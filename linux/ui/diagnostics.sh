#!/usr/bin/env bash

# Defines the compact CustomShell command reference. The entry point decides
# whether its output should be displayed.

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
