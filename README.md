# CustomShell

Personal PowerShell and Bash configuration for a consistent prompt, aliases,
and optional tool integrations across Windows, Linux, and WSL.

## Windows

For Windows, clone this repository into `~/Documents` and run the setup script:

```ps1
git clone https://github.com/cardin/CustomShell "$env:USERPROFILE\Documents\CustomShell"
& "$env:USERPROFILE\Documents\CustomShell\pwsh\Install.ps1"
```

The script wires the profile entry point, sets persistent environment values,
installs the shipped Espanso and Clink configuration files, and reports missing
prerequisites. It is safe to re-run after upgrades or when the clone moves, and
supports `-Check`, `-DryRun`, and `-Uninstall`. See [Install.md](docs/Install.md).

Configure the prompt and the expected-command list reported by setup in
`pwsh/Settings.psd1`.

Manual alternative: append the following line to
`~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`:

```ps1
. "$env:USERPROFILE\Documents\CustomShell\pwsh\main.ps1"
```

Note: the setup script also applies persistent environment values; this manual
alternative does not.

## Linux

For Linux, clone this repository into `~/.config/CustomShell` and run the setup
script:

```sh
git clone https://github.com/cardin/CustomShell ~/.config/CustomShell
bash ~/.config/CustomShell/linux/install.sh
```

The script wires `~/.bashrc`, sets persistent environment values, links the
shipped Espanso configuration, and reports missing prerequisites. It is safe to
re-run, and supports `--check`, `--dry-run`, and `--uninstall`. See
[Install.md](docs/Install.md).

Alternatively, you can just pull the artefacts in:

```sh
curl -L https://github.com/cardin/CustomShell/archive/refs/heads/master.tar.gz | tar xz --strip 1
```

Manual alternative: append the following line to `~/.bashrc`:

```sh
. ~/.config/CustomShell/linux/main.sh
```

Note: the setup script also applies persistent environment values; this manual
alternative does not.

## Commands

- `Show-Help` displays the compact CustomShell command reference in both shells.
- `Protect-Tar` and `Unprotect-Tar` create and extract encrypted archives. See [Protect-Tar.md](docs/Protect-Tar.md).
- `mirror-win-ssh` mirrors the Windows SSH directory into WSL. See [Mirror-Win-Ssh.md](docs/Mirror-Win-Ssh.md).
- PowerShell also provides `Get-SSHConfig` for reading SSH host aliases.
- When `bat` is installed, `config/bat.conf` configures it with header and grid
  decorations and no line numbers.
- Commands listed in `WslCommands` (`pwsh/Settings.psd1`) are exposed as
  PowerShell commands that run inside the default WSL distribution when no
  native command exists. Currently `codex`, `opencode`, and `agent-deck`.

## PowerShell tests

The PowerShell regression tests require Pester 5.0 or newer and `tar.exe` in
`PATH`:

```ps1
Invoke-Pester ./pwsh/Tests
```

## Project documentation

- [Specification](docs/)
- [Contributor and coding-agent guidance](AGENTS.md)
