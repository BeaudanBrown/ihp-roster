---
id: ir-59gm
status: closed
deps: []
links: [ir-y8mj, ir-5o6t, ir-nin6]
created: 2026-04-29T04:41:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-5o6t
tags: [area:roster, coordinator:coordinator-az6]
---
# Materialize empty roster weeks on visit

Create missing roster weeks instead of rendering a no-roster empty state.


## Notes

**2026-04-30T06:32:06Z**

2026-04-30 audit note: ShowRosterWeekAction currently calls ensureRosterWeekExists and NavigationSpec covers missing-week materialization for staff. Verify remaining gaps are copy/overwrite/e2e/reusable controls rather than basic materialization, then update/close this child.

**2026-04-30T07:23:02Z**

2026-04-30 reconciliation: current ShowRosterWeekAction materializes missing roster weeks, and Test/Controller/RosterWeeks/NavigationSpec covers worker/staff materialization. Closing this child; remaining auto-create lane work lives in ir-y8mj for copy-overwrite/e2e verification and ir-w8dk for reusable controls.
