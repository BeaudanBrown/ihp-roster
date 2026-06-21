---
id: ir-5rck
status: closed
deps: []
links: []
created: 2026-06-21T06:14:31Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Split and type time picker runtime

Extract pure time-picker option helpers into a feature module and remove ts-nocheck from the app time-picker entrypoint.

## Design

Move tested parse/label/option functions to frontend/ts/time-picker/options.ts. Keep app-time-picker.ts as DOM wiring plus typed imports, using narrow DOM and Bootstrap modal shapes.

## Acceptance Criteria

app-time-picker.ts no longer uses ts-nocheck; tests import pure helpers from the feature module; generated JS is rebuilt; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:17:09Z**

Extracted pure time option parsing/label/build helpers to frontend/ts/time-picker/options.ts and updated tests to import the feature module. Removed ts-nocheck from app-time-picker.ts, added typed DOM wiring and Bootstrap modal/HTMX trigger globals, and rebuilt static/app-time-picker.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
