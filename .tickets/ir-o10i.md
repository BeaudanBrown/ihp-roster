---
id: ir-o10i
status: closed
deps: []
links: []
created: 2026-04-29T04:41:29Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9f7z
tags: [workstream, coordinator:coordinator-36f, area:frontend, area:live-fragments]
---
# Extract the app JS bootstrap into smaller runtime files

Split global bootstrap and lifecycle wiring into focused static files while preserving app:page-ready.


## Notes

**2026-04-30T02:05:30Z**

Split static/app.js into focused runtime files for dialog overlays, toasts, quarter-hour time picker, roster behavior, and timesheet behavior. Layout now loads each file explicitly and keeps static/app.js as a compatibility endpoint. Verified with node --check on the split files and bash ./bin/in-env typecheck.
