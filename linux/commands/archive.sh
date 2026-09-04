#!/usr/bin/env bash

# Defines the Linux commands for creating and extracting encrypted tar archives.
# Sourcing this file only declares commands; it performs no startup work.

# Protect-Tar
# Compresses a source item and encrypts it with age.
function Protect-Tar {
	(
		local -a excludes=() positional=()
		local argument pattern
		local no_ignore=false

		while [[ $# -gt 0 ]]; do
			argument="$1"
			case "$argument" in
			-h | --help)
				cat <<'EOF'
Protect-Tar
    Compresses a directory or file and encrypts it with age.

USAGE
    Protect-Tar <source> [output_base] [--exclude PATTERN]... [--no-ignore]
    Protect-Tar --help

ARGUMENTS
    source
        File or directory to archive.

    output_base
        Base path for the encrypted output. The command appends a datetime
        suffix and .enc extension. Defaults to the source path.

OPTIONS
    --exclude PATTERN
        Glob pattern to omit from the archive, passed through to tar's
        --exclude option. Repeatable.

    --no-ignore
        Disable the default recursive .tarignore handling, so all files
        including those matched by .tarignore files are archived.

    --help
        Displays this help.

NOTES
    Requires tar, realpath, Python 3, and age. The command prompts for a
    passphrase. Encryption uses age with scrypt key derivation and
    ChaCha20-Poly1305 authenticated encryption.
EOF
				return 0
				;;
			--exclude)
				if [[ $# -lt 2 || -z "$2" ]]; then
					echo "Error: --exclude requires a pattern."
					return 1
				fi
				excludes+=("$2")
				shift 2
				;;
			--exclude=*)
				pattern="${argument#--exclude=}"
				if [[ -z "$pattern" ]]; then
					echo "Error: --exclude requires a pattern."
					return 1
				fi
				excludes+=("$pattern")
				shift
				;;
			--no-ignore)
				no_ignore=true
				shift
				;;
			--)
				shift
				positional+=("$@")
				break
				;;
			-*)
				echo "Error: Unknown option: $argument"
				return 1
				;;
			*)
				positional+=("$argument")
				shift
				;;
			esac
		done

		set -- "${positional[@]}"

		if [[ $# -lt 1 || $# -gt 2 ]]; then
			echo "Usage: Protect-Tar <source> [output_base] [--exclude PATTERN]... [--no-ignore]"
			return 1
		fi

		if ! command -v age >/dev/null 2>&1; then
			echo "Error: age not found in PATH."
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
		if ! command -v python3 >/dev/null 2>&1; then
			echo "Error: python3 not found in PATH."
			return 1
		fi
		local auth_helper
		if [[ -n ${PROJ_DIR:-} ]]; then
			auth_helper="$PROJ_DIR/linux/commands/archive_auth.py"
		else
			auth_helper="$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/archive_auth.py")" || return 1
		fi

		local source_input="$1" source_parent source_name src
		if [[ ! -e "$source_input" && ! -L "$source_input" ]]; then
			echo "Error: '$source_input' does not exist."
			return 1
		fi
		source_parent="$(realpath -e -- "$(dirname -- "$source_input")")" || return 1
		source_name="$(basename -- "$source_input")"
		src="$source_parent/$source_name"
		if [[ "$src" == / ]]; then
			echo "Error: Refusing filesystem root as source."
			return 1
		fi
		if [[ ${#excludes[@]} -gt 0 && ! -d "$src" ]]; then
			echo "Error: --exclude can only be used with a directory source."
			return 1
		fi
		if [[ -t 1 ]]; then
			echo "[1/4] Validating source paths..."
		fi
		local total_files
		local -a validate_args=(validate-source "$src")
		if [[ "$no_ignore" == true ]]; then
			validate_args+=(--no-ignore)
		fi
		if ! total_files="$(python3 "$auth_helper" "${validate_args[@]}")"; then
			echo "Error: Source contains names that are not portable to Windows."
			return 1
		fi

		local output_base="${2:-$src}" timestamp out
		timestamp="$(date +%Y%m%d_%H%M%S)" || return 1
		out="${output_base}_${timestamp}.enc"

		local out_dir out_name
		out="$(realpath -m -- "$out")" || return 1
		out_dir="$(dirname -- "$out")"
		out_name="$(basename -- "$out")"
		if [[ ! -d "$out_dir" ]]; then
			echo "Error: Output parent directory does not exist: $out_dir"
			return 1
		fi
		out_dir="$(realpath -e -- "$out_dir")" || return 1
		out="$out_dir/$out_name"
		if [[ -e "$out" || -L "$out" ]]; then
			echo "Error: Output already exists: $out"
			return 1
		fi
		if [[ -d "$src" ]]; then
			local canonical_output
			canonical_output="$(realpath -m -- "$out")" || return 1
			if [[ "$canonical_output" == "$src"/* ]]; then
				echo "Error: Output cannot be created inside the source directory."
				return 1
			fi
		fi

		local tmp_tar="" tmp_out=""
		trap '[[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"; [[ -z "$tmp_out" ]] || rm -f -- "$tmp_out"' EXIT
		tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
		tmp_out="$(mktemp --tmpdir="$out_dir" ".${out_name}.XXXXXX.tmp")" || return 1
		chmod 600 -- "$tmp_tar" "$tmp_out" || return 1

		local -a exclude_args=()
		if [[ -d "$src" && "$no_ignore" != true ]]; then
			exclude_args+=("--exclude-ignore-recursive=.tarignore")
		fi
		local exclude_pattern
		for exclude_pattern in "${excludes[@]}"; do
			exclude_args+=("--exclude=$exclude_pattern")
		done

		local tar_status=0
		if [[ -t 1 && "$total_files" =~ ^[0-9]+$ && "$total_files" -gt 0 ]]; then
			local count=0 pct=0
			tar -czvf "$tmp_tar" "${exclude_args[@]}" -C "$source_parent" "./$source_name" 2>/dev/null | {
				while IFS= read -r _; do
					((count++))
					pct=$((count * 100 / total_files))
					((pct > 100)) && pct=100
					printf "\r\033[K[2/4] Packaging files: %3d%% (%d/%d)" "$pct" "$count" "$total_files"
				done
			}
			tar_status="${PIPESTATUS[0]}"
			printf "\r\033[K[2/4] Packaging completed (100%%)\n"
		else
			tar -czf "$tmp_tar" "${exclude_args[@]}" -C "$source_parent" "./$source_name"
			tar_status=$?
		fi

		if [[ $tar_status -ne 0 ]]; then
			echo "Error: Failed to create archive."
			return 1
		fi

		if [[ -t 1 ]]; then
			echo "[3/4] Encrypting archive with age..."
		fi
		if ! age -p -o "$tmp_out" "$tmp_tar"; then
			echo "Error: Encryption failed."
			return 1
		fi

		if [[ -t 1 ]]; then
			echo "[4/4] Publishing archive..."
		fi
		if ! mv -f -- "$tmp_out" "$out"; then
			echo "Error: Failed to publish encrypted archive."
			return 1
		fi
		tmp_out=""
		if ! rm -f -- "$tmp_tar"; then
			echo "Error: Archive was published, but temporary file cleanup failed." >&2
			return 1
		fi
		tmp_tar=""
		echo "Created: $out"
	)
}

# Unprotect-Tar
# Decrypts an age archive and extracts it into a destination directory.
function Unprotect-Tar {
	(
		if [[ $# -eq 1 && ("$1" == -h || "$1" == --help) ]]; then
			cat <<'EOF'
Unprotect-Tar
    Decrypts and safely extracts an archive created by Protect-Tar.

USAGE
    Unprotect-Tar <archive.enc> [destination_directory]
    Unprotect-Tar --help

ARGUMENTS
    archive
        Encrypted archive created by Protect-Tar.

    destination_directory
        Directory into which the archive is extracted. Defaults to the current
        directory. Filesystem roots, the home directory, and the CustomShell
        repository root are refused.

OPTIONS
    -h, --help
        Displays this help.

NOTES
    Requires tar, realpath, Python 3, and age. The command prompts for a passphrase.
    Archive paths are validated before transactional extraction. Symbolic and
    hard links stored in the archive are preserved.
EOF
			return 0
		fi

		if [[ $# -lt 1 || $# -gt 2 ]]; then
			echo "Usage: Unprotect-Tar <archive.enc> [destination_directory]"
			return 1
		fi

		if ! command -v age >/dev/null 2>&1; then
			echo "Error: age not found in PATH."
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
		if ! command -v python3 >/dev/null 2>&1; then
			echo "Error: python3 not found in PATH."
			return 1
		fi
		local auth_helper
		if [[ -n ${PROJ_DIR:-} ]]; then
			auth_helper="$PROJ_DIR/linux/commands/archive_auth.py"
		else
			auth_helper="$(realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/archive_auth.py")" || return 1
		fi

		local archive
		archive="$(realpath -e -- "$1")" || return 1
		if [[ ! -f "$archive" ]]; then
			echo "Error: '$1' does not exist or is not a file."
			return 1
		fi

		local requested_dest="${2:-.}"
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

		local tmp_tar="" list_file="" staging="" transaction=""
		local preserve_transaction=false
		trap '
            [[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"
            [[ -z "$list_file" ]] || rm -f -- "$list_file"
            [[ -z "$staging" ]] || rm -rf -- "$staging"
            if [[ -n "$transaction" && "$preserve_transaction" != true ]]; then rm -rf -- "$transaction"; fi
        ' EXIT
		tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
		list_file="$(mktemp)" || return 1
		chmod 600 -- "$tmp_tar" "$list_file" || return 1

		if [[ -t 1 ]]; then
			echo "[1/4] Decrypting and authenticating with age..."
		fi
		if ! age -d -o "$tmp_tar" "$archive"; then
			echo "Error: Decryption failed (incorrect password or unsupported archive)."
			return 1
		fi

		if [[ -t 1 ]]; then
			echo "[2/4] Validating archive contents..."
		fi
		local total_entries
		if ! total_entries="$(python3 "$auth_helper" validate-tar "$tmp_tar" linux)"; then
			echo "Error: Archive contents are unsafe or not portable."
			return 1
		fi

		if ! tar -tzf "$tmp_tar" >"$list_file"; then
			echo "Error: Failed to inspect archive."
			return 1
		fi

		local entry component
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
		local parent dest_name
		parent="$(dirname -- "$dest")"
		dest_name="$(basename -- "$dest")"
		if [[ ! -d "$parent" ]]; then
			echo "Error: Destination parent directory does not exist: $parent"
			return 1
		fi
		parent="$(realpath -e -- "$parent")" || return 1
		dest="$parent/$dest_name"
		staging="$(mktemp -d "$parent/.${dest_name}.stage.XXXXXX")" || return 1

		local tar_status=0
		if [[ -t 1 && "$total_entries" =~ ^[0-9]+$ && "$total_entries" -gt 0 ]]; then
			local count=0 pct=0
			tar -xzvf "$tmp_tar" -C "$staging" 2>/dev/null | {
				while IFS= read -r _; do
					((count++))
					pct=$((count * 100 / total_entries))
					((pct > 100)) && pct=100
					printf "\r\033[K[3/4] Extracting files: %3d%% (%d/%d)" "$pct" "$count" "$total_entries"
				done
			}
			tar_status="${PIPESTATUS[0]}"
			printf "\r\033[K[3/4] Extraction completed (100%%)\n"
		else
			tar -xzf "$tmp_tar" -C "$staging"
			tar_status=$?
		fi

		if [[ $tar_status -ne 0 ]]; then
			echo "Error: Failed to extract archive."
			return 1
		fi

		if [[ -t 1 ]]; then
			echo "[4/4] Merging and finalizing destination..."
		fi
		local -a staged_items=()
		shopt -s dotglob nullglob
		staged_items=("$staging"/*)
		shopt -u dotglob nullglob
		if [[ ${#staged_items[@]} -ne 1 ]]; then
			echo "Error: Archive must contain exactly one top-level item."
			return 1
		fi
		if [[ -d "$dest" ]]; then
			transaction="$(mktemp -d "$parent/.${dest_name}.transaction.XXXXXX")" || return 1
			local candidate="$transaction/candidate"
			local backup="$transaction/backup"
			mkdir -- "$candidate" "$backup" || return 1

			local -a item_names=() backed_up=() published=()
			local staged_item item_name target_path candidate_path

			local collision=false response
			for staged_item in "${staged_items[@]}"; do
				item_name="${staged_item##*/}"
				if [[ -e "$dest/$item_name" || -L "$dest/$item_name" ]]; then
					collision=true
				fi
			done
			if [[ "$collision" == true ]]; then
				if [[ ! -t 0 ]]; then
					echo "Error: Extraction target exists and confirmation requires an interactive terminal."
					return 1
				fi
				read -rp "Extraction target exists. Merge archived content? [y/N] " response || return 1
				if [[ "$response" != y && "$response" != Y && "$response" != yes && "$response" != YES ]]; then
					echo "Error: Extraction cancelled; destination was not changed."
					return 1
				fi
			fi

			for staged_item in "${staged_items[@]}"; do
				item_name="${staged_item##*/}"
				target_path="$dest/$item_name"
				candidate_path="$candidate/$item_name"

				if [[ -d "$target_path" && ! -L "$target_path" && -d "$staged_item" && ! -L "$staged_item" ]]; then
					mkdir -- "$candidate_path" || return 1
					cp -a -- "$target_path/." "$candidate_path/" || return 1
					cp -a -- "$staged_item/." "$candidate_path/" || return 1
				else
					cp -a -- "$staged_item" "$candidate/" || return 1
				fi

				item_names+=("$item_name")
				backed_up+=(false)
				published+=(false)
			done

			local publish_failed=false publish_error="" index
			for index in "${!item_names[@]}"; do
				item_name="${item_names[$index]}"
				target_path="$dest/$item_name"
				candidate_path="$candidate/$item_name"

				if [[ -e "$target_path" || -L "$target_path" ]]; then
					if ! mv -- "$target_path" "$backup/$item_name"; then
						publish_error="Failed to back up existing archive target: $target_path"
						publish_failed=true
						break
					fi
					backed_up[index]=true
				fi

				if ! mv -- "$candidate_path" "$target_path"; then
					publish_error="Failed to publish extracted archive target: $target_path"
					publish_failed=true
					break
				fi
				published[index]=true
			done

			if [[ "$publish_failed" == true ]]; then
				local rollback_failed=false
				for ((index = ${#item_names[@]} - 1; index >= 0; index--)); do
					item_name="${item_names[$index]}"
					target_path="$dest/$item_name"

					if [[ "${published[$index]}" == true ]]; then
						rm -rf -- "$target_path" || rollback_failed=true
					fi
					if [[ "${backed_up[$index]}" == true && ! -e "$target_path" && ! -L "$target_path" ]]; then
						mv -- "$backup/$item_name" "$target_path" || rollback_failed=true
					fi
				done

				if [[ "$rollback_failed" == true ]]; then
					preserve_transaction=true
					echo "Error: $publish_error; rollback was incomplete. Original data is preserved under: $backup"
				else
					echo "Error: $publish_error; the original destination content was restored."
				fi
				return 1
			fi

			if rm -rf -- "$transaction"; then
				transaction=""
			else
				preserve_transaction=true
				echo "Error: Extracted content was published, but transaction cleanup failed: $transaction" >&2
				return 1
			fi
		else
			if ! mv -- "$staging" "$dest"; then
				echo "Error: Failed to publish extracted content."
				return 1
			fi
			staging=""
		fi

		if ! rm -f -- "$tmp_tar" "$list_file" || ! rm -rf -- "$staging"; then
			echo "Error: Extracted content was published, but temporary file cleanup failed." >&2
			return 1
		fi
		tmp_tar=""
		list_file=""
		staging=""
		echo "Extracted to: $dest"
	)
}
