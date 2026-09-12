# CustomShell

Personal PowerShell and Bash configuration for a consistent prompt, aliases,
and optional tool integrations across Windows, Linux, and WSL.

- [Install.md](docs/Install.md) — setup, upgrade, options, and environment values.
- [DESIGN.md](docs/DESIGN.md) — runtime and setup principles.

## Windows

Clone into `~/Documents` and run the setup script:

```ps1
git clone https://github.com/cardin/CustomShell "$env:USERPROFILE\Documents\CustomShell"
& "$env:USERPROFILE\Documents\CustomShell\pwsh\Install.ps1"
```

Setup wires the all-hosts profile, persists environment values, and installs or
registers the shared tool configuration. It is safe to re-run and supports
`-Check`, `-DryRun`, and `-Uninstall`. The prompt and the expected-command list
are configured in `pwsh/Settings.psd1`. See [Install.md](docs/Install.md).

Manual alternative — append this to `~/Documents/PowerShell/profile.ps1` (the
all-hosts profile, not a host-specific one). It loads the shell configuration
but not the persistent environment values:

```ps1
. "$env:USERPROFILE\Documents\CustomShell\pwsh\main.ps1"
```

## Linux

Clone into `~/.config/CustomShell` and run the setup script:

```sh
git clone https://github.com/cardin/CustomShell ~/.config/CustomShell
bash ~/.config/CustomShell/linux/install.sh
```

Or download the tree directly:

```sh
curl -L https://github.com/cardin/CustomShell/archive/refs/heads/master.tar.gz | tar xz --strip 1
```

Setup wires `~/.bashrc`, persists environment values, and installs or links the
shared tool configuration. It is safe to re-run and supports `--check`,
`--dry-run`, and `--uninstall`. See [Install.md](docs/Install.md).

Manual alternative — append this to `~/.bashrc`. It loads the shell
configuration but not the persistent environment values:

```sh
. ~/.config/CustomShell/linux/main.sh
```

## Commands

- `Show-Help` displays the compact CustomShell command reference in both shells.
- `Protect-Tar` and `Unprotect-Tar` create and extract encrypted archives. See [Protect-Tar.md](docs/Protect-Tar.md).
- `mirror-win-ssh` mirrors the Windows SSH directory into WSL. See [Mirror-Win-Ssh.md](docs/Mirror-Win-Ssh.md).
- PowerShell also provides `Get-SSHConfig` for reading SSH host aliases.
- Commands listed in `WslCommands` (`pwsh/Settings.psd1`) are exposed as
  PowerShell commands that run inside the default WSL distribution when no
  native command exists. Currently `opencode` and `agent-deck`.

## PowerShell tests

The PowerShell regression tests require Pester 5.0 or newer and `tar.exe` in
`PATH`:

```ps1
Invoke-Pester ./pwsh/Tests
```

## Project documentation

- [Specification](docs/)
- [Contributor and coding-agent guidance](AGENTS.md)
