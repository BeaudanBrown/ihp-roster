---
id: ir-d4lr
status: closed
deps: [ir-fxl6]
links: []
created: 2026-04-29T04:41:30Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-2usx
tags: [area:view, area:maintenance, source:plans-61]
---
# Move Timesheets and StaffDialogs helpers

Extract modal/form/dialog helpers while preserving field names and mount targets.


## Notes

**2026-04-30T02:02:09Z**

Moved timesheet form/dialog helpers into Application.Helper.View.Timesheets and staff edit dialog wrappers into Application.Helper.View.StaffDialogs. Application.Helper.View is now a re-export-only compatibility wrapper. Verified with bash ./bin/in-env typecheck.
