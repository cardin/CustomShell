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
- Shared tool configuration is read from the repository at runtime where
  possible. When a tool cannot do that, setup installs or registers the
  configuration as described in [Install.md](Install.md).
- Linux may configure Git credentials, manage a reusable `ssh-agent`, and
  regenerate CustomShell's `environment.d` file. PowerShell startup does not
  change global Git configuration.

## Setup and upgrades

- `pwsh/Install.ps1` and `linux/install.sh` are the supported setup paths:
  idempotent, safe to re-run, and removable via their uninstall mode. Behavior
  lives in module files under `linux/install/` and `pwsh/Install/` so each
  concern is independently testable, and every target is resolved from the
  entry point's own location.
- Setup stays declarative: it wires the profile entry point, persists the
  environment values, and installs or registers the configuration described in
  [Install.md](Install.md). It delegates runtime mutation to existing startup
  code and never installs packages, escalates privileges, or modifies secrets,
  SSH, CA, or Git state.
- Persistent environment values are installer-owned on both platforms and always
  win over conflicts. Windows writes the User scope; Linux exports them from the
  managed profile block and runtime startup publishes them for the systemd user
  session. Setup records what it set so uninstall can reverse it, and profile
  startup never sets these values.
- Clink is the one integration referenced by repository path: setup configures it
  through the Clink CLI, follows the selected prompt, and restores prior
  settings on uninstall.
- Setup reports unavailable expected commands on every run, so startup performs
  no command discovery; `Show-Help` remains the startup reminder.

## Compatibility and safety

- Public command names and startup paths are compatibility surfaces.
- Destructive operations must resolve narrow targets and reject broad or empty
  paths.
- Secrets, passwords, certificates, and private key material must not be
  printed, logged, or committed.

## Known gaps

- Most Bash helpers beyond startup and archives lack regression coverage.
- Device detection relies on a username heuristic.
