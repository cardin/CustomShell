#!/usr/bin/env bash
# shellcheck disable=SC2154

# Read-only setup checks. This file only defines functions and is sourced by
# linux/install.sh.

check_failures=0
missing_commands=()

# check_commands
# Records expected commands that are unavailable locally.
check_commands() {
	local programs=("${CUSTOMSHELL_REQUIRED_COMMANDS[@]}")
	if ! uname -r | grep -qi microsoft; then
		programs+=("${CUSTOMSHELL_NON_WSL_REQUIRED_COMMANDS[@]}")
	fi

	local program
	missing_commands=()
	for program in "${programs[@]}"; do
		command -v "$program" >/dev/null 2>&1 || missing_commands+=("$program")
	done
}

# report_commands
# Prints the state of the expected commands as a single advisory line. Missing
# commands never fail the run.
report_commands() {
	check_commands
	if [[ ${#missing_commands[@]} -eq 0 ]]; then
		say "Commands: all expected commands found"
	else
		say "Commands: missing: ${missing_commands[*]}"
	fi
}

# report_checks
# Prints the setup state and returns non-zero when a required item is missing or
# stale. Advisories do not fail the run.
report_checks() {
	check_failures=0

	say "CustomShell setup check"
	say "  repository: $project_dir"

	local profile_state
	profile_state="$(profile_block_state)"
	if [[ "$profile_state" == complete ]]; then
		if render_profile write | cmp -s - "$bashrc"; then
			say "  profile:    current ($bashrc)"
		else
			say "  profile:    stale ($bashrc) - run install.sh"
			check_failures=$((check_failures + 1))
		fi
	elif [[ "$profile_state" == invalid ]]; then
		say "  profile:    malformed CustomShell block ($bashrc) - fix the markers"
		check_failures=$((check_failures + 1))
	elif profile_has_unmarked_source; then
		say "  profile:    manually sourced and unmanaged ($bashrc)"
	else
		say "  profile:    not configured ($bashrc) - run install.sh"
		check_failures=$((check_failures + 1))
	fi

	local posix_profile_state
	posix_profile_state="$(posix_profile_block_state)"
	if [[ "$posix_profile_state" == complete ]]; then
		if render_posix_profile write | cmp -s - "$profile_file"; then
			say "  login:      current ($profile_file)"
		else
			say "  login:      stale ($profile_file) - run install.sh"
			check_failures=$((check_failures + 1))
		fi
	elif [[ "$posix_profile_state" == invalid ]]; then
		say "  login:      malformed CustomShell block ($profile_file) - fix the markers"
		check_failures=$((check_failures + 1))
	else
		say "  login:      not configured ($profile_file) - run install.sh"
		check_failures=$((check_failures + 1))
	fi

	local customshell_login_env="${HOME:?HOME is not set}/.config/customshell/env.sh"
	if [[ -r "$customshell_login_env" ]]; then
		say "  login env:  published ($customshell_login_env)"
	else
		say "  login env:  not generated yet (runtime startup publishes it)"
	fi

	if ! customshell_shims_check; then
		check_failures=$((check_failures + 1))
	fi

	customshell_environment_report

	if [[ -n ${CUSTOM_CA_CERT:-} ]]; then
		if [[ -f ${CUSTOM_CA_CERT:-} ]]; then
			say "  CA cert:    configured"
		else
			say "  CA cert:    CUSTOM_CA_CERT does not exist: ${CUSTOM_CA_CERT:-}"
		fi
	else
		say "  CA cert:    CUSTOM_CA_CERT not set (only needed on managed devices)"
	fi
	say "  prompt:     ${PRETTY_PROMPT:-ohmyposh}"
	if ! customshell_git_check; then
		check_failures=$((check_failures + 1))
	fi

	check_commands
	if [[ ${#missing_commands[@]} -eq 0 ]]; then
		say "  commands:   all expected commands found"
	else
		say "  commands:   missing: ${missing_commands[*]}"
	fi

	if [[ "$check_failures" -gt 0 ]]; then
		return 1
	fi
	return 0
}
