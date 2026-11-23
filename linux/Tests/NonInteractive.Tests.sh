#!/usr/bin/env bash

# Exercises the env-only non-interactive entry point from BASH_ENV in a
# disposable environment. It verifies silence, portability defaults, path
# idempotency, and that no interactive startup runs, without touching the user's
# shell or Git configuration.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p "$test_root/home"

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
entry_script="$repo_dir/linux/noninteractive.sh"
user_bin="$test_root/home/.local/bin"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# run_isolated invokes Bash with the entry point as BASH_ENV and nothing else
# inherited, so the result cannot depend on the developer's own environment.
run_isolated() {
	env -i HOME="$test_root/home" PATH=/usr/bin:/bin BASH_ENV="$entry_script" "$@"
}

# Sourcing through BASH_ENV is silent on both streams, for commands and for
# scripts, and does not fail the caller.
output="$(run_isolated bash -c ':' 2>&1)" || fail "non-interactive Bash failed with BASH_ENV"
[[ -z "$output" ]] || fail "entry point produced output: $output"

printf '#!/usr/bin/env bash\nprintf ok\n' >"$test_root/script.sh"
output="$(run_isolated bash "$test_root/script.sh" 2>&1)" || fail "non-interactive script failed"
[[ "$output" == ok ]] || fail "entry point corrupted script output: $output"

# User-local commands are reachable from a plain non-interactive shell.
command_path="$(run_isolated bash -c 'printf "%s" "$PATH"')" ||
	fail "failed to read the non-interactive PATH"
[[ ":$command_path:" == *":$user_bin:"* ]] ||
	fail "user-local bin directory missing from PATH: $command_path"

# Portable defaults fill only missing values and reach the shell.
portable_values="$(
	run_isolated bash -c 'printf "%s|%s|%s" "${TMPDIR:-}" "${PROJECTS_L:-}" "${PROJECTS_W-unset}"'
)" || fail "failed to read the portable defaults"
[[ "$portable_values" == "/tmp|$test_root/home/projects_l|unset" ]] ||
	fail "unexpected portable defaults: $portable_values"

override_values="$(
	env -i HOME="$test_root/home" PATH=/usr/bin:/bin \
		TMPDIR="$test_root/temp dir" PROJECTS_L="$test_root/alt projects" \
		USERPROFILE="$test_root/windows" BASH_ENV="$entry_script" \
		bash -c 'printf "%s|%s|%s" "${TMPDIR:-}" "${PROJECTS_L:-}" "${PROJECTS_W:-}"'
)" || fail "failed to read overridden portable values"
[[ "$override_values" == "$test_root/temp dir|$test_root/alt projects|$test_root/windows/projects_w" ]] ||
	fail "existing portable values were not preserved: $override_values"

# Repeated sourcing in one shell stays idempotent.
duplicate_count="$(
	env -i HOME="$test_root/home" PATH=/usr/bin:/bin BASH_ENV="$entry_script" \
		bash -c '. "$1"; . "$1"; printf "%s" "$PATH"' bash "$entry_script" |
		tr ':' '\n' | grep -Fxc "$user_bin"
)" || fail "failed to source the entry point twice"
[[ "$duplicate_count" == 1 ]] || fail "repeated sourcing duplicated PATH entries"

# A strict caller script is unaffected by BASH_ENV.
run_isolated bash -c 'set -euo pipefail; :' ||
	fail "entry point broke a strict-mode caller"

# No interactive setup runs: no agent, prompt theme, or startup help.
side_effects="$(
	run_isolated bash -c 'printf "%s|%s" "${SSH_AUTH_SOCK-unset}" "${OMP_THEME-unset}"'
)" || fail "failed to inspect non-interactive side effects"
[[ "$side_effects" == "unset|unset" ]] ||
	fail "interactive setup ran in a non-interactive shell: $side_effects"

# A relocated entry point without its core files stays silent and inert.
lonely_dir="$test_root/lonely"
mkdir -p "$lonely_dir"
cp "$entry_script" "$lonely_dir/noninteractive.sh"
output="$(
	env -i HOME="$test_root/home" PATH=/usr/bin:/bin \
		BASH_ENV="$lonely_dir/noninteractive.sh" bash -c 'printf "%s" "$PATH"' 2>&1
)" || fail "relocated entry point failed"
[[ "$output" == "/usr/bin:/bin" ]] ||
	fail "entry point changed PATH without its core files: $output"

# A missing HOME is tolerated without diagnostics; paths.sh is not sourced.
output="$(
	env -i PATH=/usr/bin:/bin BASH_ENV="$entry_script" bash -c 'printf "%s" "${HOME-unset}"' 2>&1
)" || fail "entry point failed without HOME"
[[ "$output" == unset ]] || fail "entry point reported a problem without HOME: $output"

echo "Non-interactive tests passed"
