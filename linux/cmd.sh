#!/usr/bin/env bash
############
# Helper scripts for WSL <-> CMD usage.
# Windows backslash may be used, it's luck-based.
# So try to use UNIX forward slash if possible.
############

############
# `cd`, except input is a Windows-style path.
############
wcd() { cd "$(wslpath "$1")" || exit; }

############
# `pushd`, except input is a Windows-style path.
############
wpushd() { pushd "$(wslpath "$1")" || exit; }

############
# Runs a command in CMD.exe
############
cmd() { cmd.exe /C "$@"; }
