#!/usr/bin/env bash
current_dir="$(dirname "${BASH_SOURCE[0]}")"

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

source "$current_dir/pretty/pretty.sh"
source "$current_dir/linux.sh"
source "$current_dir/ssl.sh"

if [ "$IS_WSL" = true ]; then
    source "$current_dir/cmd.sh"
    source "$current_dir/wsl.sh"
fi

# Only show startup messages if not inside tmux
if [ -z "$TMUX" ]; then
    checkInstalled
    manShell
fi
