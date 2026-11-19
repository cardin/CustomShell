# AGENTS.md

Maintain CustomShell as defined in `docs/`. Read the relevant records before
changing behavior. This file contains contribution guidance and the change
workflow; it is not a second specification.

# Living Design and Change Workflow

## Authority

Records are layered; link rather than duplicate structure across them.

- `docs/` is canonical at all times, including while a feature is in flight. It
  holds requirements, design, contracts, verification strategy, and decisions.
- Feature specs (`specs/<feature>/`, SpecKit or equivalent) are change-local
  working records: a proposal against the current docs, never a second
  contract. Restating living-doc content for working context is permitted;
  where the two disagree, the living doc wins, and the disagreement is a
  finding for human review, not resolved silently.
- No tracker is selected in the root `README.md`. Tracking is optional; if one
  is selected later, it records scope, priorities, ownership, dependencies,
  blockers, and delivery status, but is context, not a substitute for approved
  requirements.
- Git, pull/merge request, test/CI, and deployment records are implementation,
  verification, and release evidence. The pull/merge request description is the
  change record: summary, affected requirement IDs, ADR links, test evidence,
  known gaps, and the spec disposition manifest. It must stand alone, because
  the spec is deleted after reconciliation.

## Documents

| Document | Owns |
| --- | --- |
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | Essential outcomes and safeguards. Substantive changes require explicit human approval. |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Diagrams, flows, dependencies, and boundaries. |
| [`docs/INTERFACES.md`](docs/INTERFACES.md) | Command, configuration, environment, and state-file contracts. |
| [`docs/TESTPLAN.md`](docs/TESTPLAN.md) | Verification scenarios, requirement-to-check mapping, and coverage gaps. |
| [`docs/ADR.md`](docs/ADR.md) | Significant decisions and rationale; preserve accepted history by superseding, not editing. |
| [`docs/reference/`](docs/reference/README.md) | Detailed command contracts for installation, archives, and the WSL SSH mirror. |

Create documents as needed. Split large files into matching directories with
`README.md` entry points. Preserve active requirement IDs; never renumber or
reuse removed IDs. Remove withdrawn requirements from living docs and record
their disposition in the change record, not a retirement registry. Limit each
requirement section to five entries. Use MIL-STD-498 as a reference, not a
constitution.

Above all, be concise with documentation.

### Provisional markers

Partial reconciliation leaves explicitly marked provisional content. This is
the only allowed form, defined here so any agent, script, or reviewer can find
it without having seen the feature:

> Provisional — feature `checkout-guest`: <what is not final>.
> See `specs/checkout-guest/spec.md`.
<!-- provisional:feature=checkout-guest -->

Rules:

- `feature=` is the spec folder name. One marker per merged section.
- Never invent a variant wording. Never touch another feature's markers.
- `complete` finalizes them (keep content, remove marker). `abandoned`
  retracts them (remove content and marker).
- Find all markers for a feature with:
  `rg "provisional:feature=checkout-guest"`

## Change workflow

For material changes:

1. Read the root README, relevant documents, current plan, implementation, and
   tests; consult linked work items when tracking is used.
2. Plan a bounded increment, identifying affected contracts, documentation,
   verification, and open decisions.
3. Implement and test incrementally; coordinate shared interface changes with
   affected contributors. Routine engineering decisions need not await the
   lead.
4. Record decisions and approvals when they happen. Accepted significant
   decisions get an ADR at acceptance. Approved intent changes update living
   docs before the affected implementation proceeds. Interface or public
   behavior changes that other work depends on are merged via
   `living-docs-reconcile` in `partial` mode, without waiting for completion.
   Resolve conflicts with owners rather than rewriting intent to match code.
5. Before opening the pull/merge request that ends a feature, run
   `living-docs-reconcile` with the outcome matching the feature's state. Do not
   open the request until its disposition manifest is complete and reviewed.
6. Update affected documents and tests with the code via that reconciliation.
   Before handoff, reconcile upstream changes and authoritative records, link
   evidence, and report remaining gaps. Apply the team's acceptance criteria
   before advancing delivery status.

## Change guidance

- Inspect the full sourcing chain before editing startup behavior; sourced
  files share state and depend on load order.
- Guard optional integrations and preserve the terminal/tmux gates around
  startup output.
- Keep platform code under `pwsh/` or `linux/`, shared tool configuration under
  `config/`, and cross-platform helper code used by both platforms under
  `tools/`.
- Do not add user-specific data or rename public interfaces without documenting
  the compatibility impact.
- Preserve OS-native line endings: CRLF for Windows scripts and LF for Unix
  scripts.

Archive, SSH mirroring, CA, Git credential, and `environment.d` changes are high
risk. Cover their success, failure, and cleanup paths with isolated tests; never
use real credentials or network services.

## Tracker

Tracking is optional unless selected in README. Record work requiring shared
visibility or independent ownership, not every execution step.

Routine progress, blocker, and PR-link updates to existing assigned issues are
allowed. Obtain approval to create issues or change scope, priority, ownership,
or closure. Preserve existing references; reconcile stale plans before updating
records. Before a feature spec is deleted, retarget any tracker links pointing
at it to the MR and ADR instead. Report pending updates when access or approval
is missing.

## SpecKit

SpecKit is optional; none is configured today. Its native plan and tasks may
serve as the feature spec. Feature specifications are scoped change proposals,
not competing system contracts or backlogs. Spec content may duplicate
living-doc sections for working context; living docs remain authoritative, and
the spec is deleted after reconciliation, which bounds the duplication.

Keep its constitution aligned with this workflow. Refresh active artifacts
against relevant living-document changes before resuming work; completed
artifacts are handled by `living-docs-reconcile`, not retained by default.
Review living-document consistency explicitly, beyond SpecKit's own analysis.

## living-docs-reconcile

The skill records how every part of a feature spec is dispositioned into the
authoritative records, merges the durable content, and deletes the spec when
the feature is complete. Three outcomes:

- `complete`: acceptance criteria verified, tests green, no open decisions.
  Merges content, promotes unrecorded decisions to ADRs, finalizes this
  feature's provisional markers, then deletes the spec in a separate commit
  after the docs merge is approved.
- `partial`: implementation incomplete but interface, requirement, or decision
  content is needed now. Merges only approved, stable content using the
  provisional markers above, and keeps the spec. Re-running updates in place.
- `abandoned`: work stopped, superseded, deferred, or reverted. Writes a short
  ADR with revisit conditions, retracts this feature's provisional markers,
  updates the tracker, and archives the spec rather than deleting it.

If the outcome is ambiguous, use `partial`. Deletion requires the positive
`complete` gate; it is never the fallback. Run the skill for every ending, not
only successful ones.

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
bash linux/Tests/Archive.Interop.Tests.sh
bash linux/Tests/Environment.Tests.sh
bash linux/Tests/Install.Tests.sh
bash linux/Tests/Startup.Tests.sh
bash linux/Tests/Wsl.Tests.sh
```

The shared archive core under `tools/` is covered by
`tools/Tests/ArchiveCore.Tests.py`, which `linux/Tests/Archive.Tests.sh` runs.

Report a missing `shellcheck`. Do not source `linux/main.sh` in the user's
normal shell during testing; use a disposable process and temporary `HOME`.
Use the owning tool to validate changed files under `config/` when available.

## Completion

- Update `README.md` for installation, prerequisites, or user-facing commands.
- Update `docs/` when behavior, compatibility, supported environments, known
  gaps, contracts, or decisions change. Keep requirement IDs stable and update
  the test mapping when verification changes.
- Report files changed, checks run or skipped, and compatibility impact.
