#!/usr/bin/env bash
# shellcheck disable=SC2154

# Managed shell profile block. The block is delimited by markers and contains
# the persistent environment exports plus the entry-point source line, supplied
# by the caller as the desired_block_lines array. This file only defines
# functions and is sourced by linux/install.sh.

# write_block_lines
# Prints the marker-delimited managed block.
write_block_lines() {
    printf '%s\n' "$marker_begin"
    printf '%s\n' "${desired_block_lines[@]}"
    printf '%s\n' "$marker_end"
}

# render_profile
# Writes the desired profile content to stdout. An existing managed block is
# replaced on "write" and removed on "remove"; otherwise the file is passed
# through unchanged. On "write", the block is appended when absent.
render_profile() {
    local action=$1
    local -a lines=()
    if [[ -f "$bashrc" ]]; then
        mapfile -t lines <"$bashrc"
    fi

    local start=-1 end=-1 i
    for ((i = 0; i < ${#lines[@]}; i++)); do
        if ((start < 0)) && [[ "${lines[i]}" == "$marker_begin" ]]; then
            start=$i
            continue
        fi
        if ((start >= 0)) && [[ "${lines[i]}" == "$marker_end" ]]; then
            end=$i
            break
        fi
    done

    if ((start >= 0 && end >= 0)); then
        local head_end=$((start - 1))
        if [[ "$action" == "remove" ]] && ((head_end >= 0)) && [[ -z "${lines[head_end]}" ]]; then
            head_end=$((head_end - 1))
        fi
        for ((i = 0; i <= head_end; i++)); do
            printf '%s\n' "${lines[i]}"
        done
        if [[ "$action" == "write" ]]; then
            write_block_lines
        fi
        for ((i = end + 1; i < ${#lines[@]}; i++)); do
            printf '%s\n' "${lines[i]}"
        done
    elif [[ "$action" == "write" ]]; then
        if ((${#lines[@]} > 0)); then
            printf '%s\n' "${lines[@]}"
            printf '\n'
        fi
        write_block_lines
    elif ((${#lines[@]} > 0)); then
        printf '%s\n' "${lines[@]}"
    fi
}

# profile_has_block
# Succeeds when the rc file contains a complete managed block.
profile_has_block() {
    [[ -f "$bashrc" ]] || return 1
    local -a lines=()
    mapfile -t lines <"$bashrc"
    local seen_begin=false line
    for line in "${lines[@]}"; do
        if [[ "$line" == "$marker_begin" ]]; then
            seen_begin=true
            continue
        fi
        if [[ "$seen_begin" == true && "$line" == "$marker_end" ]]; then
            return 0
        fi
    done
    return 1
}

# profile_has_unmarked_source
# Succeeds when the entry point is sourced without a managed block.
profile_has_unmarked_source() {
    [[ -f "$bashrc" ]] || return 1
    grep -Fq "$entry_script" "$bashrc" && ! profile_has_block
}

# write_profile_block
# Adds or refreshes the managed block atomically.
write_profile_block() {
    if profile_has_unmarked_source; then
        say "Skipped profile update: $bashrc already sources CustomShell without a managed block." >&2
        return 0
    fi

    local profile_dir tmp
    profile_dir="$(dirname -- "$bashrc")"
    if ! mkdir -p -- "$profile_dir"; then
        say "Error: failed to create $profile_dir" >&2
        return 1
    fi

    tmp="$(mktemp "$profile_dir/.customshell.rc.XXXXXX")" || return 1
    if [[ -f "$bashrc" ]]; then
        chmod --reference="$bashrc" "$tmp" 2>/dev/null || true
    fi

    if ! render_profile write >"$tmp"; then
        rm -f -- "$tmp"
        say "Error: failed to render the profile block." >&2
        return 1
    fi

    if [[ -f "$bashrc" ]] && cmp -s -- "$tmp" "$bashrc"; then
        rm -f -- "$tmp"
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        rm -f -- "$tmp"
        say "Would update profile block in $bashrc"
        return 0
    fi

    if mv -f -- "$tmp" "$bashrc"; then
        say "Updated profile block in $bashrc"
        return 0
    fi

    rm -f -- "$tmp"
    say "Error: failed to write $bashrc" >&2
    return 1
}

# remove_profile_block
# Removes the managed block when present.
remove_profile_block() {
    if ! profile_has_block; then
        return 0
    fi
    if [[ "$dry_run" == true ]]; then
        say "Would remove profile block from $bashrc"
        return 0
    fi

    local tmp
    tmp="$(mktemp "$(dirname -- "$bashrc")/.customshell.rc.XXXXXX")" || return 1
    chmod --reference="$bashrc" "$tmp" 2>/dev/null || true
    if render_profile remove >"$tmp" && mv -f -- "$tmp" "$bashrc"; then
        say "Removed profile block from $bashrc"
        return 0
    fi
    rm -f -- "$tmp"
    say "Error: failed to update $bashrc" >&2
    return 1
}
