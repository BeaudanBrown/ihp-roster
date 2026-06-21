---
id: ir-t1d5
status: open
deps: [ir-j3hy, ir-9ra7, ir-jxjp]
links: []
created: 2026-06-21T03:37:16Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-l5gk
tags: [agent-loop, frontend, typescript, conversion]
---
# Convert low-risk app scripts to TypeScript

Convert low-risk app-owned runtime scripts to TypeScript after the pipeline and docs are in place.

## Design

Convert app.js, app-scrollbars.js, app-xero.js, app-date-pickers.js, app-toasts.js, app-toggle-buttons.js, app-timesheets.js, and app-preferences.js to matching frontend/ts/*.ts sources. Preserve generated static output names and existing script order. Add or extend unit/DOM tests for testable behavior in each converted script, and run focused Playwright coverage where the behavior depends on browser/server integration.

## Acceptance Criteria

Each low-risk script has matching frontend/ts/*.ts source. Generated JS matches frontend-build. frontend-check passes, including unit/DOM tests added for converted behavior. Existing relevant UI behavior still works and basic syntax/runtime checks pass, with focused Playwright checks run where appropriate.

