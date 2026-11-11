#!/usr/bin/env bash
# shellcheck disable=SC2016

# Exercises the idempotent setup helper in a disposable HOME. It verifies
# profile block insertion, replacement, and removal, link management, and that
# check/dry-run modes never change the filesystem.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT
export XDG_STATE_HOME="$test_root/state"

install_script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/install.sh"
repo_dir="$(cd -- "$(dirname -- "$install_script")/.." && pwd -P)"
entry_script="$repo_dir/linux/main.sh"
marker_begin="# >>> CustomShell >>>"
profile_marker_begin="# >>> CustomShell profile >>>"
profile_file="$test_root/home/.profile"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# The command inventory comes from settings, with native-only entries omitted
# under WSL.
bash -u -c '
	source "$1"
	source "$2"
	CUSTOMSHELL_REQUIRED_COMMANDS=(sh customshell-common-missing)
	CUSTOMSHELL_NON_WSL_REQUIRED_COMMANDS=(customshell-native-missing)

	uname() { printf "%s\n" "Linux microsoft"; }
	check_commands
	[[ "${missing_commands[*]}" == "customshell-common-missing" ]]

	uname() { printf "%s\n" "Linux native"; }
	check_commands
	[[ "${missing_commands[*]}" == \
		"customshell-common-missing customshell-native-missing" ]]
' bash "$repo_dir/linux/Settings.sh" "$repo_dir/linux/install/checks.sh" ||
	fail "configured command inventory was not applied"

# A failed Git update removes newly-created ownership state.
git_failure_home="$test_root/git-failure"
mkdir -p "$git_failure_home"
bash -u -c '
	export HOME=$1
	dry_run=false
	say() { :; }
	git() { return 1; }
	source "$2"
	customshell_git_install && exit 1
	[[ ! -e "$customshell_git_state_file" && ! -d "$customshell_git_state_dir" ]]
' bash "$git_failure_home" "$repo_dir/linux/install/git.sh" ||
	fail "failed Git configuration left ownership state behind"

md5_of() {
	md5sum "$1" | cut -d' ' -f1
}

run_install() {
	HOME="$test_root/home" XDG_BIN_HOME='' GIT_CONFIG_GLOBAL="$test_root/home/.gitconfig" \
		bash "$install_script" \
		--bashrc "$test_root/home/.bashrc" \
		--profile "$profile_file" "$@"
}

mkdir -p "$test_root/home"
printf '# my bashrc\nalias foo=bar\n' >"$test_root/home/.bashrc"
printf '%s\n' \
	'# my profile' \
	'alias keep-profile=me' \
	'' \
	'if [ -n "$BASH_VERSION" ]; then' \
	'    : bash-specific initialization' \
	'fi' >"$profile_file"
GIT_CONFIG_GLOBAL="$test_root/home/.gitconfig" \
	git config --global --add credential.helper store || fail "failed to stage Git helper"
GIT_CONFIG_GLOBAL="$test_root/home/.gitconfig" \
	git config --global --add credential.helper manager-core || fail "failed to stage second Git helper"
original_md5="$(md5_of "$test_root/home/.bashrc")"
original_profile_md5="$(md5_of "$profile_file")"

# First install inserts the block once and preserves unrelated content.
first_output="$(run_install 2>&1)" || fail "install failed"
[[ "$first_output" == *"Commands:"* ]] || fail "install did not report command state"
grep -Fq "$marker_begin" "$test_root/home/.bashrc" || fail "profile block not inserted"
grep -Fq "alias foo=bar" "$test_root/home/.bashrc" || fail "unrelated profile content lost"
grep -Fq "export GTK_OVERLAY_SCROLLING=0" "$test_root/home/.bashrc" ||
	fail "GTK environment value was not added to the profile block"
grep -Fq "export UV_SYSTEM_CERTS=true" "$test_root/home/.bashrc" ||
	fail "uv environment value was not added to the profile block"
[[ "$(GIT_CONFIG_GLOBAL="$test_root/home/.gitconfig" git config --global --get-all credential.helper)" == "cache --timeout=21600" ]] || fail "Git credential helper was not configured"
[[ -f "$XDG_STATE_HOME/customshell/git-credential-helper" ]] ||
	fail "previous Git credential helper was not recorded"
[[ "$(grep -c -F "$marker_begin" "$test_root/home/.bashrc")" == 1 ]] ||
	fail "expected exactly one managed block"

grep -Fq "$profile_marker_begin" "$profile_file" || fail "POSIX login block not inserted"
grep -Fq 'alias keep-profile=me' "$profile_file" || fail "unrelated login profile content lost"
[[ "$(grep -c -F "$profile_marker_begin" "$profile_file")" == 1 ]] ||
	fail "expected exactly one managed POSIX login block"
profile_block_line="$(grep -n -F "$profile_marker_begin" "$profile_file" | cut -d: -f1)"
bash_version_line="$(grep -n -F 'if [ -n "$BASH_VERSION" ]' "$profile_file" | cut -d: -f1)"
[[ "$profile_block_line" -lt "$bash_version_line" ]] ||
	fail "POSIX login block is not before Bash-specific initialization"
grep -Fq '. "${HOME}/.config/customshell/env.sh"' "$profile_file" ||
	fail "POSIX login block does not source the shell environment artifact"

# Re-running is idempotent.
before_md5="$(md5_of "$test_root/home/.bashrc")"
before_profile_md5="$(md5_of "$profile_file")"
run_install >/dev/null 2>&1 || fail "second install failed"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$before_md5" ]] ||
	fail "profile changed on a no-op rerun"
[[ "$(md5_of "$profile_file")" == "$before_profile_md5" ]] ||
	fail "POSIX login profile changed on a no-op rerun"

# A stale block is rewritten in place without duplication.
if ! grep -Fq "/old/location/linux/main.sh" "$test_root/home/.bashrc"; then
	perl -0pi -e "s#^\.\s+'?[^'\n]*/linux/main\.sh'?\$#. '/old/location/linux/main.sh'#m" \
		"$test_root/home/.bashrc" || fail "failed to stage a stale block"
fi
run_install >/dev/null 2>&1 || fail "install over stale block failed"
grep -Fq "$entry_script" "$test_root/home/.bashrc" || fail "stale block was not updated"
grep -Fq "/old/location/linux/main.sh" "$test_root/home/.bashrc" && fail "stale path remained"
[[ "$(grep -c -F "$marker_begin" "$test_root/home/.bashrc")" == 1 ]] ||
	fail "stale rewrite duplicated the block"

# A stale POSIX login block is rewritten in place without duplication.
perl -0pi -e 's#\.config/customshell/env\.sh#.config/customshell/old.sh#g' "$profile_file" ||
	fail "failed to stage a stale POSIX login block"
run_install >/dev/null 2>&1 || fail "install over stale POSIX login block failed"
grep -Fq '.config/customshell/env.sh' "$profile_file" ||
	fail "stale POSIX login block was not updated"
grep -Fq '.config/customshell/old.sh' "$profile_file" && fail "stale POSIX login path remained"
[[ "$(grep -c -F "$profile_marker_begin" "$profile_file")" == 1 ]] ||
	fail "stale POSIX login rewrite duplicated the block"

# POSIX login shells and Bash login shells must inherit the generated exports
# even when .bashrc returns immediately for non-interactive shells.
login_home="$test_root/login-home"
mkdir -p "$login_home"
cp "$profile_file" "$login_home/.profile"
printf '%s\n' 'case $- in' '    *i*) ;;' '      *) return;;' 'esac' >"$login_home/.bashrc"
login_cert_dir="$test_root/login-certs"
mkdir -p "$login_cert_dir"
login_cert="$login_cert_dir/ca bundle's;test.pem"
printf 'test certificate\n' >"$login_cert"
HOME="$login_home" \
	NODE_EXTRA_CA_CERTS="$login_cert" \
	REQUESTS_CA_BUNDLE="$login_cert" \
	GTK_OVERLAY_SCROLLING=0 \
	UV_SYSTEM_CERTS=true \
	bash -c 'source "$1"' bash "$repo_dir/linux/startup/environment-d.sh" ||
	fail "failed to generate the login environment artifact"
for login_shell in sh bash; do
	login_values="$(
		env -i HOME="$login_home" PATH=/usr/bin:/bin "$login_shell" -lc \
			'printf "%s\n%s\n" "$NODE_EXTRA_CA_CERTS" "$REQUESTS_CA_BUNDLE"'
	)" || fail "$login_shell -lc failed to start"
	[[ "$login_values" == "$login_cert"$'\n'"$login_cert" ]] ||
		fail "$login_shell -lc did not inherit the certificate variables"
done

# A missing runtime artifact is a no-op, not a login-shell failure.
rm -f -- "$login_home/.config/customshell/env.sh"
login_values="$(
	env -i HOME="$login_home" PATH=/usr/bin:/bin sh -lc \
		'printf "%s" "${NODE_EXTRA_CA_CERTS-unset}"'
)" || fail "sh -lc failed when the login environment artifact was missing"
[[ "$login_values" == unset ]] ||
	fail "missing login environment artifact still exported a value"

# The fd shim exposes fdfind under its expected name so scripts and
# non-interactive shells see it, not only interactive aliases.
fd_shim="$test_root/home/.local/bin/fd"
if command -v fdfind >/dev/null 2>&1; then
	[[ -L "$fd_shim" ]] || fail "fd shim missing"
	[[ "$(readlink -f "$fd_shim")" == "$(readlink -f "$(command -v fdfind)")" ]] ||
		fail "fd shim target is wrong"
fi

# Check mode succeeds when configured and changes nothing.
check_md5="$(md5_of "$test_root/home/.bashrc")"
check_profile_md5="$(md5_of "$profile_file")"
run_install --check >/dev/null 2>&1 || fail "check failed on a configured setup"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$check_md5" ]] ||
	fail "check mode modified the profile"
[[ "$(md5_of "$profile_file")" == "$check_profile_md5" ]] ||
	fail "check mode modified the POSIX login profile"

# Uninstall removes the block and managed links, restoring the original file.
environment_file="$test_root/home/.config/environment.d/90-customshell.conf"
shell_env_file="$test_root/home/.config/customshell/env.sh"
mkdir -p "$(dirname -- "$environment_file")" "$(dirname -- "$shell_env_file")"
printf 'GTK_OVERLAY_SCROLLING=0\n' >"$environment_file"
printf '# generated\n' >"$shell_env_file"
run_install --uninstall --dry-run >/dev/null 2>&1 || fail "uninstall dry run failed"
[[ -f "$environment_file" ]] || fail "uninstall dry run removed the environment.d file"
[[ -f "$shell_env_file" ]] || fail "uninstall dry run removed the shell environment file"
run_install --uninstall >/dev/null 2>&1 || fail "uninstall failed"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$original_md5" ]] ||
	fail "uninstall did not restore the original profile"
[[ "$(md5_of "$profile_file")" == "$original_profile_md5" ]] ||
	fail "uninstall did not restore the original POSIX login profile"
[[ ! -e "$profile_file.customshell.bak" ]] || fail "uninstall left a profile backup"
[[ ! -e "$environment_file" ]] || fail "uninstall left the environment.d file behind"
[[ ! -e "$shell_env_file" ]] || fail "uninstall left the shell environment file behind"
if command -v fdfind >/dev/null 2>&1; then
	[[ ! -e "$fd_shim" && ! -L "$fd_shim" ]] || fail "uninstall left the fd shim behind"
fi
[[ "$(GIT_CONFIG_GLOBAL="$test_root/home/.gitconfig" git config --global --get-all credential.helper)" == $'store\nmanager-core' ]] || fail "uninstall did not restore the previous Git credential helpers"
[[ ! -e "$XDG_STATE_HOME/customshell/git-credential-helper" ]] ||
	fail "uninstall left Git credential helper state behind"
run_install --check >/dev/null 2>&1 && fail "check passed for an unconfigured setup"

# An unmarked manual source line is left untouched.
manual_rc="$test_root/manual/.bashrc"
mkdir -p "$test_root/manual"
printf '. %s\n' "$entry_script" >"$manual_rc"
manual_md5="$(md5_of "$manual_rc")"
manual_output="$(HOME="$test_root/home" bash "$install_script" \
	--bashrc "$manual_rc" 2>&1)" ||
	fail "install failed on an unmarked profile"
[[ "$manual_output" == *"unmarked"* || "$manual_output" == *"already sources"* ]] ||
	fail "unmarked source line was not reported"
[[ "$(md5_of "$manual_rc")" == "$manual_md5" ]] ||
	fail "unmarked profile was modified"

# A malformed managed block is refused instead of rewritten, so unrelated rc
# content cannot be lost to unbalanced markers.
malformed_rc="$test_root/malformed/.bashrc"
mkdir -p "$test_root/malformed"
printf '# before\n%s\n# orphaned customshell line\nalias keep=me\n' "$marker_begin" >"$malformed_rc"
malformed_md5="$(md5_of "$malformed_rc")"
if HOME="$test_root/home" bash "$install_script" \
	--bashrc "$malformed_rc" >/dev/null 2>&1; then
	fail "install accepted a malformed managed block"
fi
[[ "$(md5_of "$malformed_rc")" == "$malformed_md5" ]] ||
	fail "malformed profile was modified"
grep -Fq 'alias keep=me' "$malformed_rc" || fail "malformed profile lost unrelated content"
HOME="$test_root/home" bash "$install_script" --check \
	--bashrc "$malformed_rc" >/dev/null 2>&1 &&
	fail "check passed for a malformed managed block"

# A malformed POSIX login block is refused instead of rewritten.
malformed_profile_dir="$test_root/malformed-profile"
mkdir -p "$malformed_profile_dir"
printf '# valid bashrc\n' >"$malformed_profile_dir/.bashrc"
malformed_login_profile="$malformed_profile_dir/.profile"
printf '# before\n%s\n# orphaned customshell line\nalias keep-login=me\n' \
	"$profile_marker_begin" >"$malformed_login_profile"
malformed_login_md5="$(md5_of "$malformed_login_profile")"
if HOME="$test_root/home" bash "$install_script" \
	--bashrc "$malformed_profile_dir/.bashrc" \
	--profile "$malformed_login_profile" >/dev/null 2>&1; then
	fail "install accepted a malformed POSIX login block"
fi
[[ "$(md5_of "$malformed_login_profile")" == "$malformed_login_md5" ]] ||
	fail "malformed POSIX login profile was modified"
grep -Fq 'alias keep-login=me' "$malformed_login_profile" ||
	fail "malformed POSIX login profile lost unrelated content"
HOME="$test_root/home" bash "$install_script" --check \
	--bashrc "$malformed_profile_dir/.bashrc" \
	--profile "$malformed_login_profile" >/dev/null 2>&1 &&
	fail "check passed for a malformed POSIX login block"

# Dry-run changes nothing and creates no links.
dry_rc="$test_root/dry/.bashrc"
dry_profile="$test_root/dry/.profile"
dry_bin="$test_root/dry/bin"
mkdir -p "$test_root/dry"
printf '# dry\n' >"$dry_rc"
printf '# dry profile\n' >"$dry_profile"
dry_md5="$(md5_of "$dry_rc")"
dry_profile_md5="$(md5_of "$dry_profile")"
HOME="$test_root/home" XDG_BIN_HOME="$dry_bin" bash "$install_script" --dry-run \
	--bashrc "$dry_rc" --profile "$dry_profile" >/dev/null 2>&1 ||
	fail "dry-run failed"
[[ "$(md5_of "$dry_rc")" == "$dry_md5" ]] || fail "dry-run modified the profile"
[[ "$(md5_of "$dry_profile")" == "$dry_profile_md5" ]] ||
	fail "dry-run modified the POSIX login profile"
[[ ! -e "$dry_bin/fd" ]] || fail "dry-run created the fd shim"

# Help exits successfully.
bash "$install_script" --help >/dev/null 2>&1 || fail "help did not exit successfully"

echo "Install tests passed"
