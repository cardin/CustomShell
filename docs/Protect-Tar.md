# Protect-Tar and Unprotect-Tar

This document defines the required behavior of the paired encrypted archive
commands on Windows PowerShell and Linux Bash.

## Command interface

```text
Protect-Tar <source> [output_base] [--exclude <pattern>]... [--no-ignore]
Protect-Tar --help

Unprotect-Tar <archive.enc> [destination]
Unprotect-Tar --help
```

- Both platforms must implement the same arguments, behavior, and exit status.
- `--help` succeeds without checking dependencies or changing the filesystem.
- `--exclude <pattern>` is optional and repeatable. It applies only to directory
  input, uses archive-relative glob patterns, and combines repeated patterns.
  Missing or empty patterns fail before any filesystem change.
- Directory archiving recursively applies exclusion rules from `.tarignore`
  files by default (equivalent to GNU tar's `--exclude-ignore-recursive=.tarignore`).
  Empty lines and lines beginning with `#` are ignored.
  `--no-ignore` disables this default handling so ignored files are archived.

## Input and output

- `source` must identify exactly one existing regular file or directory.
- The source basename and type are stored as the archive's single top-level
  item and are recreated during extraction.
- Filesystem roots and output locations inside a source directory are refused.
- `output_base` is optional. The output filename is always
  `<output_base>_YYYYMMDD_HHMMSS.enc`, using local system time. Without an
  output base, the source path and basename are used.
- An existing generated output path is not replaced.
- The parent directories of `output_base` and `destination` must already exist.

## Archive format

New archives use the version 2 format encrypted with `age`:

1. An `age-encryption.org/v1` container.
2. A recipient stanza using `scrypt` for passphrase key derivation.
3. A ChaCha20-Poly1305 authenticated payload containing one gzip-compressed
   tar archive.

Integrity and authentication are verified cryptographically by `age` prior to
decompression or extraction. Tampered, truncated, or incorrectly keyed archives
fail during decryption before any destination data is touched.

Archives created by either platform must be extractable by the other, except
that Windows rejects Linux archives containing symbolic or hard links.

Passphrase input is handled directly by `age`. Empty input or cancelled prompts
fail before publishing output. Passphrases must not be printed, logged, stored
in environment variables, or passed in process arguments.

## Requirements

Linux

- Python 3.8 or newer for path and tar validation
- `tar` (GNU or compatible with `--exclude-ignore-recursive`)
- `realpath`
- `age`

Windows

- Requires PowerShell 7
- `tar.exe` (bsdtar/libarchive)
- `age.exe`.

## Portable contents

- Member paths must be relative and must remain beneath the staged top-level
  item after treating both `/` and `\` as separators.
- Parent traversal, absolute paths, drive-qualified paths, UNC paths, Windows
  device paths, unsupported tar member types, duplicate paths, and
  case-insensitive path collisions are rejected before publication.
- Linux creation rejects names that cannot be recreated on Windows.
- Portable recreation covers names, item types, file contents, directory
  structure, and modification times. Ownership, ACLs, extended attributes,
  alternate data streams, and platform-specific mode bits are best effort.
- Windows fails when creation or extraction encounters symbolic links, hard
  links, junctions, mount points, or other reparse points.
- Linux preserves symbolic and hard links. Extraction must not follow an
  archive link while writing another member outside the staging tree.

## Extraction and collisions

- `destination` is a container directory and defaults to the current directory.
  The destination directory itself is never renamed or replaced.
- The archive is authenticated, decrypted, validated, and extracted in private
  staging locations before destination content changes.
- If the top-level item already exists, an interactive terminal prompts once
  before publication. Only an explicit affirmative response proceeds.
- A declined prompt or a collision without an interactive terminal fails with
  no destination change. There is no noninteractive force option.
- Approved directory collisions merge recursively. Archived entries replace
  colliding entries, while unrelated existing entries remain. File/directory
  type conflicts are replaced by the archived type.

## Progress reporting

Interactive sessions provide stage indicators and live percentage updates:

- **Stage tracking:** Both commands display four progress stages (validation,
  packaging/extraction, encryption/decryption with `age`, and finalization).
- **Tar percentage progress:** During tar creation and extraction, progress is
  updated in place with a percentage and processed-item counter.
- **Terminal isolation:** Progress output is suppressed in non-interactive and
  redirected sessions, keeping logs and pipes clean.

## Failure safety

- Before publication begins, errors leave existing output and destination data
  unchanged and remove temporary plaintext and encrypted data.
- Publication journals every affected item and rolls changes back in reverse
  order if a handled error occurs. Empty parent directories created by the
  command are removed after failure.
- If automatic rollback cannot complete, original data is retained in a
  permission-restricted recovery directory and its path is reported clearly.
- Cleanup failure is reported and must not be described as a clean success.
- Temporary files, test data, passwords, and recovery data must never use real
  credentials or network services.

## Format and version history

### Version 2 (Current)

- **Container format:** Standard `age` encrypted file (`age-encryption.org/v1`),
  using scrypt passphrase key derivation and ChaCha20-Poly1305 AEAD payload.
- **Integrity verification:** Cryptographic authentication is enforced by `age`
  prior to tar decompression and extraction.
- **Source types:** Supports both single regular files and directory trees.
- **Naming:** Enforces `<output_base>_YYYYMMDD_HHMMSS.enc`.
- **Collisions:** Requires explicit user confirmation on an interactive
  terminal to merge into an existing destination item; fails without changes in
  non-interactive contexts.
- **Introduced in:** CustomShell.Commands module version 2.0.0 and updated Linux
  tooling.

### Version 1 (Discontinued)

- **Container format:** Raw OpenSSL `enc` format (AES-256-CBC with PBKDF2,
  salt, and 600,000 iterations), prefixed with the standard OpenSSL `Salted__`
  header.
- **Integrity verification:** None.
- **Support status:** Discontinued; superseded by Version 2 `age` archives.
