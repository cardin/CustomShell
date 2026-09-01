#!/usr/bin/env bash

# Defines WSL-only interoperability and maintenance commands. This file is
# sourced only after WSL detection and color initialization.

if [[ -z ${USERPROFILE+x} ]]; then
    echo -e "${Blue}Need to share WSL variable \$USERPROFILE!"
    echo -e "${Blue}Ignore this error if you're using \"su -\". Next time, use \"su root\"."
fi

# Use VS Code (Windows) as the default editor inside WSL so it opens in the
# Windows-side GUI. Only set here because this file is sourced only on WSL.
if command -v code >/dev/null 2>&1; then
    export EDITOR="${EDITOR:-code --wait}"
fi

# wcd
# Changes directory using a Windows-style path converted by wslpath.
wcd() {
    if [[ -z ${1:-} ]]; then
        echo "Usage: wcd WINDOWS_PATH" >&2
        return 2
    fi
    cd "$(wslpath "$1")" || return
}

# wpushd
# Pushes a Windows-style path, converted by wslpath, onto the directory stack.
wpushd() {
    if [[ -z ${1:-} ]]; then
        echo "Usage: wpushd WINDOWS_PATH" >&2
        return 2
    fi
    pushd "$(wslpath "$1")" || return
}

# cmd
# Executes the supplied command through Windows Command Prompt.
cmd() { cmd.exe /C "$@"; }

# release-ram
# Requests that Linux drop filesystem caches through the kernel interface.
release-ram() { echo 1 | sudo tee /proc/sys/vm/drop_caches; }

# mirror-win-ssh
# Mirrors the Windows SSH directory into WSL and applies OpenSSH permissions.
mirror-win-ssh() (
    if ! command -v rsync >/dev/null 2>&1; then
        echo "Error: rsync is not installed." >&2
        echo "Install it with: sudo apt install rsync" >&2
        return 1
    fi
    if ! command -v cmd.exe >/dev/null 2>&1; then
        echo "Error: cmd.exe not found. Are you running inside WSL?" >&2
        return 1
    fi
    if ! command -v realpath >/dev/null 2>&1; then
        echo "Error: realpath is not installed." >&2
        return 1
    fi
    if [[ -z ${USERPROFILE:-} ]]; then
        echo "Error: USERPROFILE is not set; refusing to infer a Windows SSH source." >&2
        return 1
    fi

    local home_path src dest
    home_path="$(realpath -m -- "${HOME:?HOME is not set}")" || return 1
    src="$(realpath -m -- "$USERPROFILE/.ssh")" || return 1
    dest="$(realpath -m -- "$home_path/.ssh")" || return 1
    if [[ "$home_path" == / || "$dest" == / || "$src" == / || "$src" == "$dest" ]]; then
        echo "Error: Refusing unsafe SSH mirror paths." >&2
        return 1
    fi
    if [[ ! -d "$src" ]]; then
        echo "Windows .ssh directory not found: $src" >&2
        return 1
    fi
    if [[ -L "$USERPROFILE/.ssh" || -L "$home_path/.ssh" ]]; then
        echo "Error: SSH mirror source and destination must not be symbolic links." >&2
        return 1
    fi
    if [[ -n "$(find "$src" -type l -print -quit)" || -n "$(find "$src" -type f -links +1 -print -quit)" ]]; then
        echo "Error: Windows SSH source contains symbolic or hard links." >&2
        return 1
    fi

    local staging="" backup="" preserve_backup=false
    trap '
        [[ -z "$staging" ]] || rm -rf -- "$staging"
        if [[ -n "$backup" && "$preserve_backup" != true ]]; then rm -rf -- "$backup"; fi
    ' EXIT

    staging="$(mktemp -d "$home_path/.ssh.customshell.stage.XXXXXX")" || return 1
    if ! rsync -a "$src/" "$staging/"; then
        echo "Error: Failed to stage the Windows SSH directory." >&2
        return 1
    fi

    chmod 700 "$staging" || return 1
    find "$staging" -type d -exec chmod 700 {} \; || return 1
    find "$staging" -type f -exec chmod 600 {} \; || return 1
    find "$staging" -type f -name '*.pub' -exec chmod 644 {} \; || return 1
    [[ ! -f "$staging/known_hosts" ]] || chmod 644 "$staging/known_hosts" || return 1
    [[ ! -f "$staging/authorized_keys" ]] || chmod 600 "$staging/authorized_keys" || return 1
    [[ ! -f "$staging/config" ]] || chmod 600 "$staging/config" || return 1

    if [[ -e "$dest" ]]; then
        if [[ ! -d "$dest" ]]; then
            echo "Error: SSH mirror destination is not a directory: $dest" >&2
            return 1
        fi
        backup="$(mktemp -d "$home_path/.ssh.customshell.backup.XXXXXX")" || return 1
        rmdir -- "$backup" || return 1
        if ! mv -- "$dest" "$backup"; then
            echo "Error: Failed to stage the existing SSH directory." >&2
            return 1
        fi
        preserve_backup=true
        if ! mv -- "$staging" "$dest"; then
            if mv -- "$backup" "$dest"; then
                backup=""
                preserve_backup=false
                echo "Error: Failed to publish SSH mirror; the original was restored." >&2
            else
                echo "Error: Publication and rollback failed; original SSH data is at: $backup" >&2
            fi
            return 1
        fi
        staging=""
        preserve_backup=false
        rm -rf -- "$backup"
        backup=""
    else
        mv -- "$staging" "$dest" || return 1
        staging=""
    fi

    echo "Mirrored $src -> $dest"
    ls -ld "$dest"
    ls -l "$dest"
)
