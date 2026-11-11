#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2178

# Installer-owned Git credential helper configuration. The previous helper list
# is stored as NUL-delimited state so uninstall can restore it without evaluating
# user-controlled values.
customshell_git_helper='cache --timeout=21600'
customshell_git_state_dir="${XDG_STATE_HOME:-${HOME:?HOME is not set}/.local/state}/customshell"
customshell_git_state_file="$customshell_git_state_dir/git-credential-helper"

customshell_git_get_helpers() {
	local result_name=$1 value
	local -n result=$result_name
	result=()
	while IFS= read -r -d '' value; do
		result+=("$value")
	done < <(git config --global --null --get-all credential.helper 2>/dev/null)
}

customshell_git_is_current() {
	local -a helpers=()
	customshell_git_get_helpers helpers
	[[ ${#helpers[@]} -eq 1 && "${helpers[0]}" == "$customshell_git_helper" ]]
}

customshell_git_save_state() {
	local -a helpers=("$@")
	local tmp
	mkdir -p -- "$customshell_git_state_dir" || return 1
	tmp="$(mktemp "$customshell_git_state_dir/.git-credential-helper.XXXXXX")" || return 1
	if ! chmod 600 "$tmp" ||
		! {
			printf 'customshell-git-v1\0'
			((${#helpers[@]} == 0)) || printf '%s\0' "${helpers[@]}"
		} >"$tmp" ||
		! mv -f -- "$tmp" "$customshell_git_state_file"; then
		rm -f -- "$tmp"
		return 1
	fi
}

customshell_git_read_state() {
	local result_name=$1 header value
	local -n result=$result_name
	result=()
	[[ -f "$customshell_git_state_file" ]] || return 1
	exec 3<"$customshell_git_state_file"
	if ! IFS= read -r -d '' header <&3 || [[ "$header" != customshell-git-v1 ]]; then
		exec 3<&-
		return 1
	fi
	while IFS= read -r -d '' value <&3; do
		result+=("$value")
	done
	exec 3<&-
}

customshell_git_install() {
	command -v git >/dev/null 2>&1 || return 0
	if customshell_git_is_current && [[ -f "$customshell_git_state_file" ]]; then
		return 0
	fi
	if [[ "$dry_run" == true ]]; then
		say "Would configure Git credential helper: $customshell_git_helper"
		return 0
	fi

	local state_created=false
	if [[ ! -f "$customshell_git_state_file" ]]; then
		local -a previous=()
		if ! customshell_git_is_current; then
			customshell_git_get_helpers previous
		fi
		if ! customshell_git_save_state "${previous[@]}"; then
			say "Error: failed to record the existing Git credential helper." >&2
			return 1
		fi
		state_created=true
	fi

	if git config --global --replace-all credential.helper "$customshell_git_helper"; then
		say "Configured Git credential helper: $customshell_git_helper"
		return 0
	fi
	if [[ "$state_created" == true ]]; then
		rm -f -- "$customshell_git_state_file"
		rmdir --ignore-fail-on-non-empty "$customshell_git_state_dir" 2>/dev/null || true
	fi
	say "Error: failed to configure the Git credential helper." >&2
	return 1
}

customshell_git_uninstall() {
	[[ -f "$customshell_git_state_file" ]] || return 0
	command -v git >/dev/null 2>&1 || {
		say "Skipped Git credential helper restore: git is unavailable." >&2
		return 0
	}
	if ! customshell_git_is_current; then
		say "Kept locally modified Git credential helper configuration."
		return 0
	fi

	local -a previous=()
	if ! customshell_git_read_state previous; then
		say "Error: Git credential helper state is unreadable." >&2
		return 1
	fi
	if [[ "$dry_run" == true ]]; then
		say "Would restore the previous Git credential helper configuration"
		return 0
	fi

	if ! git config --global --unset-all credential.helper; then
		say "Error: failed to remove the managed Git credential helper." >&2
		return 1
	fi
	local helper
	for helper in "${previous[@]}"; do
		if ! git config --global --add credential.helper "$helper"; then
			git config --global --unset-all credential.helper >/dev/null 2>&1 || true
			git config --global --add credential.helper "$customshell_git_helper" >/dev/null 2>&1 || true
			say "Error: failed to restore the previous Git credential helper." >&2
			return 1
		fi
	done
	rm -f -- "$customshell_git_state_file"
	rmdir --ignore-fail-on-non-empty "$customshell_git_state_dir" 2>/dev/null || true
	say "Restored the previous Git credential helper configuration"
}

customshell_git_check() {
	if ! command -v git >/dev/null 2>&1; then
		say "  Git helper: unavailable (optional)"
		return 0
	fi
	if customshell_git_is_current && [[ -f "$customshell_git_state_file" ]]; then
		say "  Git helper: configured"
		return 0
	fi
	say "  Git helper: stale - run install.sh"
	return 1
}
