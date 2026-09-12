#!/usr/bin/env bash
# shellcheck disable=SC2154

# Espanso configuration links. The installer links the shipped files into the
# directories Espanso expects under the root it reports. This file only defines
# functions and is sourced by linux/install.sh.

# resolve_espanso_root
# Asks Espanso for its config directory, falling back to the platform default.
resolve_espanso_root() {
    local name output line
    for name in espanso espansod; do
        command -v "$name" >/dev/null 2>&1 || continue
        output="$("$name" path config 2>/dev/null)" || continue
        line="$(printf '%s\n' "$output" | awk 'NF { print; exit }')"
        if [[ -n "$line" && -d "$line" ]]; then
            printf '%s' "$line"
            return 0
        fi
    done
    return 1
}

# espanso_initialize
# Resolves the root and defines the source files and their destinations.
espanso_initialize() {
    if [[ -z "$espanso_root" ]]; then
        if ! espanso_root="$(resolve_espanso_root)"; then
            espanso_root="${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}/espanso"
        fi
    fi

    espanso_match_dir="$espanso_root/match"
    espanso_config_dir="$espanso_root/config"

    espanso_sources=(
        "$config_dir/espanso/_base.yml"
        "$config_dir/espanso/whitelist.yml"
    )
}

# espanso_destination_dir
# Maps a configuration source to the Espanso directory that expects it.
espanso_destination_dir() {
    case "$(basename -- "$1")" in
    _base.yml)
        printf '%s' "$espanso_match_dir"
        ;;
    whitelist.yml)
        printf '%s' "$espanso_config_dir"
        ;;
    *)
        return 1
        ;;
    esac
}

# link_config_file
# Links one source file into its destination directory.
link_config_file() {
    local source=$1
    local destination_dir=$2
    local destination
    local target
    destination="$destination_dir/$(basename -- "$source")"

    if [[ ! -e "$source" ]]; then
        say "Error: missing configuration source: $source" >&2
        return 1
    fi

    target="$(resolve_link_target "$destination")"
    if [[ -n "$target" && "$target" == "$source" ]]; then
        return 0
    fi

    if [[ "$dry_run" == true ]]; then
        say "Would link $destination -> $source"
        return 0
    fi

    if ! mkdir -p -- "$destination_dir"; then
        say "Error: failed to create $destination_dir" >&2
        return 1
    fi

    if [[ -e "$destination" && ! -L "$destination" ]]; then
        if [[ "$force" != true ]]; then
            say "Skipped $destination: a file already exists (use --force to replace)." >&2
            return 0
        fi
        if [[ -e "$destination.customshell.bak" ]]; then
            say "Error: backup already exists: $destination.customshell.bak" >&2
            return 1
        fi
        mv -- "$destination" "$destination.customshell.bak" || return 1
        say "Backed up existing file to $destination.customshell.bak"
    fi

    if ln -sfn -- "$source" "$destination"; then
        say "Linked $destination -> $source"
        return 0
    fi

    say "Error: failed to link $destination" >&2
    return 1
}

# link_espanso
# Links every shipped Espanso configuration file.
link_espanso() {
    local source
    for source in "${espanso_sources[@]}"; do
        link_config_file "$source" "$(espanso_destination_dir "$source")" || return 1
    done
}

# unlink_espanso
# Removes links that still point into the repository.
unlink_espanso() {
    local source destination target
    for source in "${espanso_sources[@]}"; do
        destination="$(espanso_destination_dir "$source")/$(basename -- "$source")"
        [[ -L "$destination" ]] || continue
        target="$(resolve_link_target "$destination")"
        if [[ "$target" == "$source" ]]; then
            if [[ "$dry_run" == true ]]; then
                say "Would remove link $destination"
            elif rm -f -- "$destination"; then
                say "Removed link $destination"
            fi
        fi
    done
}
