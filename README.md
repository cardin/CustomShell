# CustomShell

Personal PowerShell and Bash configuration for a consistent prompt, aliases,
and optional tool integrations across Windows, Linux, and WSL.

## Setup

Windows, cloned into `~/Documents`:

```ps1
git clone https://github.com/cardin/CustomShell "$env:USERPROFILE\Documents\CustomShell"
& "$env:USERPROFILE\Documents\CustomShell\pwsh\Install.ps1"
```

Linux and WSL, cloned into `~/.config/CustomShell`:

```sh
git clone https://github.com/cardin/CustomShell ~/.config/CustomShell
bash ~/.config/CustomShell/linux/install.sh
```

Setup is idempotent and safe to re-run. It supports `-Check`/`--check`,
`-DryRun`/`--dry-run`, and `-Uninstall`/`--uninstall`. Options, persistent
environment values, and platform details are in
[Install.md](docs/reference/Install.md).

In Windows PowerShell, run `opencode-wsl` to launch OpenCode in the default
WSL distribution. Inside WSL, the command is still `opencode`.

Scripts can use `TMPDIR`, `USER`, `HOME`, `PROJECTS_W`, and `PROJECTS_L` on both
sides after setup. See
[portable environment variables](docs/INTERFACES.md#portable-environment-variables)
for defaults and session scope.

## Documentation

- [Requirements](docs/REQUIREMENTS.md) — required behavior and constraints.
- [Design](docs/DESIGN.md) — runtime and setup principles.
- [Interfaces](docs/INTERFACES.md) — commands, settings, and state-file contracts.
- [Test plan](docs/TESTPLAN.md) — verification mapping and known gaps.
- [Decisions](docs/ADR.md) — accepted architecture decisions.
- [Reference](docs/reference/README.md) — installation, archives, and SSH mirror.
- [Contributor and coding-agent guidance](AGENTS.md) — validation commands and change workflow.

`Show-Help` lists the interactive commands in either shell.
