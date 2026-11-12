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
printf '#!/usr/bin/env bash\nprintf "CUSTOMSHELL_TEST_INIT=1\\n"\n' \
	>"$test_root/bin/oh-my-posh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$test_root/bin/starship"
chmod +x "$test_root/bin/git" "$test_root/bin/ssh-add" "$test_root/bin/ssh-agent"
chmod +x "$test_root/bin/oh-my-posh" "$test_root/bin/starship"
chmod +x "$test_root/home/.local/share/fnm/fnm"

main_script="$(dirname "${BASH_SOURCE[0]}")/../main.sh"
HOME="$test_root/home" USER=cardi-test PATH="$test_root/bin:$PATH" \
	bash -u -c '
        source "$1"
        env_inode=$(stat -c %i "$HOME/.config/environment.d/90-customshell.conf")
        shell_env_inode=$(stat -c %i "$HOME/.config/customshell/env.sh")
        source "$1"
        declare -F Protect-Tar >/dev/null
        declare -F Unprotect-Tar >/dev/null
        declare -F list_cert_chain >/dev/null
        declare -F Show-Help >/dev/null
        declare -F checkInstalled >/dev/null && exit 1
        [[ "$IS_WORK_DEVICE" == false ]]
        [[ "$TMOUT" == -1 ]]
        [[ -f "$HOME/.config/environment.d/90-customshell.conf" ]]
        [[ "$(stat -c %i "$HOME/.config/environment.d/90-customshell.conf")" == "$env_inode" ]]
        [[ -f "$HOME/.config/customshell/env.sh" ]]
        [[ "$(stat -c %i "$HOME/.config/customshell/env.sh")" == "$shell_env_inode" ]]
        [[ -f "$HOME/.cache/customshell/ssh-agent.env" ]]
        [[ -n "$SSH_AUTH_SOCK" ]]
        [[ "$(wc -l <"$HOME/agent-starts")" == 1 ]]
        fnm_count=$(printf "%s" "$PATH" | tr ":" "\n" | grep -Fxc "$HOME/.local/share/fnm")
        [[ "$fnm_count" == 1 ]]
    ' bash "$main_script" || {
	echo "FAIL: main.sh did not tolerate repeated sourcing" >&2
	exit 1
}

HOME="$test_root/home" bash -u -c '
    PRETTY_PROMPT=none
    PROMPT_COMMAND=("printf z >>\"$HOME/prompt-hooks\";" "printf p >>\"$HOME/prompt-hooks\"")
    source "$1"
    source "$1"
    if ((BASH_VERSINFO[0] < 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] < 1))); then
        eval "$PROMPT_COMMAND"
    else
        for hook in "${PROMPT_COMMAND[@]}"; do eval "$hook"; done
    fi
    [[ "$(cat "$HOME/prompt-hooks")" == zp ]] || exit 1
    unset PROMPT_COMMAND
    source "$1"
    PROMPT_COMMAND=:
    source "$1"
    [[ "$PROMPT_COMMAND" == :* ]]
' bash "$(dirname "${BASH_SOURCE[0]}")/../integrations/prompt.sh" || {
	echo "FAIL: prompt hooks were not preserved" >&2
	exit 1
}

# Theme selection: WSL always targets a Windows-side terminal and keeps the
# glyph theme, even in a bare session such as SSH; native Linux bare sessions
# keep the ASCII fallback.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
prompt_script="$repo_root/linux/integrations/prompt.sh"

# check_prompt_selection runs prompt.sh with a prompt engine and terminal
# context, then compares the engine's configuration variable to the expectation.
check_prompt_selection() {
	local pretty="$1" is_wsl="$2" bare="$3" variable="$4" expected="$5" actual
	actual="$(PRETTY_PROMPT="$pretty" IS_WSL="$is_wsl" IS_BARE_TERMINAL="$bare" \
		PROJ_DIR="$repo_root" PATH="$test_root/bin:$PATH" bash -u -c '
        source "$1"
        printf "%s" "${!2:-}"
    ' bash "$prompt_script" "$variable")" ||
		{
			echo "FAIL: $pretty initialization failed (WSL=$is_wsl bare=$bare)" >&2
			exit 1
		}
	[[ "$actual" == "$expected" ]] || {
		echo "FAIL: $pretty under WSL=$is_wsl bare=$bare selected '$actual', expected '$expected'" >&2
		exit 1
	}
}

check_prompt_selection ohmyposh true true OMP_THEME catppuccin_gruvbox
check_prompt_selection ohmyposh false true OMP_THEME ascii
check_prompt_selection ohmyposh false false OMP_THEME catppuccin_gruvbox
check_prompt_selection starship true true STARSHIP_CONFIG \
	"$repo_root/config/starship/catppuccin-powerline.toml"
check_prompt_selection starship false true STARSHIP_CONFIG \
	"$repo_root/config/starship/plain-text-symbols.toml"
check_prompt_selection starship false false STARSHIP_CONFIG \
	"$repo_root/config/starship/catppuccin-powerline.toml"

echo "Startup tests passed"
