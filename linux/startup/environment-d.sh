#!/usr/bin/env bash

# Publishes CustomShell's selected environment variables atomically so supported
# GUI and user services never observe a partially generated configuration.

customshell_env_dir="${HOME:?HOME is not set}/.config/environment.d"
customshell_env_file="$customshell_env_dir/90-customshell.conf"
customshell_file_envs=("REQUESTS_CA_BUNDLE" "NODE_EXTRA_CA_CERTS")
customshell_value_envs=("GTK_OVERLAY_SCROLLING")
customshell_env_tmp=""

if mkdir -p -- "$customshell_env_dir" && \
    customshell_env_tmp="$(mktemp "$customshell_env_dir/.90-customshell.conf.XXXXXX")"; then
    chmod 600 "$customshell_env_tmp"

    for customshell_env_name in "${customshell_file_envs[@]}"; do
        if [[ -n "${!customshell_env_name+x}" && -f "${!customshell_env_name}" ]]; then
            customshell_env_value="${!customshell_env_name}"
            if [[ "$customshell_env_value" != *$'\n'* && "$customshell_env_value" != *'$'* ]]; then
                printf '%s=%s\n' "$customshell_env_name" "$customshell_env_value" >>"$customshell_env_tmp"
            fi
        fi
    done
    for customshell_env_name in "${customshell_value_envs[@]}"; do
        if [[ -n "${!customshell_env_name+x}" ]]; then
            customshell_env_value="${!customshell_env_name}"
            if [[ "$customshell_env_value" != *$'\n'* && "$customshell_env_value" != *'$'* ]]; then
                printf '%s=%s\n' "$customshell_env_name" "$customshell_env_value" >>"$customshell_env_tmp"
            fi
        fi
    done

    if [[ -f "$customshell_env_file" ]] && cmp -s -- "$customshell_env_tmp" "$customshell_env_file"; then
        rm -f -- "$customshell_env_tmp"
    elif mv -f -- "$customshell_env_tmp" "$customshell_env_file"; then
        customshell_env_tmp=""
    fi
fi

[[ -z "$customshell_env_tmp" ]] || rm -f -- "$customshell_env_tmp"
unset customshell_env_dir customshell_env_file customshell_env_tmp
unset customshell_file_envs customshell_value_envs
unset customshell_env_name customshell_env_value
