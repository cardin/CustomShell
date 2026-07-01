#!/usr/bin/env bash
if [ -z ${USERPROFILE+x} ]; then
	echo -e "${Blue}Need to share WSL variable \$USERPROFILE!"
	echo -e "${Blue}Ignore this error if you're using \"su -\". Next time, use \"su root\"."
fi

release-ram() { echo 1 | sudo tee /proc/sys/vm/drop_caches; }

mirror-win-ssh() {
	set -e

	if ! command -v rsync >/dev/null 2>&1; then
		echo "Error: rsync is not installed." >&2
		echo "Install it with: sudo apt install rsync" >&2
		return 1
	fi

	if ! command -v cmd.exe >/dev/null 2>&1; then
		echo "Error: cmd.exe not found. Are you running inside WSL?" >&2
		return 1
	fi

	local src="$USERPROFILE/.ssh"
	local dest="$HOME/.ssh"

	if [ ! -d "$src" ]; then
		echo "Windows .ssh directory not found: $src" >&2
		return 1
	fi

	mkdir -p "$dest"

	# Mirror contents, including deletions.
	rsync -a --delete "$src/" "$dest/"

	# Fix permissions for OpenSSH.
	chmod 700 "$dest"
	find "$dest" -type d -exec chmod 700 {} \;
	find "$dest" -type f -exec chmod 600 {} \;

	# Files that may be world-readable.
	find "$dest" -type f -name '*.pub' -exec chmod 644 {} \;
	[ -f "$dest/known_hosts" ] && chmod 644 "$dest/known_hosts"

	# Files that must remain private.
	[ -f "$dest/authorized_keys" ] && chmod 600 "$dest/authorized_keys"
	[ -f "$dest/config" ] && chmod 600 "$dest/config"

	echo "Mirrored $src -> $dest"
	ls -ld "$dest"
	ls -l "$dest"
}
