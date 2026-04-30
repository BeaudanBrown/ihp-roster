---
id: ir-59gm
status: open
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
