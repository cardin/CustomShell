#!/usr/bin/env bash
# shellcheck disable=SC2154

# Shared helpers for the CustomShell setup entry point. This file only defines
# functions and is sourced by linux/install.sh.

# say
# Prints a message to standard output.
say() {
    printf '%s\n' "$*"
}

# shell_single_quote
# Quotes a value for safe inclusion in a single-quoted shell literal.
shell_single_quote() {
    local value=$1
    value=${value//\'/\'\\\'\'}
    printf "'%s'" "$value"
}

# resolve_link_target
# Prints the physical target of a path, or an empty string when it cannot be
# resolved.
resolve_link_target() {
    readlink -f -- "$1" 2>/dev/null || true
}
