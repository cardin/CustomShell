# CustomShell requirements

This is the canonical list of essential outcomes and safeguards.
[Interfaces](INTERFACES.md) and the [command references](reference/README.md)
own flags, formats, defaults, and detailed behaviour. [Design](DESIGN.md) owns
implementation choices. [Test plan](TESTPLAN.md) maps checks and gaps to both
requirements and contracts.

Use at most five requirements per section. New areas start at `001`; keep IDs
stable when entries are removed. Substantive changes need human approval.

## Startup

See the [Bash](DESIGN.md#bash-startup) and
[PowerShell](DESIGN.md#powershell-startup) startup flows.

- **REQ-STARTUP-001:** Reload either profile without errors or duplicate effects.
- **REQ-STARTUP-002:** Missing optional tools must not prevent shell startup.
- **REQ-STARTUP-003:** Keep startup quiet outside appropriate interactive
  sessions, including embedded, nested, and explicitly quiet sessions.
- **REQ-STARTUP-004:** Give non-interactive Bash the user-local command paths and
  portable defaults without interactive output, prompt, certificate, or agent
  setup.

## WSL interoperability

See [WSL command wrappers](INTERFACES.md#wsl-command-wrappers).

- **REQ-WSL-001:** Enable Windows interoperability in the Linux profile only
  on WSL.
- **REQ-WSL-002:** Make configured WSL commands available in PowerShell without
  shadowing native commands.
- **REQ-WSL-003:** Install a `cmd.exe` shim on PATH on WSL so processes that
  start without the Windows directories, such as the OpenCode Desktop server,
  can launch Windows programs and the default browser.

## Installation

See the [installation reference](reference/Install.md).

- **REQ-INSTALL-001:** Setup must be safe to rerun and inspect without changes.
  Uninstall must reverse managed changes without discarding local edits.
- **REQ-INSTALL-002:** Setup must not install packages, elevate privileges, or
  change secrets, SSH data, or CA state. The WSL `cmd.exe` shim is the only
  system file setup may write with sudo. Global Git changes are limited to the
  Linux installer's credential helper.
- **REQ-INSTALL-003:** Configure both shells to load CustomShell. Make managed
  Linux environment values available in login shells.

## Archives

See the [archive command reference](reference/Protect-Tar.md).

- **REQ-ARCHIVE-001:** Provide a common interface and interoperable archives on
  Bash and PowerShell, subject to documented portability limits.
- **REQ-ARCHIVE-003:** Honor directory exclusions. Fail rather than include
  potentially excluded files when exclusion rules cannot be evaluated.
- **REQ-ARCHIVE-004:** Create encrypted archives and authenticate them before
  decompression or extraction.
- **REQ-ARCHIVE-007:** Reject unsafe paths and archive contents. Roll back
  handled publication failures; preserve recoverable originals and report
  their location if rollback fails.
- **REQ-ARCHIVE-008:** Never overwrite an existing output archive. Require
  explicit interactive approval before modifying colliding extraction targets.

## WSL SSH mirror

See the [SSH mirror reference](reference/Mirror-Win-Ssh.md).

- **REQ-MIRROR-001:** Mirror Windows SSH files into WSL by replacement, not
  merging, with permissions suitable for OpenSSH.
- **REQ-MIRROR-003:** Reject unsafe paths. On failure, preserve the prior SSH
  data or report where to recover it if restoration fails.
