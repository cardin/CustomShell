#!/usr/bin/env bash
export LINUX_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
export PROJ_DIR="$(dirname "$LINUX_SCRIPT_DIR")"
export IS_WSL=$(uname -r | grep -i "microsoft" >/dev/null && echo true || echo false)
export PRETTY_PROMPT="ohmyposh" # 'ohmyposh' | 'starship'
if [[ "$USER" == "root" || "$USER" == *-admin ]]; then
    export IS_BARE_TERMINAL=true
else
    export IS_BARE_TERMINAL=false
fi

# if ~/.local/bin is not in path, add it
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    export PATH="$HOME/.local/bin:$PATH"
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
