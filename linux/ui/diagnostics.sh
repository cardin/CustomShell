#!/usr/bin/env bash

# Defines interactive startup diagnostics and the compact CustomShell command
# reference. The entry point decides whether their output should be displayed.

# checkInstalled
# Prints a compact warning for expected commands that are unavailable locally.
checkInstalled() {
	local missing=false
	local missing_marker="󰬅"
	if [[ ${UTF8_ENABLED:-false} != true || ${IS_BARE_TERMINAL:-false} == true ]]; then
		missing_marker="missing:"
	fi
	local programs=("age" "bat" "btop" "conda" "delta" "dos2unix" "fd" "fzf"
		"node" "pipx" "progress" "rg" "shfmt" "tmux" "tree" "unzip" "zip" "zoxide")

	if [[ "$IS_WSL" == false ]]; then
		programs+=("lazygit" "lazydocker" "nvitop")
	fi

	local program pattern type_output
	for program in "${programs[@]}"; do
		pattern="${program} is /mnt/"
		type_output="$(type "$program" 2>/dev/null)"
		if [[ "$type_output" == "$pattern"* || -z "$type_output" ]]; then
			echo -e -n "${Red}${missing_marker}${program} "
			missing=true
		fi
	done
	if [[ "$missing" == true ]]; then
		echo -e "${Color_Off}"
	fi
}

# Show-Help
# Displays a short reference for commonly used CustomShell and CLI commands.
Show-Help() {
	if [[ ${UTF8_ENABLED:-false} != true || ${IS_BARE_TERMINAL:-false} == true ]]; then
		echo -e "${Blue}CustomShell commands${Color_Off}"
		if [[ "$IS_WSL" == true ]]; then
			echo "wcd / wpushd / cmd / release-ram / mirror-win-ssh"
		fi
		echo "Protect-Tar / Unprotect-Tar / list_cert_chain"
		echo "z / zi / bat / tree / rg / fd / btop / ssh"
		return
	fi

	echo -e "$Blue󰗉󰗉󰗉 Show-Help 󰗉󰗉󰗉"

	if [[ "$IS_WSL" == true ]]; then
		echo -e "$Green•  wcd ~ / wpushd / cmd / dos2unix / release-ram / mirror-win-ssh / \$USERPROFILE"
	else
		echo -e "$Green• lazydocker 󰇙 lazygit 󰇙 nvitop"
	fi
	echo -e "$Green• conda / pipx / node
• z[i] / bat / tree [-L] / [Un]Protect-Tar / list_cert_chain
• btop / progress [-w -m]
• df -hl .. / du -hl [--max-depth <int>] ..
• rg <regex> [--glob ..] [--type <py>] [--no-ignore] [--hidden] [--max-depth ..] \n\
    [-l] [-B|A|C <int>] [<path> ...]
• fd <regex> [--glob ..] [--type d|f] [--no-ignore] [--hidden] [--max|min-depth ..] \n\
    [--full-path] [-e <py>] [<targetDir>] [--exec <cmd> {} /;]
• xargs -I % [-0] echo \"%\"
• ssh [-p <port>] [-NT] [-L [<local>:]<port>:<remote>:<port>] [-J <user>@<hop1>] <user>@<hop2>
• \$USER${Color_Off}"
}

export TMOUT=-1
