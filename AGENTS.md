# AGENTS.md

Maintain CustomShell as defined in `DESIGN.md`. Read it before changing
behavior; this file contains only contribution guidance.

## Change guidance

- Inspect the full sourcing chain before editing startup behavior; sourced
  files share state and depend on load order.
- Guard optional integrations and preserve the terminal/tmux gates around
  startup output.
- Keep platform code under `pwsh/` or `linux/` and shared tool configuration
  under `config/`.
- Do not add user-specific data or rename public interfaces without documenting
  the compatibility impact.
- Preserve OS-native line endings: CRLF for Windows scripts and LF for Unix
  scripts.

Archive, SSH mirroring, CA, Git credential, and `environment.d` changes are
high risk. Cover their success, failure, and cleanup paths with isolated tests;
never use real credentials or network services.

## Validation

PowerShell:

```powershell
Invoke-Pester ./pwsh/Tests
```

If Pester is unavailable, parse changed `.ps1` files with PowerShell's AST
parser and report that behavioral tests were skipped.

Bash:

```bash
find linux -type f -name '*.sh' -print0 | xargs -0 bash -n
find linux -type f -name '*.sh' -print0 | xargs -0 shellcheck
bash linux/Tests/Archive.Tests.sh
bash linux/Tests/Environment.Tests.sh
bash linux/Tests/Startup.Tests.sh
bash linux/Tests/Wsl.Tests.sh
```

Report a missing `shellcheck`. Do not source `linux/main.sh` in the user's
normal shell during testing; use a disposable process and temporary `HOME`.
Use the owning tool to validate changed files under `config/` when available.

## Completion

- Update `README.md` for installation, prerequisites, or user-facing commands.
- Update `DESIGN.md` when behavior, compatibility, supported environments, or
  known gaps change.
- Report files changed, checks run or skipped, and compatibility impact.
