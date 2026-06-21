---
id: ir-gx55
status: closed
deps: []
links: []
created: 2026-06-21T06:08:25Z
type: task
priority: 2
assignee: beaudan
parent: ir-bmc0
tags: [agent-loop, frontend, typescript, refactor]
---
# Add shared frontend DOM and lifecycle helpers

Create shared frontend DOM and lifecycle helper modules and migrate a few low-risk runtimes to use them as the first frontend TypeScript refactor slice.

## Design

Add frontend/ts/shared/dom.ts with typed element guards/query helpers and frontend/ts/shared/lifecycle.ts with app page/HTMX detail-target helpers. Adopt them in small already-typed runtimes rather than touching large ts-nocheck files first.

## Acceptance Criteria

Shared helper modules are covered by frontend unit tests or exercised through existing tests; app-toggle-buttons, app-timesheets, and app-preferences use the shared lifecycle/detail-target helpers where applicable; generated JS is rebuilt with no drift; frontend-check passes.


## Notes

**2026-06-21T06:10:55Z**

Added shared DOM and lifecycle helper modules, with tests for detail target/root extraction and browserless DOM guards. Migrated app-toggle-buttons, app-timesheets, and app-preferences to use shared page-ready/HTMX detail helpers. Regenerated generated static JS. Verified frontend-check, doc-drift-check, and LSP diagnostics.
