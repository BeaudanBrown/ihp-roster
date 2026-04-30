---
id: ir-7t6a
status: closed
deps: [ir-o10i, ir-5uzu, ir-g4el]
links: []
created: 2026-04-29T04:41:29Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-9f7z
tags: [workstream, coordinator:coordinator-36f, area:frontend, area:live-fragments]
---
# Verify the JS runtime refactor across lifecycle and interactive flows

Run targeted browser/controller checks covering lifecycle, HTMX swaps, live updates, pickers, and overlays.


## Notes

**2026-04-30T02:07:26Z**

Verified the runtime split with node --check for static/app-dialog-overlays.js, static/app-toasts.js, static/app-time-picker.js, static/app-roster.js, static/app-timesheets.js, and static/app.js; bash ./bin/in-env typecheck; bash ./bin/in-env hspec-test --match "LiveUpdate" --match "TimesheetsController"; and bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts e2e/live-fragment-submit-regressions.spec.ts e2e/roster-live-fragments.spec.ts --reporter=line (21 passed).
