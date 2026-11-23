#!/usr/bin/env bash

# Shared WSL interoperability helpers. This file only defines functions; it is
# sourced by linux/platform/wsl.sh for interactive shells and by the installer
# when it generates the cmd.exe shim. Shared discovery keeps the runtime wrapper
# and the installed shim pointing at the same executable.

# customshell_is_wsl
# Returns success inside WSL. CUSTOMSHELL_IS_WSL overrides detection so tests
# can exercise both branches without a real kernel.
customshell_is_wsl() {
    case "${CUSTOMSHELL_IS_WSL:-}" in
    true) return 0 ;;
    false) return 1 ;;
    esac
    [[ "$(uname -r 2>/dev/null)" == *[Mm]icrosoft* ]]
}

# customshell_find_cmd_exe
# Prints the path to Windows cmd.exe. PATH is tried first; distributions that
# set PATH in /etc/environment replace the WSL PATH that includes the Windows
# directories, and OpenCode Desktop strips every /mnt entry from it, so fall
# back to the mounted Windows system directory. Set CUSTOMSHELL_WINDOWS_MOUNT
# when the drives are mounted outside /mnt.
customshell_find_cmd_exe() {
    local candidate mount shim
    shim="${CUSTOMSHELL_SYSTEM_BIN_DIR:-/usr/local/bin}/cmd.exe"
    candidate="$(command -v cmd.exe 2>/dev/null || true)"
    # The installer's shim exists exactly so PATH lookup succeeds; treating it as
    # the target would make the shim exec itself. Fall through to the mount.
    if [[ -n "$candidate" ]] && ! customshell_same_file "$candidate" "$shim"; then
        printf '%s\n' "$candidate"
        return 0
    fi
    mount="${CUSTOMSHELL_WINDOWS_MOUNT:-/mnt}"
    for candidate in \
        "$mount"/*/Windows/System32/cmd.exe \
        "$mount"/*/Windows/system32/cmd.exe; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# customshell_same_file
# Returns success when both paths exist and resolve to the same file.
customshell_same_file() {
    [[ -e ${1:-} && -e ${2:-} ]] || return 1
    [[ "$(readlink -f -- "$1" 2>/dev/null)" == "$(readlink -f -- "$2" 2>/dev/null)" ]]
}

# customshell_cmd_exe_usable
# Returns success when the path can be embedded in a generated script: nonempty,
# without quotes or newlines.
customshell_cmd_exe_usable() {
    local value=${1:-}
    [[ -n "$value" && "$value" != *'"'* && "$value" != *"'"* && "$value" != *$'\n'* ]]
}
