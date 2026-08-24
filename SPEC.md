# CustomShell specification

## Purpose

CustomShell is a personal shell configuration for PowerShell on Windows and
Bash on Linux/WSL. It provides a consistent prompt, optional tool integrations,
convenience commands, and shared CLI configuration.

Primary environments are Windows 11 with PowerShell 7 and Ubuntu-like Linux or
WSL2 with interactive Bash. Missing optional tools must not prevent shell
startup.

## Behavior

### Startup

- PowerShell and Bash load the selected prompt, tool integrations, aliases, and
  helper functions into the interactive session.
- PowerShell loads reusable archive and SSH commands through the import-safe
  `CustomShell.Commands` module. Importing the module alone has no profile or
  external configuration side effects.
- The module exports the archive pair `Encode-Tar` and `Decode-Tar`, plus the
  SSH parser `Get-SSHConfig`.
- Prompt selection supports Oh My Posh and Starship, including a plain theme
  for constrained or embedded terminals.
- Startup diagnostics and command help appear only in appropriate interactive
  contexts and remain suppressed in embedded or nested sessions.
- Linux and WSL setup detects its environment and exposes Windows
  interoperability helpers only under WSL.
- Linux sourcing may update the global Git credential cache, start `ssh-agent`,
  and regenerate CustomShell's Linux `environment.d` file. PowerShell startup
  does not mutate global Git configuration.

## Compatibility and safety

- Archive formats and cryptographic parameters are compatibility surfaces.
  Interactive command names and startup file locations may change when the
  corresponding behavior and documentation are updated together.
- PowerShell OpenSSL archives use AES-256-CBC with PBKDF2, salt, and 600,000
  iterations. Preserve parameters needed to decrypt existing archives.
- Destructive mirroring, replacement, extraction, and cleanup must operate only
  on resolved, narrow targets. Never recursively target an empty path,
  filesystem root, home directory, or repository root.
- Failed replacement operations must preserve existing data.
- Archive extraction must reject path traversal.
- Windows operations reject operating on locations that contain symbolic-link and hard-link members.
- Operations publishes destination changes transactionally, and preserves recoverable
  backups when automatic rollback cannot complete.
- Secrets, passwords, certificates, and private key material must not be
  printed, logged, or committed.
- Startup should remain quiet and responsive.
- Startup files must tolerate repeated sourcing. Optional generated
  shell initialization code must be non-empty and successful before execution.

## Known gaps

- Bash helpers lack automated regression tests.
- Linux encrypted-archive helpers do not yet match PowerShell replacement,
  cleanup, traversal, and password-handling safeguards.
- Device detection relies on a username heuristic.
- Some Linux third-party startup invocations can emit errors for malformed
  output.
