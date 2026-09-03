# CustomShell design

## Purpose

CustomShell provides consistent interactive shell behavior across PowerShell
on Windows and Bash on Linux/WSL. Windows 11 with PowerShell 7 and Ubuntu-like
Linux or WSL2 are the primary environments.

Startup entry points compose small platform-specific files. Reusable PowerShell
commands live in an import-safe module; importing it must not run profile setup
or change external configuration. Shared tool configuration lives under
`config/`.

## Runtime principles

- Missing optional tools must not prevent startup, and generated initialization
  code must be successful and non-empty before execution.
- Repeated sourcing must be safe. Startup output belongs only in appropriate
  interactive contexts and remains suppressed in embedded or nested sessions.
- Prompt engines initialize before zoxide so its directory-tracking hook wraps
  the final prompt function and remains active.
- Platform-specific features activate only where supported; Windows
  interoperability helpers are limited to WSL.
- When `bat` is available, `batx` is the cross-shell shortcut for file output
  with header and grid decorations but no line numbers.
- `Protect-Tar -h` and `Unprotect-Tar -h` display command usage and archive
  safety details without checking dependencies or changing the filesystem.
- Linux may configure Git credentials, manage a reusable `ssh-agent`, and
  regenerate CustomShell's `environment.d` file. PowerShell startup does not
  change global Git configuration.

## Compatibility and safety

- Public command names, startup paths, archive formats, and cryptographic
  parameters are compatibility surfaces. PowerShell and Linux archives use
  AES-256-CBC with PBKDF2, salt, and 600,000 iterations.
- `Protect-Tar` accepts repeatable glob exclude patterns (`-Exclude` on
  PowerShell, `--exclude` on Bash) passed through to tar's `--exclude` option
  on both platforms.
- `Show-Help` is the cross-shell command-reference entry point. It replaces
  PowerShell's `Show-CustomShellHelp` and Bash's `manShell`.
- Destructive operations must resolve narrow targets and reject broad or empty
  paths. Archive extraction must reject traversal and link entries.
- Replacement and extraction are transactional: failures preserve existing
  data, with recoverable backups when automatic rollback cannot complete.
- Secrets, passwords, certificates, and private key material must not be
  printed, logged, or committed.

## Known gaps

- Most Bash helpers beyond startup and archives lack regression coverage.
- Linux encrypted-archive passwords are supplied to OpenSSL through process
  arguments rather than PowerShell-style secure prompting.
- Device detection relies on a username heuristic.
