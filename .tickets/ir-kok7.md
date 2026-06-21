---
id: ir-kok7
status: closed
deps: []
links: []
created: 2026-06-21T06:17:51Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Split and type horizontal scroll runtime

Extract horizontal-scroll math helpers and remove ts-nocheck from the horizontal scroll runtime.

## Design

Move tested parse/clamp helpers to frontend/ts/horizontal-scroll/math.ts, add explicit snap/drag state types in app-horizontal-scroll.ts, and preserve data-attribute driven scroll behavior.

## Acceptance Criteria

app-horizontal-scroll.ts no longer uses ts-nocheck; tests import math helpers from feature module; generated JS is rebuilt; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:19:51Z**

Extracted horizontal scroll parse/clamp helpers to frontend/ts/horizontal-scroll/math.ts and updated tests to import that feature module. Removed ts-nocheck from app-horizontal-scroll.ts with explicit snap/drag state, event, map, and DOM types while preserving runtime behavior. Rebuilt static/app-horizontal-scroll.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
