---
id: ir-v7aj
status: closed
deps: []
links: []
created: 2026-04-29T04:45:32Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-5uzu
tags: [area:live-fragments, source:plans-62]
---
# Fix live-fragment correctness regressions from plan 62

Phase 1 from plans/62-live-fragment-system-refactor.md: fix admin_xero scope handling, timesheet date-move invalidation, slot-name roster config fanout, profile roster fanout, and focused regression coverage.

## Acceptance Criteria

Admin Xero live surfaces match client scope keys; timesheet workedOn moves invalidate old and new mounted day/week sections; slot-name create/update/move/delete broadcasts roster group config; profile roster invalidations cover active affected weeks; focused tests pass.


## Notes

**2026-04-29T04:50:47Z**

Implemented correctness slice: admin_xero JS scope support, slot-name roster config fanout, timesheet date-move invalidation/actor fragments, profile full roster content invalidation. Verified with typecheck, focused Hspec, and live-update adapter E2E.
