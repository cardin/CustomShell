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

- `Protect-Tar <source> [archive]` creates an encrypted tar archive.
- `Unprotect-Tar <archive> <destination>` safely extracts one.
- PowerShell also provides `Get-SSHConfig` for reading SSH host aliases.
- `batx <file>` displays files with `bat` without line numbers when `bat` is installed.

PowerShell and Linux use compatible archive formats. Replacement and extraction
are staged, and unsafe paths and links are rejected.

## PowerShell tests

The PowerShell regression tests require Pester 3.4 or newer and `tar.exe` in
`PATH`:

```ps1
Invoke-Pester ./pwsh/Tests
```

## Project documentation

- [Design and behavioral constraints](DESIGN.md)
- [Contributor and coding-agent guidance](AGENTS.md)
