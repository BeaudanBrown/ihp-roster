---
id: ir-cfcr
status: open
deps: []
links: []
created: 2026-05-29T03:16:06Z
type: epic
priority: 2
assignee: beaudan
tags: [agent-loop, live-fragments, htmx, oob]
---
# Unify fragment swap and live update system app-wide

Migrate the app toward one typed fragment model where actor HTMX/OOB updates, passive live invalidations, and resyncs reuse the same fragment identities, target ids, renderers, dependency contracts, and containment metadata. Timesheets is the reference implementation; migrate remaining areas without keeping obsolete compatibility paths.

## Design

Reference pattern: fragments are stable DOM ownership units; successful actor responses return the same fragments as OOB swaps; fragment GET endpoints return plain target nodes; validation failures may remain direct form/dialog responses; scroll/focus owners should not be swapped unless intentional; use containment normalization for parent/child overlaps.

## Acceptance Criteria

Each phase epic is closed; no targeted area has duplicate actor-only/live-only fragment render paths; relevant Hspec and Playwright coverage passes; docs/guardrails describe the unified pattern.


## Notes

**2026-05-29T03:16:12Z**

Planning context: timesheets was already refactored in commits 6acdd86, f783b51, c060acc and should be treated as the reference implementation, not as remaining scope except for extracting shared helper usage.
