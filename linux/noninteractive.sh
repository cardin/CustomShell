#!/usr/bin/env bash

# Environment-only entry point for non-interactive Bash. The managed profile
# blocks export BASH_ENV so that `bash -c` and shell scripts started outside an
# interactive or login session receive the same user-local command paths and
# portable defaults.
#
# It runs for every non-interactive Bash, including scripts started by build
# tools, so it must stay silent, idempotent, and free of interactive setup: no
# prompt, terminal, certificate, or SSH-agent initialization.

__customshell_noninteractive_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"

# paths.sh requires HOME; both guards keep an unusual environment quiet instead
# of failing the calling script.
if [[ -n "${HOME:-}" && -r "$__customshell_noninteractive_dir/core/paths.sh" ]]; then
	. "$__customshell_noninteractive_dir/core/paths.sh"
fi
if [[ -r "$__customshell_noninteractive_dir/core/portable-env.sh" ]]; then
	. "$__customshell_noninteractive_dir/core/portable-env.sh"
fi

unset __customshell_noninteractive_dir
