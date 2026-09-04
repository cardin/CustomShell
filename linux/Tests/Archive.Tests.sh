#!/usr/bin/env bash

# Exercises Linux archive command naming, round trips, and failure cleanup with
# a disposable directory and a deterministic OpenSSL test double.

set -u

test_root="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$test_root"' EXIT

# fail
# Reports an assertion failure and terminates the archive test script.
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

PROJ_DIR="$(realpath -e -- "$(dirname "${BASH_SOURCE[0]}")/../..")"
source "$(dirname "${BASH_SOURCE[0]}")/../commands/archive.sh"

declare -F Protect-Tar >/dev/null || fail "Protect-Tar is not defined"
declare -F Unprotect-Tar >/dev/null || fail "Unprotect-Tar is not defined"
declare -F tar_gpg >/dev/null && fail "tar_gpg should have been removed"
declare -F untar_gpg >/dev/null && fail "untar_gpg should have been removed"
declare -F tar_enc >/dev/null && fail "tar_enc should have been renamed"
declare -F untar_enc >/dev/null && fail "untar_enc should have been renamed"

protect_help="$(Protect-Tar -h)" || fail "Protect-Tar -h failed"
[[ "$protect_help" == *"USAGE"* ]] || fail "Protect-Tar help has no usage section"
[[ "$protect_help" == *"600,000 iterations"* ]] ||
    fail "Protect-Tar help has no encryption details"
[[ "$protect_help" == *"--exclude"* ]] ||
    fail "Protect-Tar help has no exclude details"

unprotect_help="$(Unprotect-Tar -h)" || fail "Unprotect-Tar -h failed"
[[ "$unprotect_help" == *"USAGE"* ]] || fail "Unprotect-Tar help has no usage section"
[[ "$unprotect_help" == *"transactional"* ]] ||
    fail "Unprotect-Tar help has no extraction details"
[[ "$unprotect_help" == *"[destination_directory]"* ]] ||
    fail "Unprotect-Tar help does not show an optional destination"

mkdir -p "$test_root/bin" "$test_root/source"
echo "archive test" >"$test_root/source/content.txt"

mock_openssl="$test_root/bin/openssl"
cat >"$mock_openssl" <<'EOF'
#!/usr/bin/env bash
input=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -in) input="$2"; shift 2 ;;
        -out) output="$2"; shift 2 ;;
        -iter) iterations="$2"; shift 2 ;;
        -d) shift ;;
        *) shift ;;
    esac
done
if [[ "${OPENSSL_FAIL:-false}" == true ]]; then
    [[ -z "$output" ]] || : >"$output"
    exit 1
fi
if [[ "${iterations:-}" != 600000 ]]; then
    [[ -z "$output" ]] || : >"$output"
    exit 1
fi
cp -- "$input" "$output"
EOF
chmod +x "$mock_openssl"
export PATH="$test_root/bin:$PATH"

archive="$test_root/source.tar.gz.enc"
printf 'password\n' | Protect-Tar "$test_root/source" "$archive" >/dev/null ||
    fail "Protect-Tar failed"
[[ -f "$archive" ]] || fail "Protect-Tar did not publish its output"

plaintext_sibling="${archive%.enc}"
echo "preserve sibling" >"$plaintext_sibling"
printf 'password\n' | Protect-Tar "$test_root/source" "$archive" >/dev/null ||
    fail "Protect-Tar failed while replacing an archive"
[[ "$(<"$plaintext_sibling")" == "preserve sibling" ]] ||
    fail "Protect-Tar changed the filename formerly used for temporary data"

exclude_source="$test_root/exclude-source"
mkdir -p "$exclude_source/node_modules"
echo "keep" >"$exclude_source/keep.txt"
echo "drop" >"$exclude_source/drop.log"
echo "dep" >"$exclude_source/node_modules/dep.txt"
exclude_archive="$test_root/exclude.tar.gz.enc"
printf 'password\n' | Protect-Tar --exclude node_modules --exclude '*.log' \
    "$exclude_source" "$exclude_archive" >/dev/null ||
    fail "Protect-Tar with --exclude failed"
exclude_listing="$(tar -tzf "$exclude_archive")"
[[ "$exclude_listing" == *"keep.txt"* ]] ||
    fail "Protect-Tar --exclude removed an included file"
[[ "$exclude_listing" != *"drop.log"* ]] ||
    fail "Protect-Tar --exclude did not omit a matched file pattern"
[[ "$exclude_listing" != *"node_modules"* ]] ||
    fail "Protect-Tar --exclude did not omit a matched directory"

printf 'password\n' | Protect-Tar --exclude >/dev/null 2>&1 &&
    fail "Protect-Tar accepted --exclude without a pattern"

destination="$test_root/restored"
printf 'password\n' | Unprotect-Tar "$archive" "$destination" >/dev/null ||
    fail "Unprotect-Tar failed"
[[ "$(<"$destination/source/content.txt")" == "archive test" ]] ||
    fail "Unprotect-Tar did not restore the archived content"

default_destination="$test_root/default-restored"
mkdir -p "$default_destination"
(
    cd "$default_destination" || exit 1
    printf 'password\n' | Unprotect-Tar "$archive" >/dev/null
) || fail "Unprotect-Tar failed with its default destination"
[[ "$(<"$default_destination/source/content.txt")" == "archive test" ]] ||
    fail "Unprotect-Tar did not use the current directory by default"

echo "unrelated" >"$destination/unrelated.txt"
printf 'password\n' | Unprotect-Tar "$archive" "$destination" >/dev/null ||
    fail "Unprotect-Tar failed to merge into an existing destination"
[[ "$(<"$destination/unrelated.txt")" == "unrelated" ]] ||
    fail "Unprotect-Tar removed unrelated destination content"

rollback_destination="$test_root/rollback-destination"
mkdir -p "$rollback_destination"
echo "original" >"$rollback_destination/original.txt"

# mv
# Injects a publication failure while allowing staging and rollback renames.
mv() {
    local arguments=("$@")
    local source_path="${arguments[${#arguments[@]} - 2]}"
    local destination_path="${arguments[${#arguments[@]} - 1]}"
    if [[ "$source_path" == *".stage."* && "$destination_path" == "$rollback_destination" ]]; then
        return 1
    fi
    command mv "$@"
}
printf 'password\n' | Unprotect-Tar "$archive" "$rollback_destination" \
    >/dev/null 2>&1 && fail "Unprotect-Tar succeeded when publication failed"
unset -f mv
[[ "$(<"$rollback_destination/original.txt")" == "original" ]] ||
    fail "Unprotect-Tar did not roll back the original destination"
[[ -z "$(find "$test_root" -maxdepth 1 -name '.rollback-destination.*' -print -quit)" ]] ||
    fail "failed extraction publication left staging or backup directories"

failed_archive="$test_root/failed.tar.gz.enc"
echo "original archive" >"$failed_archive"
printf 'password\n' | OPENSSL_FAIL=true Protect-Tar \
    "$test_root/source" "$failed_archive" >/dev/null 2>&1 &&
    fail "Protect-Tar succeeded when encryption failed"
[[ "$(<"$failed_archive")" == "original archive" ]] ||
    fail "failed encryption did not preserve the existing archive"
[[ -z "$(find "$test_root" -maxdepth 1 -name '.failed.tar.gz.enc.*.tmp' -print -quit)" ]] ||
    fail "failed encryption left a temporary encrypted file"

mkdir -p "$test_root/temp"
printf 'password\n' | TMPDIR="$test_root/temp" OPENSSL_FAIL=true Unprotect-Tar \
    "$archive" "$test_root/failed-restore" >/dev/null 2>&1 &&
    fail "Unprotect-Tar succeeded when decryption failed"
[[ -z "$(find "$test_root/temp" -mindepth 1 -print -quit)" ]] ||
    fail "failed decryption left a temporary tar"

link_source="$test_root/link-source"
mkdir -p "$link_source"
ln -s /tmp "$link_source/external"
link_archive="$test_root/link-archive.tar.gz.enc"
tar -czf "$link_archive" -C "$test_root" link-source
printf 'password\n' | Unprotect-Tar "$link_archive" "$test_root/link-restore" \
    >/dev/null 2>&1 && fail "Unprotect-Tar accepted a symbolic-link entry"
[[ ! -e "$test_root/link-restore" ]] ||
    fail "rejected link archive changed the destination"

traversal_archive="$test_root/traversal-archive.tar.gz.enc"
tar -czf "$traversal_archive" --transform='s|^|../|' \
    -C "$test_root/source" content.txt
printf 'password\n' | Unprotect-Tar "$traversal_archive" "$test_root/traversal-restore" \
    >/dev/null 2>&1 && fail "Unprotect-Tar accepted a parent-directory entry"
[[ ! -e "$test_root/traversal-restore" ]] ||
    fail "rejected traversal archive changed the destination"

Unprotect-Tar "$archive" / >/dev/null 2>&1 &&
    fail "Unprotect-Tar accepted the filesystem root"

echo "Archive tests passed"
