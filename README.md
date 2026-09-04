# CustomShell

Personal PowerShell and Bash configuration for a consistent prompt, aliases,
and optional tool integrations across Windows, Linux, and WSL.

## Windows

For Windows, you can git clone this repository into `~/Documents`.

Append the following line to `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`:

```ps1
. "$env:USERPROFILE\Documents\CustomShell\pwsh\main.ps1"
```

Configure the prompt and startup command checks in `pwsh/Settings.psd1`.

## Linux

For Linux, you can git clone this repository into `~/.config/CustomShell`.

Alternatively, you can just pull the artefacts in:

```sh
curl -L https://github.com/cardin/CustomShell/archive/refs/heads/master.tar.gz | tar xz --strip 1
```

Append the following line to `~/.bashrc`:

```sh
. ~/.config/CustomShell/linux/main.sh
```

## Commands

- `Show-Help` displays the compact CustomShell command reference in both shells.
- `Protect-Tar` and `Unprotect-Tar` create and extract encrypted archives. See [Protect-Tar.md](docs/Protect-Tar.md) for usage, prerequisites, and specifications.
- PowerShell also provides `Get-SSHConfig` for reading SSH host aliases.
- `batx <file>` displays files with `bat` without line numbers when `bat` is installed.

## PowerShell tests

The PowerShell regression tests require Pester 3.4 or newer and `tar.exe` in
`PATH`:

```ps1
Invoke-Pester ./pwsh/Tests
```

## Project documentation

- [Specification](docs/)
- [Contributor and coding-agent guidance](AGENTS.md)
