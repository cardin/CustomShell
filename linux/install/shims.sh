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
# exposes the name before "=" using the command after "=". The system directory
# receives generated shims for processes that start outside a login shell, and
# is overridable so tests never write to the real one.
customshell_shims_initialize() {
	customshell_shim_dir="${XDG_BIN_HOME:-${HOME:?HOME is not set}/.local/bin}"
	customshell_system_bin_dir="${CUSTOMSHELL_SYSTEM_BIN_DIR:-/usr/local/bin}"
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

# cmd.exe shim
# Windows interoperability commands are unavailable by name to processes that
# start without the Windows directories on PATH: OpenCode Desktop launches its
# WSL server with `bash -se` and removes every /mnt entry. The installer writes
# the resolved cmd.exe into a system bin directory so those processes, and
# Plannotator's WSL browser opener in particular, find it without a login shell.

customshell_wsl_cmd_shim_marker='# Managed by CustomShell (linux/install.sh); removed by --uninstall.'

# customshell_wsl_cmd_shim_content
# Prints the managed shim, or nothing when Windows cmd.exe is unavailable or
# unsafe to embed.
customshell_wsl_cmd_shim_content() {
	local cmd_exe
	cmd_exe="$(customshell_find_cmd_exe || true)"
	customshell_cmd_exe_usable "$cmd_exe" || return 0
	printf '%s\n' \
		'#!/bin/sh' \
		"$customshell_wsl_cmd_shim_marker" \
		"exec \"$cmd_exe\" \"\$@\""
}

# customshell_wsl_cmd_shim_managed
# Returns success when a file carries the CustomShell marker near the top, so
# uninstall and check never claim a foreign or user-edited file.
customshell_wsl_cmd_shim_managed() {
	[[ -f "$1" ]] || return 1
	head -n 5 -- "$1" 2>/dev/null | grep -Fqx -- "$customshell_wsl_cmd_shim_marker"
}

# customshell_system_write
# Replaces a root-owned path, elevating only when the caller cannot write it.
customshell_system_write() {
	local target=$1 content=$2 directory temp
	directory="$(dirname -- "$target")"
	if [[ ! -d "$directory" ]]; then
		mkdir -p -- "$directory" 2>/dev/null || true
	fi
	if [[ -d "$directory" && (-w "$directory" || $EUID -eq 0) ]]; then
		printf '%s\n' "$content" >"$target" || return 1
		chmod 755 -- "$target" || return 1
		return 0
	fi
	if ! command -v sudo >/dev/null 2>&1; then
		say "Error: sudo is required to write $target." >&2
		return 1
	fi
	temp="$(mktemp)" || return 1
	if ! printf '%s\n' "$content" >"$temp"; then
		rm -f -- "$temp"
		return 1
	fi
	if sudo install -D -m 755 -- "$temp" "$target"; then
		rm -f -- "$temp"
		return 0
	fi
	rm -f -- "$temp"
	say "Error: failed to install $target" >&2
	return 1
}

# customshell_system_remove
# Removes a root-owned path, elevating only when the caller cannot write it.
customshell_system_remove() {
	local target=$1 directory
	directory="$(dirname -- "$target")"
	if [[ -w "$directory" || $EUID -eq 0 ]]; then
		rm -f -- "$target"
		return
	fi
	if ! command -v sudo >/dev/null 2>&1; then
		say "Error: sudo is required to remove $target." >&2
		return 1
	fi
	sudo rm -f -- "$target"
}

# customshell_wsl_cmd_shim_install
# Installs or refreshes the shim on WSL. Advisory when Windows cmd.exe is
# missing; returns non-zero only when the write itself fails.
customshell_wsl_cmd_shim_install() {
	local target content
	customshell_is_wsl || return 0
	target="$customshell_system_bin_dir/cmd.exe"
	content="$(customshell_wsl_cmd_shim_content)"
	if [[ -z "$content" ]]; then
		say "cmd.exe shim: skipped (Windows cmd.exe not found)"
		return 0
	fi
	if customshell_wsl_cmd_shim_managed "$target" &&
		[[ "$(<"$target")" == "$content" ]]; then
		say "cmd.exe shim: already configured ($target)"
		return 0
	fi
	if [[ "$dry_run" == true ]]; then
		say "Would install the cmd.exe shim: $target"
		return 0
	fi
	if ! customshell_system_write "$target" "$content"; then
		return 1
	fi
	say "Installed the cmd.exe shim: $target"
}

# customshell_wsl_cmd_shim_uninstall
# Removes only a shim that still carries the managed marker.
customshell_wsl_cmd_shim_uninstall() {
	local target
	customshell_is_wsl || return 0
	target="$customshell_system_bin_dir/cmd.exe"
	[[ -e "$target" || -L "$target" ]] || return 0
	if ! customshell_wsl_cmd_shim_managed "$target"; then
		say "cmd.exe shim: leaving unmanaged file ($target)"
		return 0
	fi
	if [[ "$dry_run" == true ]]; then
		say "Would remove the cmd.exe shim: $target"
		return 0
	fi
	if ! customshell_system_remove "$target"; then
		return 1
	fi
	say "Removed the cmd.exe shim: $target"
}

# customshell_wsl_cmd_shim_check
# Reports the shim state for the check summary. Returns non-zero when it is
# missing, stale, or occupied by an unmanaged file.
customshell_wsl_cmd_shim_check() {
	local target content
	if ! customshell_is_wsl; then
		say "  cmd.exe:    not applicable (not WSL)"
		return 0
	fi
	target="$customshell_system_bin_dir/cmd.exe"
	if [[ ! -e "$target" && ! -L "$target" ]]; then
		say "  cmd.exe:    missing ($target) - run install.sh"
		return 1
	fi
	if ! customshell_wsl_cmd_shim_managed "$target"; then
		say "  cmd.exe:    unmanaged file ($target)"
		return 1
	fi
	content="$(customshell_wsl_cmd_shim_content)"
	if [[ -n "$content" ]] && [[ "$(<"$target")" != "$content" ]]; then
		say "  cmd.exe:    stale ($target) - run install.sh"
		return 1
	fi
	say "  cmd.exe:    configured ($target)"
	return 0
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
	local applicable=false missing=false status=0
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
	elif [[ "$missing" == true ]]; then
		say "  shims:      missing ($customshell_shim_dir) - run install.sh"
		status=1
	else
		say "  shims:      configured ($customshell_shim_dir)"
	fi
	customshell_wsl_cmd_shim_check || status=1
	return "$status"
}
