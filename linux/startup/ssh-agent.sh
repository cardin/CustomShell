#!/usr/bin/env bash

# Reuses a recorded SSH agent when it is reachable, or starts and records a new
# agent for later shells. Process existence alone is not treated as attachment.

if command -v ssh-agent >/dev/null 2>&1 && command -v ssh-add >/dev/null 2>&1; then
    customshell_agent_usable=false
    if [[ -n ${SSH_AUTH_SOCK:-} ]] && ssh-add -l >/dev/null 2>&1; then
        customshell_agent_usable=true
    else
        customshell_ssh_add_status=$?
        if [[ -n ${SSH_AUTH_SOCK:-} && $customshell_ssh_add_status -eq 1 ]]; then
            customshell_agent_usable=true
        fi
    fi

    customshell_agent_dir="${HOME:?HOME is not set}/.cache/customshell"
    customshell_agent_file="$customshell_agent_dir/ssh-agent.env"
    if [[ "$customshell_agent_usable" != true && -r "$customshell_agent_file" ]]; then
        while IFS='=' read -r customshell_agent_name customshell_agent_value; do
            case "$customshell_agent_name" in
                SSH_AUTH_SOCK) export SSH_AUTH_SOCK="$customshell_agent_value" ;;
                SSH_AGENT_PID) export SSH_AGENT_PID="$customshell_agent_value" ;;
            esac
        done <"$customshell_agent_file"

        if [[ -n ${SSH_AUTH_SOCK:-} ]] && ssh-add -l >/dev/null 2>&1; then
            customshell_agent_usable=true
        else
            customshell_ssh_add_status=$?
            if [[ -n ${SSH_AUTH_SOCK:-} && $customshell_ssh_add_status -eq 1 ]]; then
                customshell_agent_usable=true
            fi
        fi
    fi

    if [[ "$customshell_agent_usable" != true ]]; then
        customshell_agent_init=""
        if customshell_agent_init="$(ssh-agent -s 2>/dev/null)" && \
            [[ -n "$customshell_agent_init" ]] && \
            bash -n <<<"$customshell_agent_init" 2>/dev/null; then
            if eval "$customshell_agent_init" >/dev/null 2>&1; then
                if mkdir -p -- "$customshell_agent_dir" 2>/dev/null && \
                    customshell_agent_tmp="$(mktemp "$customshell_agent_dir/.ssh-agent.env.XXXXXX" 2>/dev/null)"; then
                    if chmod 600 "$customshell_agent_tmp" && \
                        printf 'SSH_AUTH_SOCK=%s\nSSH_AGENT_PID=%s\n' \
                            "$SSH_AUTH_SOCK" "$SSH_AGENT_PID" >"$customshell_agent_tmp" && \
                        mv -f -- "$customshell_agent_tmp" "$customshell_agent_file"; then
                        customshell_agent_tmp=""
                    else
                        rm -f -- "$customshell_agent_tmp"
                    fi
                fi
            fi
        fi
    fi

    unset customshell_agent_usable customshell_ssh_add_status
    unset customshell_agent_dir customshell_agent_file
    unset customshell_agent_name customshell_agent_value
    unset customshell_agent_init customshell_agent_tmp
fi
