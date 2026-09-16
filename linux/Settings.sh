#!/usr/bin/env bash
# shellcheck disable=SC2034

# Defines the expected commands reported by the Linux setup helper. Missing
# commands are advisory and do not cause installation or checks to fail.
CUSTOMSHELL_REQUIRED_COMMANDS=(
	"age"
	"bat"
	"btop"
	"conda"
	"delta"
	"dos2unix"
	"fd"
	"fzf"
	"jq"
	"node"
	"pipx"
	"progress"
	"realpath"
	"rg"
	"shfmt"
	"tmux"
	"tree"
	"unzip"
	"zip"
	"zoxide"
)

CUSTOMSHELL_NON_WSL_REQUIRED_COMMANDS=(
	"lazygit"
	"lazydocker"
	"nvitop"
)
