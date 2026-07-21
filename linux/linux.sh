#!/usr/bin/env bash
function tar_gpg {
	local -r target_path=$1
	local -r other_args="${*:2}"

	if [[ $# -lt 1 ]] || [[ ! -e "$target_path" ]]; then
		echo "[ERROR] Given Input: $*"
		echo "USAGE: tar_gpg <target> [--exclude a] [--exclude b]"
		return 1
	fi

	# if targetpath ends in TAR or TGZ, do nothing
	if [[ "$target_path" == *.tar ]] || [[ "$target_path" == *.tgz ]]; then
		local -r archive_name="$target_path"
	else
		local -r archive_name="$(basename "$target_path")_$(date +%Y%m%d-%H%M%S).tgz"
		tar "$other_args" -czf "$archive_name" -R "$(basename "$target_path")"
	fi

	# GPG it
	local -r gpg_name="$archive_name.gpg"
	echo ""
	read -r -p "Press ENTER to encrypt with password." </dev/tty
	gpg --output "$gpg_name" --symmetric "$archive_name"

	# Test password
	echo ""
	read -r -p "Press ENTER to test decryption with password." </dev/tty
	gpg --no-symkey-cache --decrypt "$gpg_name" >/dev/null

	# if targetpath ends in TAR or TGZ, do nothing
	if [[ "$target_path" == *.tar ]] || [[ "$target_path" == *.tgz ]]; then
		echo ""
	else
		rm "$archive_name"
	fi
}

function untar_gpg {
	local -r gpg_file=$1
	local -r archive_name="$(basename "${gpg_file::-4}")"

	if [[ $# -ne 1 ]] || [[ ! -f "$gpg_file" ]]; then
		echo "[ERROR] Given Input: $*"
		echo "USAGE: untar_gpg <gpg_file>"
		return 1
	fi

	gpg --output "$archive_name" --decrypt "$gpg_file"

	local -r target_path="${archive_name::-4}"
	mkdir "$target_path"
	tar -xf "$archive_name" -C "$target_path"
	rm "$archive_name"
}

function tar_enc {
	if [[ $# -ne 2 ]]; then
		echo "Usage: tar_enc <source_directory> <output_file.tar.gz.enc>"
		return 1
	fi

	local src="$1"
	local out="$2"

	if [[ ! -d "$src" ]]; then
		echo "Error: '$src' is not a directory."
		return 1
	fi

	if ! command -v openssl >/dev/null 2>&1; then
		echo "Error: openssl not found in PATH."
		return 1
	fi

	local tmp="${out%.enc}"
	if [[ "$tmp" == "$out" ]]; then
		tmp="${out}.tmp.tar.gz"
	fi

	read -rsp "Password: " password
	echo

	if ! tar -czf "$tmp" -C "$(dirname "$src")" "$(basename "$src")"; then
		echo "Error: Failed to create archive."
		return 1
	fi

	if ! openssl enc -aes-256-cbc -pbkdf2 -salt \
		-in "$tmp" \
		-out "$out" \
		-pass "pass:$password"; then
		rm -f "$tmp"
		echo "Error: Encryption failed."
		return 1
	fi

	rm -f "$tmp"
	unset password

	echo "Created: $out"
}

function untar_enc {
	if [[ $# -ne 2 ]]; then
		echo "Usage: untar_enc <archive.tar.gz.enc> <destination_directory>"
		return 1
	fi

	local archive="$1"
	local dest="$2"

	if [[ ! -f "$archive" ]]; then
		echo "Error: '$archive' does not exist."
		return 1
	fi

	if ! command -v openssl >/dev/null 2>&1; then
		echo "Error: openssl not found in PATH."
		return 1
	fi

	mkdir -p "$dest" || return 1

	local tmp
	tmp="$(mktemp --suffix=.tar.gz)" || return 1

	read -rsp "Password: " password
	echo

	if ! openssl enc -d -aes-256-cbc -pbkdf2 \
		-in "$archive" \
		-out "$tmp" \
		-pass "pass:$password"; then
		rm -f "$tmp"
		echo "Error: Decryption failed (incorrect password?)."
		return 1
	fi

	if ! tar -xzf "$tmp" -C "$dest"; then
		rm -f "$tmp"
		echo "Error: Failed to extract archive."
		return 1
	fi

	rm -f "$tmp"
	unset password

	echo "Extracted to: $dest"
}

function dt_str {
	date +"%Y-%m-%d_%H%M"
}

# Headless Linux SSH issue
if ! pgrep -u "$USER" ssh-agent >/dev/null; then
	eval "$(ssh-agent -s)" >/dev/null
fi

# Git
git config --global credential.helper 'cache --timeout=21600'

# ===  GNOME Scrollbar issue ===
# https://bbs.archlinux.org/viewtopic.php?id=196118
export GTK_OVERLAY_SCROLLING=0
