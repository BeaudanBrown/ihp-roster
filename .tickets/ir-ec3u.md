---
id: ir-ec3u
status: closed
deps: []
links: []
created: 2026-06-21T06:13:25Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Type dialog overlay runtime

Remove ts-nocheck from the dialog overlay runtime while preserving HTMX/Bootstrap dialog behavior.

## Design

Add narrow DOM/event types, reuse shared lifecycle/detail helpers where useful, and avoid changing runtime semantics. Keep exported dialogSubmitLoadingHtml test contract.

## Acceptance Criteria

frontend/ts/app-dialog-overlays.ts no longer uses ts-nocheck; generated static JS is rebuilt; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:14:23Z**

Removed ts-nocheck from app-dialog-overlays.ts, added explicit string/event/DOM types, reused shared DOM and lifecycle detail helpers, and preserved submit loading HTML export. Rebuilt static/app-dialog-overlays.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
