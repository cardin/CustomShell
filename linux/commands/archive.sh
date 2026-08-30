#!/usr/bin/env bash

# Defines the Linux commands for creating and extracting encrypted tar archives.
# Sourcing this file only declares commands; it performs no startup work.

# Protect-Tar
# Compresses a source directory and encrypts it with OpenSSL.
function Protect-Tar {
    (
        if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
            cat <<'EOF'
Protect-Tar
    Compresses a directory and encrypts it as an OpenSSL-compatible archive.

USAGE
    Protect-Tar <source_directory> [output_file.tar.gz.enc]
    Protect-Tar -h

ARGUMENTS
    source_directory
        Directory to archive.

    output_file
        Encrypted output file. By default, a timestamped .tar.gz.enc file is
        created beside the source directory. An existing file is replaced only
        after encryption succeeds.

OPTIONS
    -h, --help
        Displays this help.

NOTES
    Requires tar, realpath, and OpenSSL. The command prompts for a password.
    Encryption uses AES-256-CBC with PBKDF2 and 600,000 iterations.
EOF
            return 0
        fi

        if [[ $# -lt 1 || $# -gt 2 ]]; then
            echo "Usage: Protect-Tar <source_directory> [output_file.tar.gz.enc]"
            return 1
        fi

        if ! command -v openssl >/dev/null 2>&1; then
            echo "Error: openssl not found in PATH."
            return 1
        fi
        if ! command -v tar >/dev/null 2>&1; then
            echo "Error: tar not found in PATH."
            return 1
        fi
        if ! command -v realpath >/dev/null 2>&1; then
            echo "Error: realpath not found in PATH."
            return 1
        fi

        local src
        src="$(realpath -e -- "$1")" || return 1
        if [[ ! -d "$src" ]]; then
            echo "Error: '$1' is not a directory."
            return 1
        fi

        local out="${2:-}"
        if [[ -z "$out" ]]; then
            local timestamp
            timestamp="$(date +%Y%m%d_%H%M%S)"
            out="$(dirname -- "$src")/$(basename -- "$src")_${timestamp}.tar.gz.enc"
        fi

        local out_dir out_name
        out_dir="$(dirname -- "$out")"
        out_name="$(basename -- "$out")"
        mkdir -p -- "$out_dir" || return 1
        out_dir="$(realpath -e -- "$out_dir")" || return 1
        out="$out_dir/$out_name"
        if [[ -d "$out" ]]; then
            echo "Error: '$out' is a directory."
            return 1
        fi

        local tmp_tar="" tmp_out="" password
        trap '[[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"; [[ -z "$tmp_out" ]] || rm -f -- "$tmp_out"; unset password' EXIT
        tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
        tmp_out="$(mktemp --tmpdir="$out_dir" ".${out_name}.XXXXXX.tmp")" || return 1

        if ! read -rsp "Password: " password; then
            echo
            echo "Error: Failed to read a password."
            return 1
        fi
        echo

        if ! tar -czf "$tmp_tar" -C "$(dirname -- "$src")" "$(basename -- "$src")"; then
            echo "Error: Failed to create archive."
            return 1
        fi

        if ! openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
            -in "$tmp_tar" \
            -out "$tmp_out" \
            -pass "pass:$password"; then
            echo "Error: Encryption failed."
            return 1
        fi

        if ! mv -f -- "$tmp_out" "$out"; then
            echo "Error: Failed to publish encrypted archive."
            return 1
        fi
        tmp_out=""
        echo "Created: $out"
    )
}

# Unprotect-Tar
# Decrypts an OpenSSL archive and extracts it into a destination directory.
function Unprotect-Tar {
    (
        if [[ $# -eq 1 && ( "$1" == -h || "$1" == --help ) ]]; then
            cat <<'EOF'
Unprotect-Tar
    Decrypts and safely extracts an archive created by Protect-Tar.

USAGE
    Unprotect-Tar <archive.tar.gz.enc> <destination_directory>
    Unprotect-Tar -h

ARGUMENTS
    archive
        Encrypted archive created by Protect-Tar.

    destination_directory
        Directory into which the archive is extracted. Filesystem roots, the
        home directory, and the CustomShell repository root are refused.

OPTIONS
    -h, --help
        Displays this help.

NOTES
    Requires tar, realpath, and OpenSSL. The command prompts for a password.
    Archive paths and link entries are validated before transactional
    extraction.
EOF
            return 0
        fi

        if [[ $# -ne 2 ]]; then
            echo "Usage: Unprotect-Tar <archive.tar.gz.enc> <destination_directory>"
            return 1
        fi

        if ! command -v openssl >/dev/null 2>&1; then
            echo "Error: openssl not found in PATH."
            return 1
        fi
        if ! command -v tar >/dev/null 2>&1; then
            echo "Error: tar not found in PATH."
            return 1
        fi
        if ! command -v realpath >/dev/null 2>&1; then
            echo "Error: realpath not found in PATH."
            return 1
        fi

        local archive
        archive="$(realpath -e -- "$1")" || return 1
        if [[ ! -f "$archive" ]]; then
            echo "Error: '$1' does not exist or is not a file."
            return 1
        fi

        local requested_dest="$2"
        if [[ -z "$requested_dest" || -L "$requested_dest" ]]; then
            echo "Error: destination is empty or is a symbolic link."
            return 1
        fi

        local dest home_path repository_path
        dest="$(realpath -m -- "$requested_dest")" || return 1
        home_path="$(realpath -m -- "${HOME:?HOME is not set}")" || return 1
        if [[ -n ${PROJ_DIR:-} ]]; then
            repository_path="$(realpath -m -- "$PROJ_DIR")" || return 1
        else
            repository_path="$(realpath -m -- "$(dirname -- "${BASH_SOURCE[0]}")/../..")" || return 1
        fi
        if [[ "$dest" == / || "$dest" == "$home_path" || "$dest" == "$repository_path" ]]; then
            echo "Error: Refusing protected destination: $dest"
            return 1
        fi
        if [[ -e "$dest" && ! -d "$dest" ]]; then
            echo "Error: '$dest' is not a directory."
            return 1
        fi

        local tmp_tar="" list_file="" verbose_file="" staging="" backup=""
        local preserve_backup=false password
        trap '
            [[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"
            [[ -z "$list_file" ]] || rm -f -- "$list_file"
            [[ -z "$verbose_file" ]] || rm -f -- "$verbose_file"
            [[ -z "$staging" ]] || rm -rf -- "$staging"
            if [[ -n "$backup" && "$preserve_backup" != true ]]; then rm -rf -- "$backup"; fi
            unset password
        ' EXIT
        tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
        list_file="$(mktemp)" || return 1
        verbose_file="$(mktemp)" || return 1

        if ! read -rsp "Password: " password; then
            echo
            echo "Error: Failed to read a password."
            return 1
        fi
        echo

        if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
            -in "$archive" -out "$tmp_tar" -pass "pass:$password" 2>/dev/null; then
            echo "Error: Decryption failed (incorrect password or unsupported archive)."
            return 1
        fi

        if ! tar -tzf "$tmp_tar" >"$list_file" || ! tar -tvzf "$tmp_tar" >"$verbose_file"; then
            echo "Error: Failed to inspect archive."
            return 1
        fi

        local entry component entry_type
        while IFS= read -r entry; do
            while [[ "$entry" == ./* ]]; do entry="${entry#./}"; done
            if [[ "$entry" == /* ]]; then
                echo "Error: Archive contains an absolute path: $entry"
                return 1
            fi
            IFS='/' read -r -a components <<<"$entry"
            for component in "${components[@]}"; do
                if [[ "$component" == .. ]]; then
                    echo "Error: Archive contains path traversal: $entry"
                    return 1
                fi
            done
        done <"$list_file"
        while IFS= read -r entry; do
            entry_type="${entry:0:1}"
            if [[ "$entry_type" == l || "$entry_type" == h ]]; then
                echo "Error: Archive contains a symbolic-link or hard-link entry."
                return 1
            fi
        done <"$verbose_file"

        local parent dest_name
        parent="$(dirname -- "$dest")"
        dest_name="$(basename -- "$dest")"
        mkdir -p -- "$parent" || return 1
        parent="$(realpath -e -- "$parent")" || return 1
        dest="$parent/$dest_name"
        staging="$(mktemp -d "$parent/.${dest_name}.stage.XXXXXX")" || return 1

        if [[ -d "$dest" ]]; then
            if [[ -n "$(find "$dest" -type l -print -quit)" || -n "$(find "$dest" -type f -links +1 -print -quit)" ]]; then
                echo "Error: Existing destination contains symbolic or hard links."
                return 1
            fi
            cp -a -- "$dest/." "$staging/" || return 1
        fi

        if ! tar -xzf "$tmp_tar" -C "$staging"; then
            echo "Error: Failed to extract archive."
            return 1
        fi
        if [[ -n "$(find "$staging" -type l -print -quit)" || -n "$(find "$staging" -type f -links +1 -print -quit)" ]]; then
            echo "Error: Extracted content contains symbolic or hard links."
            return 1
        fi

        if [[ -d "$dest" ]]; then
            backup="$(mktemp -d "$parent/.${dest_name}.backup.XXXXXX")" || return 1
            rmdir -- "$backup" || return 1
            if ! mv -- "$dest" "$backup"; then
                echo "Error: Failed to stage the existing destination for replacement."
                return 1
            fi
            preserve_backup=true
            if ! mv -- "$staging" "$dest"; then
                if mv -- "$backup" "$dest"; then
                    backup=""
                    preserve_backup=false
                    echo "Error: Failed to publish extracted content; the original was restored."
                else
                    echo "Error: Publication and rollback failed; original data is preserved at: $backup"
                fi
                return 1
            fi
            staging=""
            preserve_backup=false
            rm -rf -- "$backup"
            backup=""
        else
            if ! mv -- "$staging" "$dest"; then
                echo "Error: Failed to publish extracted content."
                return 1
            fi
            staging=""
        fi

        echo "Extracted to: $dest"
    )
}
