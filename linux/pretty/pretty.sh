#!/usr/bin/env bash
PRETTY_SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")

source "$PRETTY_SCRIPT_DIR/colors.sh"
source "$PRETTY_SCRIPT_DIR/tool_activation.sh"
source "$PRETTY_SCRIPT_DIR/etc_inputrc.sh"

# Check what's installed
checkInstalled() {
    local missing=false

    local programs=("bat" "btop" "conda" "delta" "dos2unix" "fd" "fzf"
        "node" "pipx" "progress"
        "rg" "tmux" "tree" "unzip" "zip" "zoxide")

    if [ "$IS_WSL" = false ]; then
        programs+=("lazygit" "lazydocker" "nvitop")
    fi

    for program in "${programs[@]}"; do
        local pattern="${program} is /mnt/"
        # shellcheck disable=SC2155
        local type_output=$(type "$program" 2>/dev/null)
        if [[ ($type_output == "$pattern"*) || (! $type_output) ]]; then
            echo -e -n "${Red}󰬅$program "
            missing=true
        fi
    done
    if [ $missing = true ]; then
        echo ""
    fi
}

manShell() {
    echo -e "$Blue󰗉󰗉󰗉  manShell ()  󰗉󰗉󰗉"

    if [ "$IS_WSL" = true ]; then
        echo -e "$Green•  wcd ~ 󰇙 wpushd 󰇙 cmd 󰇙 dos2unix 󰇙 release-ram 󰇙 \$USERPROFILE"
    else
        echo -e "$Green• lazydocker 󰇙 lazygit 󰇙 nvitop"
    fi
    echo -e "$Green• list_cert_chain
• conda 󰇙 pipx 󰇙 node
• z[i] 󰇙 bat 󰇙 tree [-L] 󰇙 [un]tar_gpg
• btop 󰇙 progress [-w -m]
• df -hl .. 󰇙 du -hl [--max-depth <int>] ..
• rg <regex> [--glob ..] [--type <py>] [--no-ignore] [--hidden] [--max-depth ..] \n\
    [-l] [-B|A|C <int>] [<path> ...]
• fd <regex> [--glob ..] [--type d|f] [--no-ignore] [--hidden] [--max|min-depth ..] \n\
    [--full-path] [-e <py>] [<targetDir>] [--exec <cmd> {} /;]
• xargs -I % [-0] echo \"%\"
• ssh [-p <port>] [-NT] [-L [<local>:]<port>:<remote>:<port>] [-J <user>@<hop1>] <user>@<hop2>
• \$USER"
}

# For Tmux
export TMOUT=-1 # seconds
