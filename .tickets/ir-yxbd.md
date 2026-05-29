---
id: ir-yxbd
status: closed
deps: []
links: [ir-cqg3]
created: 2026-05-29T02:31:33Z
type: chore
priority: 2
assignee: beaudan
tags: [css, cleanup, agent-loop]
---
# Final dead CSS cleanup pass

Audit app-owned CSS after the CSS architecture overhaul and remove selectors/files that are demonstrably dead and safe to delete.

## Design

Use style-audit/css-inventory plus targeted code searches. Preserve feature classes, JS/test hooks, and Bootstrap overrides that are still used or intentionally broad. Keep changes scoped to dead CSS removal and docs/ticket notes.

## Acceptance Criteria

Dead CSS candidates are either removed with verification or recorded as still used/unsafe. style-audit, css-inventory, typecheck, and focused styling/mobile e2e checks are run or noted.


## Notes

**2026-05-29T02:46:08Z**

Dead CSS pass complete. Removed comment-only/empty runtime stylesheet shims static/app.css, static/css/components.css, static/css/features/roster.css, and static/css/features/exports.css; removed their Layout.hs/Makefile links and stale styling-regression expectations. Removed unused Bootstrap/card/breadcrumb/nav-tabs overrides, unused .app-surface-muted helper, unused .conflict-advisory roster conflict styling and --roster-warning token, and stale .form-check/.form-check-label rules under roster assignment filters. Tightened style-audit's unlinked CSS allowlist to empty so future comment-only app CSS files are not silently retained. Remaining css-inventory stale candidates are intentional dynamic/runtime classes: app-week-toolbar-roster/app-week-toolbar-timesheets from Application.Helper.View.WeekToolbar and htmx-request from htmx. Final app-owned CSS inventory: 4,097 lines across 37 files, down 65 lines and 4 files from the previous closeout count of 4,162 across 41 files. Verification: bash ./bin/in-env ./bin/style-audit passed; bash ./bin/in-env ./bin/css-inventory passed; bash ./bin/in-env typecheck passed; LSP clean for styling-regression and only the existing roster-row-controls implicit-any hint remains; bash ./bin/in-env e2e e2e/styling-regression.spec.ts e2e/roster-row-controls.spec.ts passed (12/12).
