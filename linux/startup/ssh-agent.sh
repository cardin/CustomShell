#!/usr/bin/env bash

# Reuses a recorded SSH agent when it is reachable, or starts and records a new
# agent for later shells. Process existence alone is not treated as attachment.

# customshell_ssh_agent_reachable
# Succeeds when SSH_AUTH_SOCK points at a reachable agent. ssh-add exits with
# status 1 when the agent is reachable but holds no identities, which still
# counts as usable; any other failure means the socket cannot be used.
customshell_ssh_agent_reachable() {
	[[ -n ${SSH_AUTH_SOCK:-} ]] || return 1
	local status=0
	ssh-add -l >/dev/null 2>&1 || status=$?
	[[ $status -eq 0 || $status -eq 1 ]]
}

if command -v ssh-agent >/dev/null 2>&1 && command -v ssh-add >/dev/null 2>&1; then
	customshell_agent_usable=false
	if customshell_ssh_agent_reachable; then
		customshell_agent_usable=true
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

		if customshell_ssh_agent_reachable; then
			customshell_agent_usable=true
		fi
	fi

	if [[ "$customshell_agent_usable" != true ]]; then
		customshell_agent_init=""
		if customshell_agent_init="$(ssh-agent -s 2>/dev/null)" &&
			[[ -n "$customshell_agent_init" ]] &&
			bash -n <<<"$customshell_agent_init" 2>/dev/null; then
			if eval "$customshell_agent_init" >/dev/null 2>&1; then
				if mkdir -p -- "$customshell_agent_dir" 2>/dev/null &&
					customshell_agent_tmp="$(mktemp "$customshell_agent_dir/.ssh-agent.env.XXXXXX" 2>/dev/null)"; then
					if chmod 600 "$customshell_agent_tmp" &&
						printf 'SSH_AUTH_SOCK=%s\nSSH_AGENT_PID=%s\n' \
							"$SSH_AUTH_SOCK" "$SSH_AGENT_PID" >"$customshell_agent_tmp" &&
						mv -f -- "$customshell_agent_tmp" "$customshell_agent_file"; then
						customshell_agent_tmp=""
					else
						rm -f -- "$customshell_agent_tmp"
					fi
				fi
			fi
		fi
	fi

	unset customshell_agent_usable
	unset customshell_agent_dir customshell_agent_file
	unset customshell_agent_name customshell_agent_value
	unset customshell_agent_init customshell_agent_tmp
fi

unset -f customshell_ssh_agent_reachable
