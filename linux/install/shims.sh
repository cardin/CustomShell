#!/usr/bin/env bash
# shellcheck disable=SC2154

# PATH shims for tools whose binary name differs from the command users expect.
# Some distributions ship `fd` as `fdfind`, which interactive shells only reach
# through an alias. The installer links the expected name into a user bin
# directory instead, so scripts, non-interactive shells, and tools that spawn
# commands all see it. This file only defines functions and is sourced by
# linux/install.sh.

# customshell_shims_initialize
# Resolves the shim directory and the name/command pairs to expose. Each entry
# exposes the name before "=" using the command after "=".
customshell_shims_initialize() {
	customshell_shim_dir="${XDG_BIN_HOME:-${HOME:?HOME is not set}/.local/bin}"
	customshell_shims=("fd=fdfind")
}

# customshell_shim_command
# Prints the canonical path of a command, or an empty string when it is absent.
customshell_shim_command() {
	local command_path
	command_path="$(command -v "$1" 2>/dev/null || true)"
	[[ -n "$command_path" ]] || return 0
	resolve_link_target "$command_path"
}

# customshell_shims_link
# Links each expected tool name that is not already provided.
customshell_shims_link() {
	local pair name command_name command_path destination target
	for pair in "${customshell_shims[@]}"; do
		name=${pair%%=*}
		command_name=${pair#*=}
		command_path="$(customshell_shim_command "$command_name")"
		[[ -n "$command_path" ]] || continue
		destination="$customshell_shim_dir/$name"

		if [[ -L "$destination" ]]; then
			target="$(resolve_link_target "$destination")"
			[[ "$target" == "$command_path" ]] && continue
		elif [[ -e "$destination" ]]; then
			# A non-link entry already occupies the name; leave it alone.
			continue
		fi

		if [[ "$dry_run" == true ]]; then
			say "Would link $destination -> $command_path"
			continue
		fi
		if ! mkdir -p -- "$customshell_shim_dir"; then
			say "Error: failed to create $customshell_shim_dir" >&2
			return 1
		fi
		if ln -sfn -- "$command_path" "$destination"; then
			say "Linked $destination -> $command_path"
		else
			say "Error: failed to link $destination" >&2
			return 1
		fi
	done
}

# customshell_shims_unlink
# Removes links that still point at the command they were created for.
customshell_shims_unlink() {
	local pair name command_name command_path destination target
	for pair in "${customshell_shims[@]}"; do
		name=${pair%%=*}
		command_name=${pair#*=}
		destination="$customshell_shim_dir/$name"
		[[ -L "$destination" ]] || continue
		command_path="$(customshell_shim_command "$command_name")"
		target="$(resolve_link_target "$destination")"
		if [[ -n "$command_path" && "$target" == "$command_path" ]]; then
			if [[ "$dry_run" == true ]]; then
				say "Would remove link $destination"
			elif rm -f -- "$destination"; then
				say "Removed link $destination"
			fi
		fi
	done
}

# customshell_shims_check
# Prints shim state for the check report. Returns non-zero when a shim that
# should exist is missing or stale, so the caller can count it as a failure.
customshell_shims_check() {
	local pair name command_name command_path destination target
	local applicable=false missing=false
	for pair in "${customshell_shims[@]}"; do
		name=${pair%%=*}
		command_name=${pair#*=}
		command_path="$(customshell_shim_command "$command_name")"
		[[ -n "$command_path" ]] || continue
		applicable=true
		destination="$customshell_shim_dir/$name"
		target="$(resolve_link_target "$destination")"
		if [[ "$target" != "$command_path" ]]; then
			missing=true
		fi
	done

	if [[ "$applicable" == false ]]; then
		say "  shims:      none needed"
		return 0
	fi
	if [[ "$missing" == true ]]; then
		say "  shims:      missing ($customshell_shim_dir) - run install.sh"
		return 1
	fi
	say "  shims:      configured ($customshell_shim_dir)"
	return 0
}
