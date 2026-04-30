---
id: ir-g4el
status: closed
deps: [ir-o10i]
links: []
created: 2026-04-29T04:41:29Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-9f7z
tags: [workstream, coordinator:coordinator-36f, area:frontend, area:live-fragments]
---
# Extract roster and timesheet feature helpers from shared runtime

Move feature-specific behavior out of the shared app entrypoint.


## Notes

**2026-04-30T02:05:30Z**

Moved roster week overview, roster image export, and roster staff panel sorting into static/app-roster.js; moved timesheet break-time toggle behavior into static/app-timesheets.js. Verified with node --check on feature scripts and bash ./bin/in-env typecheck.
