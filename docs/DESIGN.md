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
- WSL-exposed commands are declared in `pwsh/Settings.psd1` (`WslCommands`) and
  wrapped only when no native command exists. Arguments are forwarded to an
  interactive login Bash through `wsl -e` with CustomShell's startup output
  suppressed, so the command resolves from the user's own environment.
- When `bat` is available, `config/bat.conf` supplies file output with header
  and grid decorations but no line numbers across shells. On Windows the
  installer persists `BAT_CONFIG_PATH` to that file; Linux startup exports it.
- Linux may configure Git credentials, manage a reusable `ssh-agent`, and
  regenerate CustomShell's `environment.d` file. PowerShell startup does not
  change global Git configuration.

## Setup and upgrades

- `pwsh/Install.ps1` and `linux/install.sh` are the supported setup paths. They
  are idempotent, safe to re-run, and removable via their uninstall mode.
- Setup only wires the profile entry point, persists a small set of user
  environment values, and installs configuration that the runtime does not
  reference by repository path. It delegates all runtime mutation to existing
  startup code and never installs packages or modifies secrets, SSH, CA, or Git
  state.
- Persistent environment values (currently `UV_SYSTEM_CERTS`) always win,
  overwriting conflicts, and are recorded so uninstall can reverse them.
- Persistent environment values are installer-owned on both platforms: Windows
  writes the User environment scope; Linux exports them from the managed profile
  block. Profile startup does not set them, so the former
  `Initialize-Environment.ps1` startup path was removed.
- Setup owns missing-required-command reporting: `pwsh/Install.ps1` and
  `linux/install.sh` report unavailable expected commands on every run, so
  profile startup performs no command discovery. `Show-Help` remains the startup
  reminder.
- Setup entry points stay thin; behavior lives in module files under
  `linux/install/` and `pwsh/Install/` so each concern is independently
  testable. Setup resolves every target from its own location and refuses to
  modify unrecognized content or broad paths.

## Compatibility and safety

- Public command names and startup paths are compatibility surfaces.
- `Show-Help` is the cross-shell command-reference entry point. It replaces
  PowerShell's `Show-CustomShellHelp` and Bash's `manShell`.
- Destructive operations must resolve narrow targets and reject broad or empty
  paths.
- Secrets, passwords, certificates, and private key material must not be
  printed, logged, or committed.

## Known gaps

- Most Bash helpers beyond startup and archives lack regression coverage.
- Device detection relies on a username heuristic.
