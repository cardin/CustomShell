#!/usr/bin/env bash

# Exercises atomic and idempotent environment.d publication without touching the
# user's real configuration directory.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT

# fail
# Reports an assertion failure and terminates the environment.d test script.
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

export HOME="$test_root/home"
export GTK_OVERLAY_SCROLLING=0
mkdir -p "$HOME"
environment_script="$(dirname "${BASH_SOURCE[0]}")/../startup/environment-d.sh"

source "$environment_script"
environment_file="$HOME/.config/environment.d/90-customshell.conf"
[[ "$(<"$environment_file")" == "GTK_OVERLAY_SCROLLING=0" ]] ||
    fail "environment.d content was not generated"

original_inode="$(stat -c %i "$environment_file")"
source "$environment_script"
[[ "$(stat -c %i "$environment_file")" == "$original_inode" ]] ||
    fail "unchanged environment.d content was republished"

# mv
# Simulates a publication failure so preservation and cleanup can be asserted.
mv() { return 1; }
export GTK_OVERLAY_SCROLLING=1
source "$environment_script"
unset -f mv
[[ "$(<"$environment_file")" == "GTK_OVERLAY_SCROLLING=0" ]] ||
    fail "failed publication changed the existing environment.d file"
[[ -z "$(find "$(dirname "$environment_file")" -name '.90-customshell.conf.*' -print -quit)" ]] ||
    fail "failed publication left a temporary environment.d file"

echo "Environment tests passed"
