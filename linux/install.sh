#!/usr/bin/env bash
# shellcheck disable=SC1090,SC1091,SC2034

# Idempotent setup and upgrade helper for CustomShell on Linux and WSL. It wires
# the Bash entry point into the user's rc file, publishes persistent environment
# values, links shipped tool configuration into place, and reports missing
# prerequisites. It never installs packages and never touches secrets, SSH data,
# CA certificates, Git credentials, or environment.d state directly.
#
# The work is split across modules under linux/install/: common helpers, the
# managed profile block, persistent environment values, Espanso configuration,
# and read-only checks.

set -u

project_dir="$({ cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P; })"
install_dir="$project_dir/linux/install"
entry_script="$project_dir/linux/main.sh"
config_dir="$project_dir/config"

marker_begin="# >>> CustomShell >>>"
marker_end="# <<< CustomShell <<<"

mode="install"
dry_run=false
force=false

bashrc="${HOME:?HOME is not set}/.bashrc"
espanso_root=""

source "$install_dir/common.sh"
source "$install_dir/profile.sh"
source "$install_dir/environment.sh"
source "$install_dir/espanso.sh"
source "$install_dir/checks.sh"

usage() {
	cat <<EOF
Usage: install.sh [options]

Wires CustomShell into the current user's shell profile, publishes persistent
environment values, and links the shipped tool configuration. Safe to run
repeatedly.

Options:
  --check              Report current state without changing anything.
  --dry-run            Print intended actions without changing anything.
  --uninstall          Remove the CustomShell profile block and managed links.
  --force              Replace conflicting configuration files (with backups).
  --bashrc <path>      Override the rc file to edit (default: ~/.bashrc).
  --espanso-root <dir> Override the Espanso configuration root.
  -h, --help           Show this help and exit.
EOF
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--check)
		mode="check"
		;;
	--dry-run)
		dry_run=true
		;;
	--uninstall)
		mode="uninstall"
		;;
	--force)
		force=true
		;;
	--bashrc)
		shift
		[[ $# -gt 0 ]] || {
			say "Error: --bashrc requires a path." >&2
			exit 2
		}
		bashrc=$1
		;;
	--espanso-root)
		shift
		[[ $# -gt 0 ]] || {
			say "Error: --espanso-root requires a path." >&2
			exit 2
		}
		espanso_root=$1
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		say "Error: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

# The managed block contains the persistent environment exports followed by the
# entry-point source line.
desired_block_lines=()
while IFS= read -r line; do
	[[ -n "$line" ]] && desired_block_lines+=("$line")
done < <(customshell_persistent_env_lines)
desired_block_lines+=(". $(shell_single_quote "$entry_script")")

espanso_initialize

case "$mode" in
install)
	write_profile_block || exit 1
	link_espanso || exit 1
	report_commands
	if [[ "$dry_run" == true ]]; then
		say "Dry run complete; no changes made."
	else
		say "CustomShell setup complete. Restart your shell or run: . $bashrc"
	fi
	;;
uninstall)
	remove_profile_block || exit 1
	unlink_espanso || exit 1
	if [[ "$dry_run" == true ]]; then
		say "Dry run complete; no changes made."
	else
		say "CustomShell profile block and managed links removed."
	fi
	;;
check)
	report_checks || exit 1
	;;
esac
