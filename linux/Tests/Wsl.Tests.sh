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
cat >"$test_root/bin/cmd.exe" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == /C && ${2:-} == start ]]; then
    printf 'FAKE-CMD %s\n' "${*:4}"
elif [[ ${1:-} == /c && ${2:-} == *USERPROFILE* ]]; then
    printf 'C:\\Users\\test\r\n'
fi
exit 0
EOF
cat >"$test_root/bin/wslpath" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
    'C:\Users\test') printf '/mnt/c/Users/test\n' ;;
    *) printf '%s\n' "${2:-}" ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/code"
cat >"$test_root/bin/rsync" <<'EOF'
#!/usr/bin/env bash
[[ ${RSYNC_FAIL:-false} == true ]] && exit 1
cp -a -- "$2/." "$3/"
EOF
chmod +x "$test_root/bin/code" "$test_root/bin/cmd.exe" "$test_root/bin/wslpath" \
    "$test_root/bin/rsync"

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

# USERPROFILE derivation: WSLENV only reaches shells that wsl.exe starts, so
# startup derives the translated Windows profile path through cmd.exe when the
# variable is absent, as in sshd, `su -`, and systemd service sessions.
profile_root="$test_root/profile"
mkdir -p "$profile_root/home" "$profile_root/empty"

Blue="" HOME="$profile_root/home" PATH="$test_root/bin:$PATH" \
    bash -u -c '
    unset USERPROFILE
    source "$1" >"$HOME/derived.out"
    [[ "${USERPROFILE:-}" == /mnt/c/Users/test ]] || exit 2
    grep -q "Need to share WSL variable" "$HOME/derived.out" && exit 3
    exit 0
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "USERPROFILE was not derived through cmd.exe"

# Without Windows command access the variable stays unset and the warning shows.
Blue="" HOME="$profile_root/home" PATH="/usr/bin:/bin" \
    CUSTOMSHELL_WINDOWS_MOUNT="$profile_root/empty" \
    bash -u -c '
    unset USERPROFILE BROWSER
    source "$1" >"$HOME/no-cmd.out"
    [[ -z "${USERPROFILE:-}" ]] || exit 2
    grep -q "Need to share WSL variable" "$HOME/no-cmd.out" || exit 3
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "USERPROFILE was set without Windows command access"

# BROWSER setup: every WSL session gets a wrapper that hands links to the
# default Windows browser through cmd.exe; preexisting values are left alone.
# The sources above already exported a value against the disposable browser
# home, so clear it before exercising the wrapper explicitly below.
browser_root="$test_root/browser"
unset BROWSER
mkdir -p "$browser_root/home"

# run_wsl_sh sources platform/wsl.sh in a disposable HOME with the mock
# Windows commands on PATH.
run_wsl_sh() {
    Blue="" HOME="$browser_root/home" PATH="$test_root/bin:$PATH" \
        bash -u -c "$1" bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh"
}

run_wsl_sh '
    source "$1"
    [[ "${BROWSER:-}" == "$HOME/.cache/customshell/windows-browser" ]] || exit 2
    wrapper="$BROWSER"
    "$wrapper" https://example.com >"$HOME/wrapper.out" || exit 3
    grep -q "^FAKE-CMD https://example.com$" "$HOME/wrapper.out" || exit 4
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
    grep -q "/C start" "$BROWSER" || exit 2
    "$BROWSER" https://example.com | grep -q "^FAKE-CMD " || exit 3
' || fail "stale BROWSER wrapper was not regenerated"

# Without cmd.exe on PATH, the wrapper must find the mounted Windows binary.
win_mount="$browser_root/winmount"
mkdir -p "$win_mount/c/Windows/System32"
cat >"$win_mount/c/Windows/System32/cmd.exe" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == /C && ${2:-} == start ]]; then
    printf 'FAKE-MOUNT-CMD %s\n' "${*:4}"
fi
exit 0
EOF
chmod +x "$win_mount/c/Windows/System32/cmd.exe"

Blue="" HOME="$browser_root/home" PATH="/usr/bin:/bin" \
    USERPROFILE="$browser_root/home" CUSTOMSHELL_WINDOWS_MOUNT="$win_mount" \
    bash -u -c '
    source "$1"
    [[ "${BROWSER:-}" == "$HOME/.cache/customshell/windows-browser" ]] || exit 2
    "$BROWSER" https://example.com | grep -q "^FAKE-MOUNT-CMD https://example.com$" || exit 3
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "BROWSER wrapper did not use the mounted Windows cmd.exe"

# With neither cmd.exe on PATH nor a Windows mount, BROWSER is left unset.
mkdir -p "$browser_root/empty"
Blue="" HOME="$browser_root/home" PATH="/usr/bin:/bin" \
    USERPROFILE="$browser_root/home" CUSTOMSHELL_WINDOWS_MOUNT="$browser_root/empty" \
    bash -u -c '
    source "$1"
    [[ -z "${BROWSER:-}" ]]
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "BROWSER was set without Windows command access"

Blue="" HOME="$browser_root/home" PATH="$test_root/bin:$PATH" BROWSER=vim \
    bash -u -c '
    source "$1"
    [[ "$BROWSER" == vim ]]
' bash "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh" ||
    fail "existing BROWSER was overwritten"

echo "WSL tests passed"
