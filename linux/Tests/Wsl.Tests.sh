#!/usr/bin/env bash

# Exercises transactional WSL SSH mirroring, failure cleanup, path validation,
# and shell-option isolation with disposable Windows and Linux homes.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT

# fail
# Reports an assertion failure and terminates the WSL test script.
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$test_root/bin" "$test_root/home/.ssh" "$test_root/windows/.ssh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/cmd.exe"
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/code"
cat >"$test_root/bin/rsync" <<'EOF'
#!/usr/bin/env bash
[[ ${RSYNC_FAIL:-false} == true ]] && exit 1
cp -a -- "$2/." "$3/"
EOF
chmod +x "$test_root/bin/code" "$test_root/bin/cmd.exe" "$test_root/bin/rsync"

echo "old" >"$test_root/home/.ssh/old-key"
echo "new" >"$test_root/windows/.ssh/new-key"

Blue="" HOME="$test_root/home" USERPROFILE="$test_root/windows" \
    PATH="$test_root/bin:$PATH"
export Blue HOME USERPROFILE PATH
unset EDITOR
source "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh"
[[ "${EDITOR:-}" == "code --wait" ]] || fail "EDITOR was not defaulted to code --wait"

export EDITOR="vim"
source "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh"
[[ "${EDITOR:-}" == "vim" ]] || fail "existing EDITOR was overwritten"
mirror-win-ssh >/dev/null || fail "mirror-win-ssh failed"
[[ -f "$HOME/.ssh/new-key" ]] || fail "new SSH content was not published"
[[ ! -e "$HOME/.ssh/old-key" ]] || fail "stale SSH content was not removed"
case $- in *e*) fail "mirror-win-ssh leaked errexit" ;; esac

echo "preserve" >"$HOME/.ssh/preserve-key"
RSYNC_FAIL=true mirror-win-ssh >/dev/null 2>&1 &&
    fail "mirror-win-ssh succeeded when staging failed"
[[ -f "$HOME/.ssh/preserve-key" ]] || fail "failed mirror changed existing SSH data"
[[ -z "$(find "$HOME" -maxdepth 1 -name '.ssh.customshell.*' -print -quit)" ]] ||
    fail "failed mirror left staging or backup directories"

USERPROFILE="" mirror-win-ssh >/dev/null 2>&1 &&
    fail "mirror-win-ssh accepted an empty USERPROFILE"

# BROWSER setup: work devices get a wrapper to the Windows browser, other
# setups and preexisting values are left alone.
browser_root="$test_root/browser"
win_root="$browser_root/winroot"
mkdir -p "$win_root/Users/testuser" "$browser_root/home"

# run_wsl_sh sources platform/wsl.sh as a work device in a disposable HOME.
run_wsl_sh() {
    Blue="" HOME="$browser_root/home" USERPROFILE="$win_root/Users/testuser" \
        IS_WORK_DEVICE=true PATH="$test_root/bin:$PATH" \
        bash -u -c "$1" bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh"
}

Blue="" HOME="$browser_root/home" USERPROFILE="$win_root/Users/testuser" \
    PATH="$test_root/bin:$PATH" bash -u -c '
    source "$1"
    [[ -z "${BROWSER:-}" ]]
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "BROWSER was set on a non-work device"

run_wsl_sh '
    source "$1"
    [[ -z "${BROWSER:-}" ]]
' || fail "BROWSER was set without a Windows browser"

edge_dir="$win_root/Program Files (x86)/Microsoft/Edge/Application"
mkdir -p "$edge_dir"
printf '#!/usr/bin/env bash\necho "FAKE-EDGE $*"\n' >"$edge_dir/msedge.exe"
chmod +x "$edge_dir/msedge.exe"

run_wsl_sh '
    source "$1"
    [[ "${BROWSER:-}" == "$HOME/.cache/customshell/windows-browser" ]] || exit 2
    wrapper="$BROWSER"
    "$wrapper" https://example.com >"$HOME/wrapper.out" || exit 3
    grep -q "^FAKE-EDGE https://example.com$" "$HOME/wrapper.out" || exit 4
    first_inode="$(stat -c %i "$wrapper")"
    source "$1"
    [[ "$(stat -c %i "$wrapper")" == "$first_inode" ]] || exit 5
' || fail "BROWSER wrapper was not generated or not idempotent"

run_wsl_sh '
    source "$1"
    [[ "${BROWSER:-}" == "$HOME/.cache/customshell/windows-browser" ]] || exit 1
    echo stale >"$BROWSER"
    unset BROWSER
    source "$1"
    grep -q "Program Files (x86)" "$BROWSER" || exit 2
    "$BROWSER" https://example.com | grep -q "^FAKE-EDGE " || exit 3
' || fail "stale BROWSER wrapper was not regenerated"

Blue="" HOME="$browser_root/home" USERPROFILE="$win_root/Users/testuser" \
    IS_WORK_DEVICE=true BROWSER=vim PATH="$test_root/bin:$PATH" bash -u -c '
    source "$1"
    [[ "$BROWSER" == vim ]]
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "existing BROWSER was overwritten"

echo "WSL tests passed"
