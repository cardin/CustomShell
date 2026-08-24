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
cat >"$test_root/bin/rsync" <<'EOF'
#!/usr/bin/env bash
[[ ${RSYNC_FAIL:-false} == true ]] && exit 1
cp -a -- "$2/." "$3/"
EOF
chmod +x "$test_root/bin/cmd.exe" "$test_root/bin/rsync"

echo "old" >"$test_root/home/.ssh/old-key"
echo "new" >"$test_root/windows/.ssh/new-key"

Blue="" HOME="$test_root/home" USERPROFILE="$test_root/windows" \
    PATH="$test_root/bin:$PATH"
export Blue HOME USERPROFILE PATH
source "$(dirname "${BASH_SOURCE[0]}")/../platform/wsl.sh"

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

echo "WSL tests passed"
