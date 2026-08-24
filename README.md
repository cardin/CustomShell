# Windows

For Windows, you can git clone this repository into `~/Documents`.

Append the following line to `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`:

```ps1
. "$env:USERPROFILE\Documents\CustomShell\pwsh\main.ps1"
```

The profile reads defaults from `pwsh/Settings.psd1`. Set `Prompt` to
`ohmyposh`, `starship`, or `none`, and adjust `RequiredCommands` to control the
standalone-terminal startup check.

Reusable commands are loaded from the import-safe `CustomShell.Commands`
module:

- `Encode-Tar` creates an AES-256-CBC encrypted tar archive.
- `Decode-Tar` safely decrypts and transactionally extracts one. It rejects
  link entries and protected broad destinations such as the filesystem root,
  home directory, and CustomShell repository root.
- `Get-SSHConfig` reads concrete aliases from an SSH client config.

The `pwsh/Startup` files separately configure environment values, aliases,
optional integrations, PSReadLine, prompts, and standalone-terminal status.
Optional tools are skipped when unavailable or when they return invalid
initialization code.

# Linux

For Linux, you can git clone this repository into `~/.config/CustomShell`.

Alternatively, you can just pull the artefacts in:

```sh
curl -L https://github.com/cardin/CustomShell/archive/refs/heads/master.tar.gz | tar xz --strip 1
```

Append the following line to your Bash Profile `~/.bashrc`:

```sh
. ~/config/CustomShell/linux/main.sh
```

## PowerShell tests

The PowerShell regression tests require Pester 3.4 or newer and `tar.exe` in
`PATH`:

```ps1
Invoke-Pester ./pwsh/Tests
```

The suite includes unit coverage for reusable commands and an isolated
`pwsh -NoProfile` test that sources the profile twice.

## Project documentation

- [Behavioral specification](SPEC.md)
- [Contributor and coding-agent guidance](AGENTS.md)
