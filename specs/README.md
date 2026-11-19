# Feature specifications

This directory holds change-local working records. A feature specification is a
bounded proposal against the canonical documents in [`docs/`](../docs/), never a
second contract. If a spec and a living document disagree, the living document
wins and the disagreement is a review finding, not something resolved silently.

No feature specification is currently active.

## Naming

Use one directory per feature: `specs/<feature>/`, with a kebab-case name that
matches the branch or work item where one exists. SpecKit or an equivalent tool
may supply the plan and tasks; they are optional.

## Lifecycle

A spec is deleted when the feature completes, after
`living-docs-reconcile` has dispositioned its content into `docs/`. Provisional
content merged before completion stays marked:

> Provisional — feature `<feature>`: <what is not final>.
> See `specs/<feature>/spec.md`.
<!-- provisional:feature=<feature> -->

Find a feature's markers with:

```bash
rg "provisional:feature=<feature>"
```

`complete` finalizes the markers (keep the content, remove the marker).
`abandoned` retracts them (remove the content and the marker) and archives the
spec. `partial` keeps the spec and updates markers in place.

The MR description carries the disposition manifest, so it stands alone after
the spec is deleted. Do not retarget or delete tracker links until that manifest
is complete. No tracker is selected in the root README; tracking stays optional.
