---
id: ir-0rbq
status: closed
deps: []
links: []
created: 2026-06-21T06:33:12Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Type live-update runtime

Remove ts-nocheck from app-live-updates.ts after protocol and surface validation extraction.

## Design

Add local runtime types for subscriptions, deferred fragments, performance spans, websocket state, HTMX config events, and fragment protection policies. Reuse generated contracts plus protocol/validation helpers. Avoid semantic changes.

## Acceptance Criteria

app-live-updates.ts no longer uses ts-nocheck; generated static JS is rebuilt; frontend-check and doc-drift-check pass; LSP diagnostics are clean.


## Notes

**2026-06-21T06:39:09Z**

Removed ts-nocheck from app-live-updates.ts. Added local types for subscriptions, deferred fragments, performance spans, websocket state, protection adapters, HTMX config request events, and generated live-update message variants. Rebuilt static/app-live-updates.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
