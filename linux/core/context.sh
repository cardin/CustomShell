#!/usr/bin/env bash

# Detects the host, terminal, locale, prompt, and device context used by later
# startup files. This file must be sourced before platform and UI setup.

export IS_WSL="$(uname -r | grep -qi microsoft && echo true || echo false)"
export PRETTY_PROMPT="${PRETTY_PROMPT:-ohmyposh}"
export UTF8_ENABLED="$([[ $(locale charmap 2>/dev/null) == UTF-8 ]] && echo true || echo false)"
customshell_user="${USER:-$(id -un)}"
export IS_SYSADMIN="$([[ "$customshell_user" == root || "$customshell_user" == *-admin ]] && echo true || echo false)"

if [[ "$IS_SYSADMIN" == true || ("$IS_WSL" == true && -z ${WT_SESSION:-}) ]]; then
    export IS_BARE_TERMINAL=true
else
    export IS_BARE_TERMINAL=false
fi

export IS_WORK_DEVICE="$([[ "$customshell_user" != cardi* ]] && echo true || echo false)"

unset customshell_user
