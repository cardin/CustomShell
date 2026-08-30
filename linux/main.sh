#!/usr/bin/env bash
# shellcheck disable=SC1090

# Public entry point for the Linux and WSL CustomShell configuration. It loads
# purpose-specific files in dependency order and gates interactive-only setup.
CUSTOMSHELL_LINUX_DIR="$({ cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P; })"
export CUSTOMSHELL_LINUX_DIR
# Compatibility alias for shells or local extensions that used the old name.
export LINUX_SCRIPT_DIR="$CUSTOMSHELL_LINUX_DIR"
export PROJ_DIR="$(dirname -- "$CUSTOMSHELL_LINUX_DIR")"

source "$CUSTOMSHELL_LINUX_DIR/core/context.sh"
source "$CUSTOMSHELL_LINUX_DIR/core/paths.sh"

source "$CUSTOMSHELL_LINUX_DIR/ui/colors.sh"
source "$CUSTOMSHELL_LINUX_DIR/commands/archive.sh"
source "$CUSTOMSHELL_LINUX_DIR/commands/certificates.sh"
source "$CUSTOMSHELL_LINUX_DIR/commands/utilities.sh"

if [[ "$IS_WSL" == true ]]; then
    source "$CUSTOMSHELL_LINUX_DIR/platform/wsl.sh"
fi

source "$CUSTOMSHELL_LINUX_DIR/startup/certificates.sh"
source "$CUSTOMSHELL_LINUX_DIR/startup/desktop.sh"
source "$CUSTOMSHELL_LINUX_DIR/integrations/tools.sh"

if [[ $- == *i* ]]; then
    source "$CUSTOMSHELL_LINUX_DIR/integrations/prompt.sh"
    source "$CUSTOMSHELL_LINUX_DIR/ui/readline.sh"
fi

source "$CUSTOMSHELL_LINUX_DIR/startup/ssh-agent.sh"
source "$CUSTOMSHELL_LINUX_DIR/startup/git.sh"
source "$CUSTOMSHELL_LINUX_DIR/startup/environment-d.sh"

source "$CUSTOMSHELL_LINUX_DIR/ui/diagnostics.sh"
if [[ $- == *i* && -z ${TMUX:-} && ${TERM:-dumb} != dumb && \
    ${CUSTOMSHELL_SUPPRESS_STARTUP_OUTPUT:-false} != true && \
    ${CUSTOMSHELL_DIAGNOSTICS_SHOWN:-false} != true ]]; then
    checkInstalled
    Show-Help
    export CUSTOMSHELL_DIAGNOSTICS_SHOWN=true
fi
