#!/usr/bin/env bash
# shellcheck disable=SC2154

# Persistent user environment values managed by CustomShell setup. The managed
# shell block exports these values, and the runtime publishes them through
# environment.d for the systemd user session. This file only defines functions
# and is sourced by linux/install.sh.

# customshell_persistent_env_lines
# Prints the export statements added to the managed shell block.
customshell_persistent_env_lines() {
    printf 'export %s=%s\n' 'UV_SYSTEM_CERTS' 'true'
}

# customshell_environment_report
# Prints persistent environment state for the check report.
customshell_environment_report() {
    say "  uv certs:   UV_SYSTEM_CERTS=${UV_SYSTEM_CERTS:-unset} (managed by the profile block)"
}
