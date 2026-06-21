---
id: ir-f2bm
status: closed
deps: []
links: []
created: 2026-06-21T06:39:24Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Extract roster helper modules

Move tested roster helper functions out of the app roster entrypoint before typing the full roster runtime.

## Design

Create frontend/ts/roster/overview.ts, staff-sort.ts, and fullscreen.ts for existing tested helpers. Update app-roster.ts to import/re-export helpers and update tests to import feature modules. Keep app-roster.ts ts-nocheck in this slice.

## Acceptance Criteria

Roster helper tests import feature modules; app-roster.ts runtime behavior is unchanged; generated JS is rebuilt if needed; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:40:28Z**

Extracted tested roster helpers into frontend/ts/roster/overview.ts, fullscreen.ts, and staff-sort.ts. app-roster.ts now imports/re-exports the helpers but remains ts-nocheck for the later full runtime typing slice. Updated roster tests to import feature modules and rebuilt static/app-roster.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
