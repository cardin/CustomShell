# AGENTS.md

Maintain CustomShell as defined in `SPEC.md`. Read that file before changing
behavior; do not duplicate its product contracts here.

## Change guidance

- Inspect the full sourcing chain before editing startup behavior. Variables
  and functions are shared across sourced files, and load order matters.
- Guard optional integrations with `Get-Command`, `command -v`, or a directory
  check. Preserve the existing terminal/tmux gates around startup output.
- Keep platform code under `pwsh/` or `linux/`; shared tool configuration
  belongs in `config/`.
- Avoid adding user-specific paths, usernames, hosts, certificates, or install
  locations. Do not rename public functions, aliases, variables, or config
  paths without documenting the compatibility impact.
- Preserve OS-native line endings: CRLF for Windows scripts and LF for Unix
  scripts.

Treat changes to archive helpers, `mirror-win-ssh`, CA handling, Git credential
configuration, and `environment.d` generation as high risk. Add regression
coverage for changed behavior, including failure and cleanup paths. Tests must
use unique temporary directories and mock interactive tools; never use real
credentials or network services.

## Validation

PowerShell:

```powershell
Invoke-Pester ./pwsh/Tests
```

If Pester is unavailable, parse changed `.ps1` files with PowerShell's AST
parser and report that behavioral tests were skipped.

Bash:

```bash
bash -n linux/main.sh linux/*.sh linux/pretty/*.sh
shellcheck linux/main.sh linux/*.sh linux/pretty/*.sh
```

Report a missing `shellcheck`. Do not source `linux/main.sh` in the user's
normal shell during testing; use a disposable process and temporary `HOME`.
Use the owning tool to validate changed files under `config/` when available.

## Completion

- Update `README.md` for installation, prerequisites, or user-facing commands.
- Update `SPEC.md` when behavior, compatibility, supported environments, or
  known gaps change.
- Report files changed, checks run or skipped, and compatibility impact.
