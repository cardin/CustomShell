#!/usr/bin/env bash

# Detects the host, terminal, locale, prompt, and device context used by later
# startup files. This file must be sourced before platform and UI setup.

export IS_WSL="$(uname -r | grep -qi microsoft && echo true || echo false)"
export PRETTY_PROMPT="${PRETTY_PROMPT:-ohmyposh}"
export UTF8_ENABLED="$([[ $(locale charmap 2>/dev/null) == UTF-8 ]] && echo true || echo false)"
customshell_user="${USER:-$(id -un)}"

if [[ "$customshell_user" == root || "$customshell_user" == *-admin || ("$IS_WSL" == true && -z ${WT_SESSION:-}) ]]; then
    export IS_BARE_TERMINAL=true
else
    export IS_BARE_TERMINAL=false
fi

# Retained for compatibility. Device detection should eventually use an
# explicit setting instead of this username heuristic.
if [[ "$customshell_user" == cardi* ]]; then
    export IS_WORK_DEVICE=false
else
    export IS_WORK_DEVICE=true
fi

unset customshell_user
