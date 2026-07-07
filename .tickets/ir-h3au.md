---
id: ir-h3au
status: closed
deps: [ir-4dtf]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, verification, frontend-surface]
---
# Verify roster live resync actor invalidation and parity after migration

Run and extend roster verification after the semantic actor-local invalidation migration.

## Design

Exercise actor-local invalidation, duplicate mounts, passive invalidations, websocket echo suppression, reconnect/resync defaults, direct vs projection backend rendering, manager/staff visibility, interaction conflicts, and mobile horizontal behavior.

## Acceptance Criteria

Relevant roster Hspec suites and E2E pass. New coverage proves actor-local duplicate-mount refresh and passive websocket behavior. No stale roster successful actor business-OOB helper path remains except documented intentional non-migrated/validation/extras cases.

## Notes

**2026-07-07T05:17:35Z**

Roster verification complete for migrated actor-local invalidation flow. Full RosterWeeksController Hspec suite passes after migration (103 examples). Actor responses now assert HX-Reswap none and HX-Trigger semantic fragments instead of business OOB HTML; fragment GETs are used in tests to verify authoritative rendered content for content/grid/wage/layout paths. Removed the stale unused respondWithRosterPatches/respondWithRosterRows business-OOB helper path from RosterWeeksController. Remaining OOB in roster migration scope is limited to extras/confirmation or legacy Staff controller use of respondWithRosterContentOob outside this roster actor success path. Verification: hspec-test --match 'RosterWeeksController'.
