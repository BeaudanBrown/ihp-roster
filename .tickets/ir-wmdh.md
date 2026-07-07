---
id: ir-wmdh
status: closed
deps: [ir-rfyw]
links: []
created: 2026-07-07T04:09:19Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-cfcr
tags: [agent-loop, timesheets, live-fragments, frontend-surface]
---
# Migrate Timesheets successful mutations to actor-local invalidation

Replace Timesheets successful business OOB actor responses with actor-local semantic invalidation plus extras.

## Design

Create/update/delete/approve/unapprove success paths should commit through existing mutations/touched resources, emit passive invalidation, and return dialog/toast extras plus actor-local invalidation. Date moves invalidate both affected day sections. Fragment GET endpoints continue returning plain target-node HTML. Validation failures keep direct dialog rerenders.

## Acceptance Criteria

Timesheets success responses contain no authoritative business hx-swap-oob fragments. Actor-local invalidation refreshes affected mounted day/toolbar/columns fragments as planned, including duplicate mounts. Dialog close/toast extras remain. Focused Timesheets Hspec/frontend checks pass.


## Notes

**2026-07-07T04:38:41Z**

Migrated Timesheets mutation success responses to actor-local invalidation. Create/update/delete/approve/unapprove day-section paths now emit setActorLiveFragmentsRefresh for selected Timesheets mounted fragments plus dialog/toast extras; date moves select both visible day sections. HTMX week navigation still returns toolbar/day-columns OOB because it is pure view-state navigation, not a successful mutation. Fragment GETs remain plain target-node HTML. Verification: bash ./bin/in-env hspec-test --match 'TimesheetsController'.
