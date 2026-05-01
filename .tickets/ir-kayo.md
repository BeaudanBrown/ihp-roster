---
id: ir-kayo
status: closed
deps: [ir-9sqg]
links: []
created: 2026-04-29T04:41:29Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-sryt
tags: [area:performance, area:profiling, coordinator:coordinator-b64]
---
# Instrument roster, timesheet, leave, and live-update hot paths

Add targeted spans where performance questions recur.

## Notes

**2026-04-30T23:58:52Z**

Existing roster/timesheet/leave/live-update hot-path spans verified during profiling refactor; live-update spans now include fanout detail.
