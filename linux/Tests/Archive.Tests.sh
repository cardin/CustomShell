#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2329

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

protect_help="$(Protect-Tar --help)" || fail "Protect-Tar --help failed"
[[ "$protect_help" == *"USAGE"* ]] || fail "Protect-Tar help has no usage section"
[[ "$protect_help" == *"ChaCha20-Poly1305"* ]] ||
	fail "Protect-Tar help has no encryption details"
[[ "$protect_help" == *"--exclude"* ]] ||
	fail "Protect-Tar help has no exclude details"

unprotect_help="$(Unprotect-Tar --help)" || fail "Unprotect-Tar --help failed"
[[ "$unprotect_help" == *"USAGE"* ]] || fail "Unprotect-Tar help has no usage section"
[[ "$unprotect_help" == *"transactional"* ]] ||
	fail "Unprotect-Tar help has no extraction details"
[[ "$unprotect_help" == *"[destination_directory]"* ]] ||
	fail "Unprotect-Tar help does not show an optional destination"

mkdir -p "$test_root/bin" "$test_root/source"
echo "archive test" >"$test_root/source/content.txt"

mock_age="$test_root/bin/age"
cat >"$mock_age" <<'EOF'
#!/usr/bin/env bash
output=""
input=""
mode=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        -p) mode="encrypt"; shift ;;
        -d) mode="decrypt"; shift ;;
        *) input="$1"; shift ;;
    esac
done
if [[ "${AGE_FAIL:-false}" == true ]]; then
    [[ -z "$output" ]] || : >"$output"
    exit 1
fi
if [[ "$mode" == "encrypt" ]]; then
    hash="$(sha256sum "$input" | cut -d' ' -f1)"
    {
        printf "age-encryption.org/v1\n"
        printf "%s\n" "$hash"
        cat "$input"
    } >"$output"
elif [[ "$mode" == "decrypt" ]]; then
    header="$(head -n 1 "$input")"
    if [[ "$header" != "age-encryption.org/v1" ]]; then
        exit 1
    fi
    expected_hash="$(sed -n '2p' "$input")"
    actual_hash="$(tail -n +3 "$input" | sha256sum | cut -d' ' -f1)"
    if [[ "$expected_hash" != "$actual_hash" ]]; then
        exit 1
    fi
    tail -n +3 "$input" >"$output"
fi
EOF
chmod +x "$mock_age"
export PATH="$test_root/bin:$PATH"

archive_base="$test_root/archive"
Protect-Tar "$test_root/source" "$archive_base" >/dev/null ||
	fail "Protect-Tar failed"
archives=("$archive_base"_*.enc)
[[ ${#archives[@]} -eq 1 ]] || fail "Protect-Tar did not create exactly one archive"
archive="${archives[0]}"
[[ -f "$archive" ]] || fail "Protect-Tar did not publish its output"
[[ "$(basename -- "$archive")" =~ ^archive_[0-9]{8}_[0-9]{6}\.enc$ ]] ||
	fail "Protect-Tar did not apply the required datetime suffix"
[[ "$(dd if="$archive" bs=1 count=21 status=none)" == "age-encryption.org/v1" ]] ||
	fail "Protect-Tar did not create a version 2 authenticated archive"

Protect-Tar "$test_root/source" >/dev/null ||
	fail "Protect-Tar failed with its default output base"
default_archives=("$test_root"/source_*.enc)
[[ ${#default_archives[@]} -eq 1 ]] ||
	fail "Protect-Tar default output did not use the source basename"

bad_name="$test_root/bad:name.txt"
echo "not portable" >"$bad_name"
printf 'password\npassword\n' | Protect-Tar "$bad_name" "$test_root/bad-name" \
	>/dev/null 2>&1 && fail "Protect-Tar accepted a Windows-incompatible name"

file_source="$test_root/input.txt"
echo "file input" >"$file_source"
Protect-Tar "$file_source" "$test_root/file-archive" >/dev/null ||
	fail "Protect-Tar rejected file input"
file_archives=("$test_root"/file-archive_*.enc)
file_destination="$test_root/file-restored"
Unprotect-Tar "${file_archives[0]}" "$file_destination" >/dev/null ||
	fail "Unprotect-Tar failed to restore file input"
[[ "$(<"$file_destination/input.txt")" == "file input" ]] ||
	fail "Unprotect-Tar did not recreate the input file"

exclude_source="$test_root/exclude-source"
mkdir -p "$exclude_source/node_modules"
echo "keep" >"$exclude_source/keep.txt"
echo "drop" >"$exclude_source/drop.log"
echo "dep" >"$exclude_source/node_modules/dep.txt"
exclude_base="$test_root/exclude"
Protect-Tar --exclude node_modules --exclude '*.log' \
	"$exclude_source" "$exclude_base" >/dev/null ||
	fail "Protect-Tar with --exclude failed"
exclude_archives=("$exclude_base"_*.enc)
exclude_cipher="$test_root/exclude.cipher"
age -d -o "$exclude_cipher" "${exclude_archives[0]}" || fail "archive decryption failed"
exclude_listing="$(tar -tzf "$exclude_cipher")"
[[ "$exclude_listing" == *"keep.txt"* ]] ||
	fail "Protect-Tar --exclude removed an included file"
[[ "$exclude_listing" != *"drop.log"* ]] ||
	fail "Protect-Tar --exclude did not omit a matched file pattern"
[[ "$exclude_listing" != *"node_modules"* ]] ||
	fail "Protect-Tar --exclude did not omit a matched directory"

Protect-Tar --exclude >/dev/null 2>&1 &&
	fail "Protect-Tar accepted --exclude without a pattern"

tarignore_source="$test_root/tarignore-source"
mkdir -p "$tarignore_source/sub" "$tarignore_source/ignored_dir"
echo "keep" >"$tarignore_source/keep.txt"
echo "drop" >"$tarignore_source/drop.tmp"
echo "sub keep" >"$tarignore_source/sub/sub_keep.txt"
echo "sub drop" >"$tarignore_source/sub/sub_drop.bin"
echo "deep" >"$tarignore_source/ignored_dir/deep.txt"
printf "*.tmp\nignored_dir\n# comment\n" >"$tarignore_source/.tarignore"
printf "sub_drop.bin\n" >"$tarignore_source/sub/.tarignore"
tarignore_base="$test_root/tarignore-out"
Protect-Tar "$tarignore_source" "$tarignore_base" >/dev/null ||
	fail "Protect-Tar with .tarignore failed"
tarignore_archives=("$tarignore_base"_*.enc)
tarignore_cipher="$test_root/tarignore.cipher"
age -d -o "$tarignore_cipher" "${tarignore_archives[0]}" || fail "archive decryption failed"
tarignore_listing="$(tar -tzf "$tarignore_cipher")"
[[ "$tarignore_listing" == *"keep.txt"* ]] ||
	fail ".tarignore removed an included file"
[[ "$tarignore_listing" != *"drop.tmp"* ]] ||
	fail ".tarignore did not omit root pattern *.tmp"
[[ "$tarignore_listing" == *"sub_keep.txt"* ]] ||
	fail ".tarignore removed included nested file"
[[ "$tarignore_listing" != *"sub_drop.bin"* ]] ||
	fail ".tarignore did not omit nested pattern sub_drop.bin"
[[ "$tarignore_listing" != *"ignored_dir"* ]] ||
	fail ".tarignore did not omit ignored directory"

noignore_base="$test_root/noignore-out"
Protect-Tar --no-ignore "$tarignore_source" "$noignore_base" >/dev/null ||
	fail "Protect-Tar with --no-ignore failed"
noignore_archives=("$noignore_base"_*.enc)
noignore_cipher="$test_root/noignore.cipher"
age -d -o "$noignore_cipher" "${noignore_archives[0]}" || fail "archive decryption failed"
noignore_listing="$(tar -tzf "$noignore_cipher")"
[[ "$noignore_listing" == *"drop.tmp"* ]] ||
	fail "--no-ignore omitted a .tarignore-matched file"
[[ "$noignore_listing" == *"sub_drop.bin"* ]] ||
	fail "--no-ignore omitted a nested .tarignore-matched file"
[[ "$noignore_listing" == *"ignored_dir"* ]] ||
	fail "--no-ignore omitted a .tarignore-matched directory"

destination="$test_root/restored"
Unprotect-Tar "$archive" "$destination" >/dev/null ||
	fail "Unprotect-Tar failed"
[[ "$(<"$destination/source/content.txt")" == "archive test" ]] ||
	fail "Unprotect-Tar did not restore the archived content"

default_destination="$test_root/default-restored"
mkdir -p "$default_destination"
default_destination_identity="$(stat -c '%d:%i' "$default_destination")"
(
	cd "$default_destination" || exit 1
	Unprotect-Tar "$archive" >/dev/null
) || fail "Unprotect-Tar failed with its default destination"
[[ "$(<"$default_destination/source/content.txt")" == "archive test" ]] ||
	fail "Unprotect-Tar did not use the current directory by default"
[[ "$(stat -c '%d:%i' "$default_destination")" == "$default_destination_identity" ]] ||
	fail "Unprotect-Tar replaced its current destination directory"

echo "unrelated" >"$destination/unrelated.txt"
Unprotect-Tar "$archive" "$destination" >/dev/null 2>&1 &&
	fail "Unprotect-Tar replaced a collision without an interactive terminal"
[[ "$(<"$destination/unrelated.txt")" == "unrelated" ]] ||
	fail "declined noninteractive extraction changed the destination"
printf 'y\n' | script -qfec \
	"source '$PROJ_DIR/linux/commands/archive.sh'; Unprotect-Tar '$archive' '$destination'" \
	/dev/null >/dev/null ||
	fail "Unprotect-Tar failed to merge into an existing destination"
[[ "$(<"$destination/unrelated.txt")" == "unrelated" ]] ||
	fail "Unprotect-Tar removed unrelated destination content"

rollback_destination="$test_root/rollback-destination"
mkdir -p "$rollback_destination"
echo "original" >"$rollback_destination/original.txt"

# mv
# Injects a publication failure while allowing item backup and rollback renames.
mv() {
	local arguments=("$@")
	local source_path="${arguments[${#arguments[@]} - 2]}"
	local destination_path="${arguments[${#arguments[@]} - 1]}"
	if [[ "$source_path" == *".transaction."*"/candidate/source" && "$destination_path" == "$rollback_destination/source" ]]; then
		return 1
	fi
	command mv "$@"
}
Unprotect-Tar "$archive" "$rollback_destination" \
	>/dev/null 2>&1 && fail "Unprotect-Tar succeeded when publication failed"
unset -f mv
[[ "$(<"$rollback_destination/original.txt")" == "original" ]] ||
	fail "Unprotect-Tar did not roll back the original destination"
[[ -z "$(find "$test_root" -maxdepth 1 -name '.rollback-destination.*' -print -quit)" ]] ||
	fail "failed extraction publication left staging or backup directories"

failed_base="$test_root/failed"
AGE_FAIL=true Protect-Tar \
	"$test_root/source" "$failed_base" >/dev/null 2>&1 &&
	fail "Protect-Tar succeeded when encryption failed"
[[ -z "$(find "$test_root" -maxdepth 1 -name 'failed_*.enc' -print -quit)" ]] ||
	fail "failed encryption published an archive"
[[ -z "$(find "$test_root" -maxdepth 1 -name '.failed_*.tmp' -print -quit)" ]] ||
	fail "failed encryption left a temporary encrypted file"

mkdir -p "$test_root/temp"
TMPDIR="$test_root/temp" AGE_FAIL=true Unprotect-Tar \
	"$archive" "$test_root/failed-restore" >/dev/null 2>&1 &&
	fail "Unprotect-Tar succeeded when decryption failed"
[[ -z "$(find "$test_root/temp" -mindepth 1 -print -quit)" ]] ||
	fail "failed decryption left a temporary tar"

link_source="$test_root/link-source"
mkdir -p "$link_source"
echo "linked content" >"$link_source/content.txt"
ln -s content.txt "$link_source/content-link.txt"
ln "$link_source/content.txt" "$link_source/content-hardlink.txt"
Protect-Tar "$link_source" "$test_root/link-archive" >/dev/null ||
	fail "Protect-Tar failed on link source"
link_archives=("$test_root"/link-archive_*.enc)
Unprotect-Tar "${link_archives[0]}" "$test_root/link-restore" >/dev/null ||
	fail "Unprotect-Tar rejected link entries"
[[ -L "$test_root/link-restore/link-source/content-link.txt" ]] ||
	fail "Unprotect-Tar did not preserve a symbolic link"
[[ "$(readlink "$test_root/link-restore/link-source/content-link.txt")" == content.txt ]] ||
	fail "Unprotect-Tar changed a symbolic-link target"
[[ "$test_root/link-restore/link-source/content.txt" -ef "$test_root/link-restore/link-source/content-hardlink.txt" ]] ||
	fail "Unprotect-Tar did not preserve a hard link"

tampered_archive="$test_root/tampered.enc"
cp -- "$archive" "$tampered_archive"
printf '\001' | dd of="$tampered_archive" bs=1 seek=80 conv=notrunc status=none
Unprotect-Tar "$tampered_archive" "$test_root/tampered-restore" \
	>/dev/null 2>&1 && fail "Unprotect-Tar accepted a modified authenticated archive"
[[ ! -e "$test_root/tampered-restore" ]] ||
	fail "tampered archive changed the destination"

traversal_tar="$test_root/traversal.tar.gz"
tar -czf "$traversal_tar" --transform='s|^|../|' \
	-C "$test_root/source" content.txt
traversal_archive="$test_root/traversal-archive.enc"
age -p -o "$traversal_archive" "$traversal_tar"
Unprotect-Tar "$traversal_archive" "$test_root/traversal-restore" \
	>/dev/null 2>&1 && fail "Unprotect-Tar accepted a parent-directory entry"
[[ ! -e "$test_root/traversal-restore" ]] ||
	fail "rejected traversal archive changed the destination"

Unprotect-Tar "$archive" / >/dev/null 2>&1 &&
	fail "Unprotect-Tar accepted the filesystem root"

echo "Archive tests passed"
