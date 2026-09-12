#!/usr/bin/env bash
# shellcheck disable=SC2154

# Read-only setup checks. This file only defines functions and is sourced by
# linux/install.sh.

check_failures=0
missing_commands=()

# check_commands
# Records expected commands that are unavailable locally.
check_commands() {
	local programs=("age" "bat" "btop" "conda" "delta" "dos2unix" "fd" "fzf"
		"node" "pipx" "progress" "realpath" "rg" "shfmt" "tmux" "tree"
		"unzip" "zip" "zoxide")
	if ! uname -r | grep -qi microsoft; then
		programs+=("lazygit" "lazydocker" "nvitop")
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

	if profile_has_block; then
		if render_profile write | cmp -s - "$bashrc"; then
			say "  profile:    current ($bashrc)"
		else
			say "  profile:    stale ($bashrc) - run install.sh"
			check_failures=$((check_failures + 1))
		fi
	elif profile_has_unmarked_source; then
		say "  profile:    manually sourced and unmanaged ($bashrc)"
	else
		say "  profile:    not configured ($bashrc) - run install.sh"
		check_failures=$((check_failures + 1))
	fi

	local source destination target
	local links_ok=true
	for source in "${espanso_sources[@]}"; do
		destination="$(espanso_destination_dir "$source")/$(basename -- "$source")"
		target="$(resolve_link_target "$destination")"
		if [[ "$target" != "$source" ]]; then
			links_ok=false
		fi
	done
	if [[ "$links_ok" == true ]]; then
		say "  espanso:    linked ($espanso_root)"
	else
		say "  espanso:    not linked ($espanso_root) - run install.sh"
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
