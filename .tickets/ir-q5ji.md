---
id: ir-q5ji
status: open
deps: []
links: []
created: 2026-07-08T04:59:57Z
type: chore
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, roster, cleanup]
---
# Retire RosterGlobalContract

Remove the temporary RosterGlobalContract root by moving RosterStaffSortKey to a modern contract home.

## Design

Inspect RosterStaffSortKey consumers before choosing the final home. Prefer RosterSurface if it is only roster-surface vocabulary; otherwise use a more appropriate app/interaction contract. Remove RosterGlobalContract from RegisteredFrontendContracts.

## Acceptance Criteria

No temporary roster global root remains; no stale temporary global contract comment remains; contract tests/frontend checks pass.

