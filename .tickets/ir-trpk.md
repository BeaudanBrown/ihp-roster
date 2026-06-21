---
id: ir-trpk
status: closed
deps: []
links: []
created: 2026-06-21T06:31:59Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Add live-update surface config validation

Add a small runtime validator for declarative live-update surface configs before typing the full runtime.

## Design

Create frontend/ts/live-updates/validation.ts with narrow record/string/array guards and a parser for data-live-update-surface JSON. Adopt it in app-live-updates.ts readDeclarativeSurface without changing behavior for valid configs.

## Acceptance Criteria

Invalid or malformed declarative surface JSON is rejected before use; validator has frontend unit coverage; generated JS is rebuilt; frontend-check and doc-drift-check pass.


## Notes

**2026-06-21T06:33:01Z**

Added frontend/ts/live-updates/validation.ts with narrow runtime guards for declarative live-update surface configs, adopted it in readDeclarativeSurface, and added unit coverage for accepted configs and rejection of missing scope/scopeKey. Rebuilt static/app-live-updates.js. Verified frontend-check, doc-drift-check, and LSP diagnostics.
