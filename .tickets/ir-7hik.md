---
id: ir-7hik
status: closed
deps: [ir-re0y, ir-wk3e]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, roster, split]
---
# Pure-split roster.css into focused roster feature modules

Decompose static/css/features/roster.css into a roster directory of concern-specific stylesheets while preserving behavior and cascade order.

## Design

Create static/css/features/roster/ modules, initially as a pure move of existing rules with comments and no selector rewrites except file headers. Suggested files: toolbar.css (export button, assignment filters, week nav arrow, wage summary, layout mode group), week-overview.css (.roster-week-overview*), staff-panel.css (.roster-layout-side, .roster-staff-*, .roster-quick-tool-*), grid-frame.css (.roster-grid-frame, rails, scroller, grid header sizing), grid-cells.css (day rows, slot cell base styles), day-actions.css (add/remove/closed controls shared by rail and day-column layout), day-columns.css (.roster-day-columns/.roster-day-column*), shift-card.css (.roster-shift-card* and badges), states.css (conflicts, staff highlight, required/empty/publish-required, shift colour state selectors), export-print.css (export stage/surface and @media print). Keep the order in Web/View/Layout.hs equivalent to the old roster.css order by linking modules in that sequence. Replace the old static/css/features/roster.css link with the module links; either remove the old file or leave a one-line compatibility comment only if not linked. Mirror every linked stylesheet in Makefile CSS_FILES. Update e2e/styling-regression.spec.ts so it asserts the new roster module links rather than only /css/features/roster.css.

## Acceptance Criteria

No semantic CSS or HSX changes are included beyond stylesheet link updates and test path expectations. static/css/features/roster.css is no longer the 2000+ line linked source. All new roster module links are present in Web/View/Layout.hs and Makefile CSS_FILES in cascade-preserving order. bash ./bin/in-env ./bin/style-audit passes hard checks. Focused checks pass: bash ./bin/in-env e2e e2e/styling-regression.spec.ts and bash ./bin/in-env e2e e2e/roster-mobile.spec.ts. If e2e is too expensive in the agent context, record the attempted command/output as a ticket note.


## Notes

**2026-05-29T01:21:09Z**

Pure-split static/css/features/roster.css into linked roster modules; verified nonblank CSS content matches the previous roster.css when modules are concatenated in Layout/Makefile order. Verification: bash ./bin/in-env ./bin/style-audit passed; bash ./bin/in-env ./bin/css-inventory passed with no CSS files over budget; bash ./bin/in-env e2e e2e/roster-mobile.spec.ts passed (27/27). Attempted bash ./bin/in-env e2e e2e/styling-regression.spec.ts; it failed 5 existing styling assertions unrelated to the pure split after the new stylesheet link assertions passed enough to reach metrics (desktop header expected flex but current app-week-toolbar is grid, profile accordion metrics null/collapsed, shift preference row hidden, leave dialog link not present, phone roster metrics null). Artifacts: .devenv/e2e/1780017317-691724-8205.
