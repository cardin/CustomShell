#!/usr/bin/env bash

# Verifies that the Linux entry point can be sourced repeatedly in a disposable
# environment without launching an SSH agent or changing real Git settings.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home" "$test_root/bin"

# Prevent the startup test from changing Git configuration or launching a real
# SSH agent outside its disposable shell.
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/git"
cat >"$test_root/bin/ssh-add" <<'EOF'
#!/usr/bin/env bash
[[ -n ${SSH_AUTH_SOCK:-} ]] && exit 0
exit 2
EOF
cat >"$test_root/bin/ssh-agent" <<'EOF'
#!/usr/bin/env bash
echo started >>"$HOME/agent-starts"
echo "SSH_AUTH_SOCK=$HOME/mock-agent.sock; export SSH_AUTH_SOCK;"
echo "SSH_AGENT_PID=12345; export SSH_AGENT_PID;"
EOF
mkdir -p "$test_root/home/.local/share/fnm"
printf '#!/usr/bin/env bash\nprintf ":\\n"\n' >"$test_root/home/.local/share/fnm/fnm"
chmod +x "$test_root/bin/git" "$test_root/bin/ssh-add" "$test_root/bin/ssh-agent"
chmod +x "$test_root/home/.local/share/fnm/fnm"

main_script="$(dirname "${BASH_SOURCE[0]}")/../main.sh"
HOME="$test_root/home" USER=cardi-test PATH="$test_root/bin:$PATH" \
    bash -u -c '
        source "$1"
        env_inode=$(stat -c %i "$HOME/.config/environment.d/90-customshell.conf")
        source "$1"
        declare -F Protect-Tar >/dev/null
        declare -F Unprotect-Tar >/dev/null
        declare -F list_cert_chain >/dev/null
        declare -F Show-Help >/dev/null
        [[ "$IS_WORK_DEVICE" == false ]]
        [[ "$GTK_OVERLAY_SCROLLING" == 0 ]]
        [[ -f "$HOME/.config/environment.d/90-customshell.conf" ]]
        [[ "$(stat -c %i "$HOME/.config/environment.d/90-customshell.conf")" == "$env_inode" ]]
        [[ -f "$HOME/.cache/customshell/ssh-agent.env" ]]
        [[ -n "$SSH_AUTH_SOCK" ]]
        [[ "$(wc -l <"$HOME/agent-starts")" == 1 ]]
        fnm_count=$(printf "%s" "$PATH" | tr ":" "\n" | grep -Fxc "$HOME/.local/share/fnm")
        [[ "$fnm_count" == 1 ]]
    ' bash "$main_script" || {
        echo "FAIL: main.sh did not tolerate repeated sourcing" >&2
        exit 1
    }

echo "Startup tests passed"
