---
id: ir-q5ji
status: closed
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


## Notes

**2026-07-08T05:39:05Z**

Retired the temporary RosterGlobalContract root. Moved the RosterStaffSortKey schema into AppContract as shared browser vocabulary used by the roster staff-panel client runtime, updated Haskell value accessors/tests to resolve through AppContract, removed RosterGlobalContract from RegisteredFrontendContracts, deleted Application/Helper/FrontendContract/Roster.hs, and removed stale guard allowlist entries. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-check; bash ./bin/in-env hspec-test --match "Frontend contract" --match "SurfaceGuard".
