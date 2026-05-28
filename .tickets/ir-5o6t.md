---
id: ir-5o6t
status: closed
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
status: closed
source: coordinator standalone feature
workstream: docs/workstreams/backlog.md

## Acceptance Criteria

Any visited week materializes safely, copy-from-previous remains available in the week controls, overwrite behavior is explicit, and controller/e2e coverage proves the flow.


## Notes

**2026-04-30T07:23:08Z**

2026-04-30 reconciliation: any-member missing-week materialization is current behavior and no longer the open gap. Remaining children should focus on copy-overwrite verification and reusable week controls.

**2026-05-28T08:14:27Z**

2026-05-28 closeout: acceptance confirmed. Missing weeks materialize on visit with existing NavigationSpec coverage; shared week toolbar/navigation controls are present and Copy Previous Week remains in approved Roster settings placement with explicit overwrite confirmation; copy overwrite is covered for existing/live target weeks and roster-group scope; e2e roster live-fragments already proves browser copy from settings into an auto-created week updates another viewer.
