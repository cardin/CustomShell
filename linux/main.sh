#!/usr/bin/env bash
export LINUX_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
export PROJ_DIR="$(dirname "$LINUX_SCRIPT_DIR")"
export IS_WSL=$(uname -r | grep -i "microsoft" >/dev/null && echo true || echo false)
export PRETTY_PROMPT="ohmyposh" # 'ohmyposh' | 'starship'
export UTF8_ENABLED=$(
    [[ $(locale charmap 2>/dev/null) == UTF-8 ]] && echo true || echo false
)
if [[ ("$USER" == "root" || "$USER" == *-admin) && "$IS_WSL" = false && "$UTF8_ENABLED" = true ]]; then
    export IS_BARE_TERMINAL=true
else
    export IS_BARE_TERMINAL=false
fi
if [[ "$USER" != "cardin" ]]; then
    export IS_WORK_DEVICE=true
else
    export IS_WORK_DEVICE=false
fi

# if ~/.local/bin is not in path, add it
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
fi
# if /home/linuxbrew exists and is not in path, add it
if [ -d "/home/linuxbrew" ] && [[ ":$PATH:" != *":/home/linuxbrew/.linuxbrew/bin:"* ]]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

source "$LINUX_SCRIPT_DIR/pretty/pretty.sh"
source "$LINUX_SCRIPT_DIR/linux.sh"
source "$LINUX_SCRIPT_DIR/ssl.sh"

if [ "$IS_WSL" = true ]; then
    source "$LINUX_SCRIPT_DIR/cmd.sh"
    source "$LINUX_SCRIPT_DIR/wsl.sh"
fi

# Only show startup messages if not inside tmux
if [ -z "$TMUX" ]; then
    checkInstalled
    manShell
fi

# generate conf retroactively
source "$LINUX_SCRIPT_DIR/env.sh"
