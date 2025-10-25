#!/usr/bin/env bash
PRETTY_SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

source "$PRETTY_SCRIPT_DIR/echo.sh"
source "$PRETTY_SCRIPT_DIR/tool_formatting.sh"
source "$PRETTY_SCRIPT_DIR/etc_inputrc.sh"

# Check what's installed
checkInstalled() {
    local missing=false
    local -r programs=("bat" "btop" "conda" "delta" "dos2unix" "fd" "fzf"
        "lazygit" "lazydocker" "node" "nvitop" "pipx" "progress"
        "rg" "tmux" "tree" "unzip" "uv" "zip" "zoxide")

    for program in "${programs[@]}"; do
        local pattern="${program} is /mnt/"
        # shellcheck disable=SC2155
        local type_output=$(type "$program" 2>/dev/null)
        if [[ ($type_output == "$pattern"*) || (! $type_output) ]]; then
            echo -n "󰬅$program "
            missing=true
        fi
    done
    if [ $missing = true ]; then
        echo ""
    fi
}

helpMe() {
    echo -e "$Blue" "󰗉󰗉󰗉  helpMe()  󰗉󰗉󰗉"
    echo -e "$Purple" \
"•  wcd ~; wpushd; cmd; dos2unix; release-ram
• list_cert_chain
• lazydocker; lazygit
• conda; pipx; uv; node
• z[i]; bat; tree [-L]; [un]tar_gpg
• btop; progress [-w -m]
• df -hl ...; du -hl [--max-depth <int>] ...
• rg <regex> [--glob <str>] [--type <py>] [--no-ignore] [--hidden] [-B|A|C <int>] [-l] [<path> ...]
• fd <regex> [--glob <str>] [-e <py>] [--type d|f] [--no-ignore] [--hidden] [<dir>] [--full-path] [--exec <cmd> {} /;]
• xargs -I % [-0] echo \"%\"
• ssh [-p <port>] [-N] [-L <localPort>:localhost:<remotePort>] [-J <user>@<hop1>] <user>@<remoteServer>
• \$USERPROFILE; \$USER"
}

# For Tmux
export TMOUT=604800 # seconds
