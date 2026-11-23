# Architecture decision records

An ADR records a significant decision that was accepted, with its context and
consequences. Write it when the decision is accepted, not at merge time. Do not
rewrite an accepted ADR to match later code: add a new ADR and mark the old one
`Superseded by ADR-NNNN`. Preserve accepted history.

Not every architectural fact qualifies. Write an ADR when the decision involves
a non-obvious trade-off, is costly to reverse, or constrains multiple components
or a compatibility surface. If the tree already shows it, or a requirement
already states it, leave it in the design or requirement instead.

Format: `ADR-NNNN`, four digits. Numbers are stable once the record is referenced
or merged; rejected drafts are removed before that. Status is `Accepted`,
`Superseded by ADR-NNNN`, `Deprecated`, or `Rejected`.

## Index

| ID | Title | Status |
| --- | --- | --- |
| ADR-0001 | Installer-owned environment values, runtime publication | Accepted |
| ADR-0002 | Use native names for portable environment variables | Accepted |
| ADR-0003 | Non-interactive Bash environment through BASH_ENV | Accepted |

## ADR-0001: Installer-owned environment values, runtime publication

- **Status:** Accepted
- **Date:** 2026-11-12 (recorded; the practice predates this record)

**Context.** Some values must survive across sessions and reach processes that
never source the interactive shell. Profile blocks alone do not cover
`systemd --user`, graphical applications, or POSIX login shells.

**Decision.** Setup owns the persistent values and records what it set. Runtime
startup publishes the Linux values to
`~/.config/environment.d/90-customshell.conf` and
`~/.config/customshell/env.sh`. Setup never writes those generated files
directly. Uninstall removes only values and files it still owns.

**Consequences.** Setup and startup have separate responsibilities that must
not blur. Modified values and files are reported and kept rather than
overwritten. A running process keeps its old environment until it restarts.

## ADR-0002: Use native names for portable environment variables

- **Status:** Accepted
- **Date:** 2026-11-22

Use the native Linux names rather than CustomShell-specific aliases so scripts
can use the same names on Windows and WSL. Persist missing Windows values at
setup so they reach processes that do not load PowerShell. Existing values
take precedence over defaults, and WSL keeps its own user and home.
See [portable environment variables](INTERFACES.md#portable-environment-variables).

## ADR-0003: Non-interactive Bash environment through BASH_ENV

- **Status:** Accepted
- **Date:** 2026-11-23

**Context.** Non-interactive Bash (`bash -c`, script runners, agent shells)
reads no profile. The managed `.bashrc` block is skipped because the stock
Debian guard returns for non-interactive shells, and `~/.profile` is read only
by login shells. Those processes therefore missed `~/.local/bin` and the
portable defaults even though the values were configured.

**Decision.** Both managed blocks export `BASH_ENV` to
`linux/noninteractive.sh` when it is empty. That entry point composes only
`core/paths.sh` and `core/portable-env.sh`; it never sources `linux/main.sh`.
A nonempty `BASH_ENV` is preserved so another tool's setting wins.

**Consequences.** Children of a managed shell receive the paths and defaults,
including tools that spawn Bash themselves. The entry point must stay silent and
free of interactive setup, because it runs for every non-interactive Bash. The
contract stops at inherited environments: processes launched without a profile,
such as a Windows to WSL interoperability process, or started before setup, are
unaffected and keep their own environment. Moving the repository requires a
reinstall so the exported path follows it.
See [non-interactive shells](INTERFACES.md#non-interactive-shells).
