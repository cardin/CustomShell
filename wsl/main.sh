#!/usr/bin/env bash
current_dir="$(dirname "${BASH_SOURCE[0]}")"

export IS_WSL=$(uname -r | grep -i "microsoft" > /dev/null && echo true || echo false)

source "$current_dir/pretty/pretty.sh"
source "$current_dir/linux.sh"
source "$current_dir/ssl.sh"
source "$current_dir/cmd.sh"
source "$current_dir/wsl.sh"

checkInstalled
manShell
