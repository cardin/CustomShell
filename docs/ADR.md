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
