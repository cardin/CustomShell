# CustomShell test plan

This document records checks and coverage gaps for the
[essential requirements](REQUIREMENTS.md) and detailed contracts.

## Running the checks

### PowerShell

Prerequisites: Windows, PowerShell 7, Pester 5.0 or newer, Git, `tar.exe`,
and Python 3.8 or newer (`python3` or `python` on `PATH`).

```powershell
Invoke-Pester ./pwsh/Tests
```

If Pester is unavailable, parse changed `.ps1` files with PowerShell's AST
parser and report that behavioural tests were skipped.

### Bash

Prerequisites: Linux or WSL, Bash, Git, Python 3.8 or newer (`python3`),
GNU `tar`, and util-linux `script` for the archive suite. Report a missing
`shellcheck` if linting is unavailable. Archive interoperability additionally
needs WSL with a runnable `pwsh.exe` or `pwsh_guest.exe` and access to the
Windows temporary directory.

```bash
find linux -type f -name '*.sh' -print0 | xargs -0 bash -n
find linux -type f -name '*.sh' -print0 | xargs -0 shellcheck
bash linux/Tests/Archive.Tests.sh
bash linux/Tests/Archive.Interop.Tests.sh
bash linux/Tests/Environment.Tests.sh
bash linux/Tests/Install.Tests.sh
bash linux/Tests/Startup.Tests.sh
bash linux/Tests/Wsl.Tests.sh
```

`linux/Tests/Archive.Tests.sh` also runs `tools/Tests/ArchiveCore.Tests.py`.

### Test isolation

Use disposable processes and temporary `HOME` directories for startup tests;
never source `linux/main.sh` in the user's normal shell. Use test fixtures, not
real credentials, SSH data, certificates, or network services. WSL tests mock
`rsync`, `cmd.exe`, and `wslpath`; archive tests use `age` test doubles.

## Scenarios

| ID | Requirement or contract | Location | What it verifies |
| --- | --- | --- | --- |
| TP-STARTUP-01 | REQ-STARTUP-001, REQ-STARTUP-002 (partial), REQ-STARTUP-003 (partial) | `linux/Tests/Startup.Tests.sh` | Repeated sourcing is safe, commands are defined, startup checks do not run, `TMOUT`/device flags are set, both environment artifacts keep their inode, the agent starts once, and the fnm path is not duplicated. |
| TP-STARTUP-02 | [Prompt configuration](reference/Install.md#prompt-configuration), [Bash startup](DESIGN.md#bash-startup) | `linux/Tests/Startup.Tests.sh` | `PROMPT_COMMAND` hooks survive repeated sourcing in order, and Oh My Posh/Starship theme selection matches standalone, WSL-bare, and native-bare contexts. |
| TP-WSL-01 | REQ-WSL-001 (partial), REQ-MIRROR-001 (partial), REQ-MIRROR-003 (partial) | `linux/Tests/Wsl.Tests.sh` | `mirror-win-ssh` publishes new content, removes stale entries, leaves data untouched when staging fails, and cleans staging; `USERPROFILE` is derived or warned about; the `BROWSER` wrapper is generated, stale-safe, mount-aware, and never overwrites a value. |
| TP-PWSH-01 | REQ-STARTUP-001, [PowerShell module](INTERFACES.md#powershell-module) | `pwsh/Tests/Integration/Profile.Tests.ps1` | The profile loads twice without errors, exports module commands, and keeps the zoxide hook active after prompt initialization. |
| TP-PWSH-02 | REQ-STARTUP-002 (partial) | `pwsh/Tests/Unit/Integrations.Tests.ps1` | An empty VS Code shell-integration path is ignored instead of executed. |
| TP-PWSH-03 | REQ-WSL-002 | `pwsh/Tests/Unit/InteractiveAliases.Tests.ps1` | A configured WSL command routes through a suppressed login shell, a renamed alias forwards to the original WSL command without shadowing native commands, and managed aliases are removed when settings change. |
| TP-PWSH-04 | REQ-STARTUP-003 (partial) | `pwsh/Tests/Unit/StartupStatus.Tests.ps1` | `Show-Help` exists, the obsolete missing-command helper is gone, and startup does not warn about configured commands. |
| TP-PWSH-05 | [Prompt configuration](reference/Install.md#prompt-configuration) | `pwsh/Tests/Unit/Prompt.Tests.ps1` | Starship uses the plain-text theme outside a standalone terminal and the powerline theme inside one. |
| TP-PWSH-06 | [`Get-SSHConfig`](INTERFACES.md#get-sshconfig) | `pwsh/Tests/Unit/Ssh.Tests.ps1` | All aliases on a `Host` line receive the block's `HostName`/`User`/`Port`, and a missing config returns nothing. |
| TP-INSTALL-01 | REQ-INSTALL-001, REQ-INSTALL-002 (partial), REQ-INSTALL-003 | `linux/Tests/Install.Tests.sh` | Disposable-home install, idempotent block insertion and replacement, dry-run/check behaviour, Git helper ownership and failure cleanup, uninstall, and command inventory across WSL and native Linux. |
| TP-INSTALL-02 | REQ-INSTALL-001, REQ-INSTALL-002 (partial), REQ-INSTALL-003 (partial) | `pwsh/Tests/Unit/Install.Tests.ps1` | Profile block lifecycle, environment ownership, Espanso copy/upgrade/uninstall, Clink registration and prompt switching, `-Force` backups, dry-run/check, help, and state preserved when modified. |
| TP-ENV-01 | [Environment publication](INTERFACES.md#environment-publication) | `linux/Tests/Environment.Tests.sh` | Both generated files have the expected content, unchanged content is not republished, failed publication leaves the previous files and no temporary data, and shell quoting preserves spaces, quotes, and metacharacters. |
| TP-ENV-02 | [Portable environment variables](INTERFACES.md#portable-environment-variables) | `pwsh/Tests/Unit/PortableEnvironment.Tests.ps1`, `linux/Tests/{Startup,Install}.Tests.sh` | Windows fills only missing values, derives the WSL projects path, diagnoses process-only values, and keeps preexisting or edited values on uninstall. Bash and POSIX login shells export the temp and projects fallbacks, leave `PROJECTS_W` unset without a Windows profile, and preserve overrides. |
| TP-ARCHIVE-01 | REQ-ARCHIVE-003, REQ-ARCHIVE-007 (partial), REQ-ARCHIVE-008 (partial) | `tools/Tests/ArchiveCore.Tests.py` | Gitignore semantics, directory pruning, CRLF/blank lines, tracked-file exclusion, source-only ignore scope, `--no-ignore`, NUL/Unicode names, temporary metadata cleanup, symlink ignore rejection, unreadable ignores, member path validation, Windows name checks, destination guards, and output naming. |
| TP-ARCHIVE-02 | REQ-ARCHIVE-001 (partial), REQ-ARCHIVE-003, REQ-ARCHIVE-004 (partial), REQ-ARCHIVE-007, REQ-ARCHIVE-008 | `linux/Tests/Archive.Tests.sh` | Bash help, naming, default output, `.gitignore` handling, file input, round trip, rejected Windows names, failure cleanup, and the shared Python suite. |
| TP-ARCHIVE-03 | REQ-ARCHIVE-001 (partial), REQ-ARCHIVE-003, REQ-ARCHIVE-004 (partial), REQ-ARCHIVE-007, REQ-ARCHIVE-008 | `pwsh/Tests/Unit/Archive.Tests.ps1` | PowerShell help, approved verbs, timestamped archives, exclusions, ignore rules, round trips, tamper and invalid-format rejection, merge/decline behaviour, rollback, path-escape and link rejection, and protected destinations. |
| TP-ARCHIVE-04 | REQ-ARCHIVE-001 (partial), REQ-ARCHIVE-004 (partial) | `linux/Tests/Archive.Interop.Tests.sh` | Linux and Windows commands round-trip both ways with `age` test doubles and compare selected members. Skips if no Windows PowerShell executable is runnable from WSL. |

## Verification gaps

These are known gaps, not failing checks. Do not assume the listed behaviour
is covered when changing it.

| Requirement or contract | Gap |
| --- | --- |
| REQ-STARTUP-003 | No check asserts output is suppressed in nested, embedded, or explicitly suppressed sessions. |
| REQ-WSL-001 | WSL tests source the platform module directly; they do not assert the native Linux startup guard. |
| [Environment publication](INTERFACES.md#environment-publication) | Startup tests assert file stability but not every partial-publication failure; `TP-ENV-01` covers the publisher directly. |
| REQ-INSTALL-002 | No negative test verifies that setup leaves secrets, SSH data, and CA state untouched, that global Git changes are limited to the Linux installer's credential helper, or that PowerShell startup leaves global Git configuration untouched. |
| [Persistent environment](reference/Install.md#persistent-environment) | Windows tests cover `environment.json` ownership, not legacy `environment.txt` migration. |
| [Espanso discovery](reference/Install.md#what-the-setup-script-does) | Default discovery and the `%APPDATA%\espanso` fallback are not exercised; tests always pass `-EspansoRoot`. |
| [Setup diagnostics](reference/Install.md#what-the-setup-script-does) | Windows tests check for a command-report heading on normal install and no warning at startup, not the complete report across setup modes. |
| REQ-ARCHIVE-004 | The listed scenarios use `age` test doubles, so they do not verify the real archive format or cryptographic authentication. |
| [Archive progress](reference/Protect-Tar.md#progress-reporting) | No check asserts interactive progress or its suppression in non-interactive and redirected sessions. |
| [Archive passphrase handling](reference/Protect-Tar.md#archive-format) | No check asserts passphrases do not appear in arguments, environment, logs, or temporary files. `AGE_FAIL` covers publication only. |
| REQ-MIRROR-001 | OpenSSH permission modes are not asserted. |
| REQ-MIRROR-003 | Only empty `USERPROFILE` is rejected in tests; missing-source, root, identical-path, symlink, hard-link, and non-directory cases are not asserted. |
