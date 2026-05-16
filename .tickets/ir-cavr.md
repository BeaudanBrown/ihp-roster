---
id: ir-cavr
status: closed
deps: [ir-mxsn]
links: []
created: 2026-05-16T03:27:18Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-y166
tags: [area:live-fragments, area:docs, area:tests]
---
# Update live runtime docs and guards after simplification

Reconcile docs, guard tests, and final verification after internal live runtime simplification.

## Design

Update Application/Helper/LiveUpdate.SPEC.md, Web/Controller/AGENTS.md, Web/View/AGENTS.md, static/AGENTS.md, and the workstream doc. Tighten LiveSurfaceGuard for the new internal names and deleted compatibility layer.

## Acceptance Criteria

Docs describe the simplified runtime accurately, guard tests enforce the new boundary, and final checks pass: typecheck, hspec LiveUpdate, hspec Surface, and live-update Playwright suites.


## Notes

**2026-05-16T03:47:32Z**

Docs and guard updated for the simplified runtime. Final checks passed: typecheck, LiveUpdate/Surface/TimesheetsController/SupportController/live scope hspec matches, plus both live-update Playwright specs.
