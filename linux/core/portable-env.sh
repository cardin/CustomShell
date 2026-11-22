#!/bin/sh

# Fill portable environment defaults without replacing configured values.
# PROJECTS_W is the Windows projects directory seen from Linux; it needs
# USERPROFILE, which WSL startup derives when it can.
: "${TMPDIR:=/tmp}"
export TMPDIR
: "${PROJECTS_L:=$HOME/projects_l}"
export PROJECTS_L
if [ -n "${USERPROFILE:-}" ]; then
	: "${PROJECTS_W:=$USERPROFILE/projects_w}"
	export PROJECTS_W
fi
