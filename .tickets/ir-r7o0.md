---
id: ir-r7o0
status: closed
deps: []
links: []
created: 2026-06-21T06:11:04Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Type bootstrap runtime

Remove ts-nocheck from the app bootstrap/page-ready runtime and give its page-ready/timer contracts explicit TypeScript types.

## Design

Add narrow exported types for the page-ready detail and lifecycle timer API. Type Window appPageLifecycle globals in globals.d.ts as needed while preserving classic script behavior.

## Acceptance Criteria

frontend/ts/app-bootstrap.ts no longer uses ts-nocheck; existing page-ready tests still pass; generated static JS is rebuilt; frontend-check passes.


## Notes

**2026-06-21T06:12:53Z**

Removed ts-nocheck from app-bootstrap.ts, added typed page-ready detail handling, HTMX process/window lifecycle globals, and typed tracked timer wrappers. Rebuilt static/app-bootstrap.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
