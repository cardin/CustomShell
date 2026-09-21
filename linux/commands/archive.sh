#!/usr/bin/env bash

# Defines the Linux commands for creating and extracting encrypted tar archives.
# Sourcing this file only declares commands; it performs no startup work.

# customshell_archive_require_tools
# Fails unless every external command the archive commands depend on is in PATH.
customshell_archive_require_tools() {
	local tool
	for tool in age tar realpath python3; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			echo "Error: $tool not found in PATH."
			return 1
		fi
	done
}

# customshell_archive_auth_helper
# Prints the path to the shared Python archive core used for validation and
# entry-list generation. PROJ_DIR is set by the entry point; the fallback keeps
# the command usable when the file is sourced directly.
customshell_archive_auth_helper() {
	if [[ -n ${PROJ_DIR:-} ]]; then
		printf '%s' "$PROJ_DIR/tools/archive_core.py"
	else
		realpath -e -- "$(dirname -- "${BASH_SOURCE[0]}")/../../tools/archive_core.py"
	fi
}

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
        Glob pattern to omit from the archive. A pattern without "/" matches
        basenames at any depth; a pattern containing "/" is anchored to the
        source root. Repeatable.

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

		if ! customshell_archive_require_tools; then
			return 1
		fi
		local auth_helper
		if ! auth_helper="$(customshell_archive_auth_helper)"; then
			return 1
		fi

		local source_input="$1" source_parent source_name src
		if [[ ! -e "$source_input" && ! -L "$source_input" ]]; then
			echo "Error: '$source_input' does not exist."
			return 1
		fi
		source_parent="$(realpath -e -- "$(dirname -- "$source_input")")" || return 1
		source_name="$(basename -- "$source_input")"
		src="$source_parent/$source_name"
		if [[ ${#excludes[@]} -gt 0 && ! -d "$src" ]]; then
			echo "Error: --exclude can only be used with a directory source."
			return 1
		fi
		# Temp files are declared before the first failure point so the EXIT
		# trap always has them in scope.
		local tmp_tar="" tmp_out="" list_file=""
		trap '[[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"; [[ -z "$tmp_out" ]] || rm -f -- "$tmp_out"; [[ -z "$list_file" ]] || rm -f -- "$list_file"' EXIT

		if [[ -t 1 ]]; then
			echo "[1/4] Validating source paths..."
		fi
		list_file="$(mktemp)" || return 1
		chmod 600 -- "$list_file" || return 1
		local -a list_args=(list-source "$src" --output "$list_file")
		if [[ "$no_ignore" == true ]]; then
			list_args+=(--no-ignore)
		fi
		local exclude_pattern
		for exclude_pattern in "${excludes[@]}"; do
			list_args+=(--exclude "$exclude_pattern")
		done
		local total_files
		if ! total_files="$(python3 "$auth_helper" "${list_args[@]}")"; then
			echo "Error: Source contains names that are not portable to Windows."
			return 1
		fi
		total_files="${total_files//[[:space:]]/}"

		local output_base="${2:-}" out
		local -a resolve_args=(resolve-output "$src")
		if [[ -n "$output_base" ]]; then
			resolve_args+=("$output_base")
		fi
		if ! out="$(python3 "$auth_helper" "${resolve_args[@]}" 2>&1)"; then
			printf 'Error: %s\n' "$out" >&2
			return 1
		fi
		local out_dir out_name
		out_dir="$(dirname -- "$out")"
		out_name="$(basename -- "$out")"

		tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
		tmp_out="$(mktemp --tmpdir="$out_dir" ".${out_name}.XXXXXX.tmp")" || return 1
		chmod 600 -- "$tmp_tar" "$tmp_out" || return 1

		local tar_status=0
		if [[ -t 1 && "$total_files" =~ ^[0-9]+$ && "$total_files" -gt 0 ]]; then
			local count=0 pct=0
			tar -czvf "$tmp_tar" -C "$source_parent" --null --no-recursion --files-from="$list_file" 2>/dev/null | {
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
			tar -czf "$tmp_tar" -C "$source_parent" --null --no-recursion --files-from="$list_file"
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
		if ! rm -f -- "$tmp_tar" "$list_file"; then
			echo "Error: Archive was published, but temporary file cleanup failed." >&2
			return 1
		fi
		tmp_tar=""
		list_file=""
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

		if ! customshell_archive_require_tools; then
			return 1
		fi
		local auth_helper
		if ! auth_helper="$(customshell_archive_auth_helper)"; then
			return 1
		fi

		local archive
		archive="$(realpath -e -- "$1")" || return 1
		if [[ ! -f "$archive" ]]; then
			echo "Error: '$1' does not exist or is not a file."
			return 1
		fi

		local requested_dest="${2:-.}"
		local repository_root
		if [[ -n ${PROJ_DIR:-} ]]; then
			repository_root="$PROJ_DIR"
		else
			repository_root="$(dirname -- "${BASH_SOURCE[0]}")/../.."
		fi
		local dest
		if ! dest="$(python3 "$auth_helper" validate-destination "$requested_dest" \
			--home "${HOME:?HOME is not set}" --repository "$repository_root" 2>&1)"; then
			printf 'Error: %s\n' "$dest" >&2
			return 1
		fi

		local tmp_tar="" staging="" transaction=""
		local preserve_transaction=false
		trap '
            [[ -z "$tmp_tar" ]] || rm -f -- "$tmp_tar"
            [[ -z "$staging" ]] || rm -rf -- "$staging"
            if [[ -n "$transaction" && "$preserve_transaction" != true ]]; then rm -rf -- "$transaction"; fi
        ' EXIT
		tmp_tar="$(mktemp --suffix=.tar.gz)" || return 1
		chmod 600 -- "$tmp_tar" || return 1

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

		local parent dest_name
		parent="$(dirname -- "$dest")"
		dest_name="$(basename -- "$dest")"
		if [[ -d "$dest" ]]; then
			staging="$(mktemp -d "$dest/.${dest_name}.stage.XXXXXX")" || return 1
		else
			staging="$(mktemp -d "$parent/.${dest_name}.stage.XXXXXX")" || return 1
		fi

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
			transaction="$(mktemp -d "$dest/.${dest_name}.transaction.XXXXXX")" || return 1
			local backup="$transaction/backup"
			mkdir -- "$backup" || return 1

			local -a item_names=() backed_up=() published=()
			local staged_item item_name target_path

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

			# The archive holds exactly one top-level item. Publish it with
			# renames and a file-level merge so unrelated destination
			# content is never copied: only archived entries are written.
			local publish_failed=false publish_error="" index
			for staged_item in "${staged_items[@]}"; do
				item_name="${staged_item##*/}"
				target_path="$dest/$item_name"

				item_names+=("$item_name")
				backed_up+=(false)
				published+=(false)
				index=$((${#item_names[@]} - 1))

				if [[ ! -e "$target_path" && ! -L "$target_path" ]]; then
					# Fast path: nothing to merge, rename into place. Staging
					# lives on the destination volume, so this is atomic.
					if ! mv -- "$staged_item" "$target_path"; then
						publish_error="Failed to publish extracted archive target: $target_path"
						publish_failed=true
						break
					fi
					published[index]=true
				elif [[ -d "$target_path" && ! -L "$target_path" && -d "$staged_item" && ! -L "$staged_item" ]]; then
					# Directory merge: back up only colliding entries, then
					# overlay archived content. Unrelated existing entries
					# stay in place and are never copied.
					local backup_item="$backup/$item_name"
					if ! mkdir -- "$backup_item"; then
						publish_error="Failed to back up existing archive target: $target_path"
						publish_failed=true
						break
					fi
					local -a merge_new=() merge_backed=()
					local merge_failed=false src rel dst bkp bkp_parent k
					while IFS= read -r -d '' src; do
						rel="${src#"$staged_item"/}"
						dst="$target_path/$rel"
						bkp="$backup_item/$rel"
						if [[ -d "$src" && ! -L "$src" && -d "$dst" && ! -L "$dst" ]]; then
							continue
						fi
						if [[ -e "$dst" || -L "$dst" ]]; then
							bkp_parent="$(dirname -- "$bkp")"
							if ! mkdir -p -- "$bkp_parent"; then
								publish_error="Failed to back up existing archive target: $dst"
								merge_failed=true
								break
							fi
							if ! mv -- "$dst" "$bkp"; then
								publish_error="Failed to back up existing archive target: $dst"
								merge_failed=true
								break
							fi
							merge_backed+=("$rel")
						else
							merge_new+=("$rel")
						fi
					done < <(find "$staged_item" -mindepth 1 -print0)
					if [[ "$merge_failed" == true ]]; then
						for ((k = ${#merge_backed[@]} - 1; k >= 0; k--)); do
							rel="${merge_backed[$k]}"
							mv -- "$backup_item/$rel" "$target_path/$rel" 2>/dev/null || true
						done
						publish_failed=true
						break
					fi
					if ! cp -a -- "$staged_item/." "$target_path/"; then
						publish_error="Failed to publish extracted archive target: $target_path"
						for ((k = ${#merge_new[@]} - 1; k >= 0; k--)); do
							rm -rf -- "${target_path:?}/${merge_new[$k]}" 2>/dev/null || true
						done
						local merge_rollback_failed=false
						for ((k = ${#merge_backed[@]} - 1; k >= 0; k--)); do
							rel="${merge_backed[$k]}"
							rm -rf -- "${target_path:?}/$rel" 2>/dev/null || true
							if ! mv -- "$backup_item/$rel" "$target_path/$rel"; then
								merge_rollback_failed=true
							fi
						done
						if [[ "$merge_rollback_failed" == true ]]; then
							preserve_transaction=true
							echo "Error: $publish_error; rollback was incomplete. Original data is preserved under: $backup"
						else
							echo "Error: $publish_error; the original destination content was restored."
						fi
						return 1
					fi
				else
					# Type conflict: replace via renames, no data copy.
					if ! mv -- "$target_path" "$backup/$item_name"; then
						publish_error="Failed to back up existing archive target: $target_path"
						publish_failed=true
						break
					fi
					backed_up[index]=true
					if ! mv -- "$staged_item" "$target_path"; then
						publish_error="Failed to publish extracted archive target: $target_path"
						publish_failed=true
						break
					fi
					published[index]=true
				fi
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

		if ! rm -f -- "$tmp_tar" || ! rm -rf -- "$staging"; then
			echo "Error: Extracted content was published, but temporary file cleanup failed." >&2
			return 1
		fi
		tmp_tar=""
		staging=""
		echo "Extracted to: $dest"
	)
}
