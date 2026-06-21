---
id: ir-rt8t
status: closed
deps: []
links: []
created: 2026-06-21T06:30:36Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Extract live-update protocol helpers

Move tested live-update pure protocol helpers out of the app entrypoint as a safe first split before typing the runtime.

## Design

Create frontend/ts/live-updates/protocol.ts for helper functions that depend only on generated contracts. Update unit tests to import this module. Keep app-live-updates.ts runtime semantics unchanged and still ts-nocheck in this slice.

## Acceptance Criteria

Protocol helper tests import from live-updates/protocol.ts; generated JS is rebuilt if needed; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:31:40Z**

Extracted live-update pure protocol helpers to frontend/ts/live-updates/protocol.ts and updated live-update unit tests to import that module. app-live-updates.ts now imports the helpers but remains ts-nocheck for a later runtime typing slice. Rebuilt static/app-live-updates.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
