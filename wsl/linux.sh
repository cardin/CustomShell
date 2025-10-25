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

function dt_str {
	date +"%Y-%m-%d_%H%M"
}

# Headless Linux SSH issue
if ! pgrep -u "$USER" ssh-agent >/dev/null; then
	eval "$(ssh-agent -s)" >/dev/null
fi

# ===  GNOME Scrollbar issue ===
# https://bbs.archlinux.org/viewtopic.php?id=196118
export GTK_OVERLAY_SCROLLING=0
