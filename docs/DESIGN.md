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
- Linux may configure Git credentials, manage a reusable `ssh-agent`, and
  regenerate CustomShell's `environment.d` file. PowerShell startup does not
  change global Git configuration.

## Compatibility and safety

- Public command names and startup paths are compatibility surfaces.
- `Show-Help` is the cross-shell command-reference entry point. It replaces
  PowerShell's `Show-CustomShellHelp` and Bash's `manShell`.
- `Protect-Tar` and `Unprotect-Tar` requirements and format specifications are
  defined in [Protect-Tar.md](Protect-Tar.md).
- Destructive operations must resolve narrow targets and reject broad or empty
  paths.
- Secrets, passwords, certificates, and private key material must not be
  printed, logged, or committed.

## Known gaps

- Most Bash helpers beyond startup and archives lack regression coverage.
- Device detection relies on a username heuristic.
