#!/usr/bin/env bash

# Exercises the idempotent setup helper in a disposable HOME. It verifies
# profile block insertion, replacement, and removal, link management, and that
# check/dry-run modes never change the filesystem.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT

install_script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)/install.sh"
repo_dir="$(cd -- "$(dirname -- "$install_script")/.." && pwd -P)"
entry_script="$repo_dir/linux/main.sh"
marker_begin="# >>> CustomShell >>>"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

md5_of() {
	md5sum "$1" | cut -d' ' -f1
}

espanso_root="$test_root/home/.config/espanso"
espanso_match="$espanso_root/match"
espanso_config="$espanso_root/config"

run_install() {
	HOME="$test_root/home" bash "$install_script" \
		--bashrc "$test_root/home/.bashrc" \
		--espanso-root "$espanso_root" "$@"
}

mkdir -p "$test_root/home"
printf '# my bashrc\nalias foo=bar\n' >"$test_root/home/.bashrc"
original_md5="$(md5_of "$test_root/home/.bashrc")"

# First install inserts the block once and preserves unrelated content.
first_output="$(run_install 2>&1)" || fail "install failed"
[[ "$first_output" == *"Commands:"* ]] || fail "install did not report command state"
grep -Fq "$marker_begin" "$test_root/home/.bashrc" || fail "profile block not inserted"
grep -Fq "alias foo=bar" "$test_root/home/.bashrc" || fail "unrelated profile content lost"
grep -Fq "export UV_SYSTEM_CERTS=true" "$test_root/home/.bashrc" ||
	fail "persistent environment value was not added to the profile block"
[[ "$(grep -c -F "$marker_begin" "$test_root/home/.bashrc")" == 1 ]] ||
	fail "expected exactly one managed block"

# Re-running is idempotent.
before_md5="$(md5_of "$test_root/home/.bashrc")"
run_install >/dev/null 2>&1 || fail "second install failed"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$before_md5" ]] ||
	fail "profile changed on a no-op rerun"

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

# Espanso links land in the directories Espanso expects and are idempotent.
[[ -L "$espanso_match/_base.yml" ]] || fail "base espanso link missing"
[[ -L "$espanso_config/whitelist.yml" ]] || fail "whitelist espanso link missing"
[[ "$(readlink -f "$espanso_match/_base.yml")" == "$repo_dir/config/espanso/_base.yml" ]] ||
	fail "base espanso link target is wrong"
[[ "$(readlink -f "$espanso_config/whitelist.yml")" == "$repo_dir/config/espanso/whitelist.yml" ]] ||
	fail "whitelist espanso link target is wrong"

# Check mode succeeds when configured and changes nothing.
check_md5="$(md5_of "$test_root/home/.bashrc")"
run_install --check >/dev/null 2>&1 || fail "check failed on a configured setup"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$check_md5" ]] ||
	fail "check mode modified the profile"

# A conflicting regular file is skipped without --force and backed up with it.
conflict_root="$test_root/conflict/espanso"
mkdir -p "$conflict_root/match"
printf 'user data\n' >"$conflict_root/match/_base.yml"
HOME="$test_root/home" bash "$install_script" \
	--bashrc "$test_root/conflict/.bashrc" \
	--espanso-root "$conflict_root" >/dev/null 2>&1 ||
	fail "install failed while handling a conflict"
[[ -f "$conflict_root/match/_base.yml" && ! -L "$conflict_root/match/_base.yml" ]] ||
	fail "conflicting file was replaced without --force"
HOME="$test_root/home" bash "$install_script" --force \
	--bashrc "$test_root/conflict/.bashrc" \
	--espanso-root "$conflict_root" >/dev/null 2>&1 ||
	fail "forced install failed"
[[ -L "$conflict_root/match/_base.yml" ]] || fail "forced install did not create the link"
[[ -f "$conflict_root/match/_base.yml.customshell.bak" ]] || fail "forced install did not back up"
[[ "$(cat "$conflict_root/match/_base.yml.customshell.bak")" == "user data" ]] ||
	fail "backup did not preserve the original content"

# Uninstall removes the block and managed links, restoring the original file.
run_install --uninstall >/dev/null 2>&1 || fail "uninstall failed"
[[ "$(md5_of "$test_root/home/.bashrc")" == "$original_md5" ]] ||
	fail "uninstall did not restore the original profile"
[[ ! -e "$espanso_match/_base.yml" && ! -e "$espanso_config/whitelist.yml" ]] ||
	fail "uninstall left managed links behind"
run_install --check >/dev/null 2>&1 && fail "check passed for an unconfigured setup"

# An unmarked manual source line is left untouched.
manual_rc="$test_root/manual/.bashrc"
mkdir -p "$test_root/manual"
printf '. %s\n' "$entry_script" >"$manual_rc"
manual_md5="$(md5_of "$manual_rc")"
manual_output="$(HOME="$test_root/home" bash "$install_script" \
	--bashrc "$manual_rc" --espanso-root "$test_root/manual/espanso" 2>&1)" ||
	fail "install failed on an unmarked profile"
[[ "$manual_output" == *"unmarked"* || "$manual_output" == *"already sources"* ]] ||
	fail "unmarked source line was not reported"
[[ "$(md5_of "$manual_rc")" == "$manual_md5" ]] ||
	fail "unmarked profile was modified"

# Dry-run changes nothing and creates no links.
dry_rc="$test_root/dry/.bashrc"
mkdir -p "$test_root/dry"
printf '# dry\n' >"$dry_rc"
dry_md5="$(md5_of "$dry_rc")"
HOME="$test_root/home" bash "$install_script" --dry-run \
	--bashrc "$dry_rc" --espanso-root "$test_root/dry/espanso" >/dev/null 2>&1 ||
	fail "dry-run failed"
[[ "$(md5_of "$dry_rc")" == "$dry_md5" ]] || fail "dry-run modified the profile"
[[ ! -e "$test_root/dry/espanso" ]] || fail "dry-run created espanso links"

# Help exits successfully.
bash "$install_script" --help >/dev/null 2>&1 || fail "help did not exit successfully"

echo "Install tests passed"
