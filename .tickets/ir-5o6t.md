---
id: ir-5o6t
status: in_progress
deps: []
links: [ir-y8mj, ir-59gm, ir-nin6]
created: 2026-04-29T04:41:29Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [area:roster, coordinator:coordinator-az6]
---
# Auto-create empty roster weeks and reusable week controls

Repo-local feature migrated from coordinator-az6. Visiting any week should materialize an empty roster week, copy-from-previous should sit beside week navigation, and future week controls should have a reusable home.

## Design

coordinator_ref: coordinator-az6
status: in_progress
source: coordinator standalone feature

## Acceptance Criteria

Any visited week materializes safely, copy-from-previous remains available in the week controls, overwrite behavior is explicit, and controller/e2e coverage proves the flow.


## Notes

**2026-04-30T07:23:08Z**

2026-04-30 reconciliation: any-member missing-week materialization is current behavior and no longer the open gap. Remaining children should focus on copy-overwrite verification and reusable week controls.
