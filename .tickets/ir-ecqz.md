---
id: ir-ecqz
status: closed
deps: [ir-fnfn, ir-f5mw]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, components, roster, forms]
---
# Extract shared dense control and action-button styling from roster CSS

Reduce duplicated dense input/select/static-cell/action-button styling by introducing shared primitives used by roster grid/cards and available to future dense surfaces.

## Design

Inventory repeated dense-control declarations in roster grid cells and roster shift cards: transparent select/input resets, centered ellipsis text, tabular time values, focus/hover behavior, static-cell display, square/compact icon buttons. Add narrowly named shared classes in components/forms.css or components/buttons.css, e.g. .app-dense-control, .app-dense-select-plain, .app-dense-static, .app-icon-button, or similar names chosen during implementation. Update roster HSX helpers in Web/View/RosterWeeks/Grid.hs to add the shared classes while keeping feature-specific classes for JS/tests. Move only generic declarations; leave roster sizing, row height, conflict, palette, and publish-required behavior in roster modules. Avoid large semantic rewrites in the same commit.

## Acceptance Criteria

Roster dense controls still behave and autosave as before. Shared dense-control/action-button classes are documented in static/css/README.md. Roster feature CSS loses duplicated generic declarations but keeps feature-specific state/sizing. No new inline styles are introduced. Focused typecheck and roster e2e/style checks pass or are attempted and noted.


## Notes

**2026-05-29T01:59:39Z**

Extracted shared dense control/static/time-value primitives in components/forms.css and shared compact/icon button primitives in components/buttons.css. Roster grid/card HSX now composes app-dense-* classes while preserving slot-* feature classes and data attrs; row/day/staff action buttons compose app-compact-action-button/app-icon-button. Updated stylesheet sync in Layout, Makefile, styling regression list, CSS docs, and synthetic row-controls fixture. Verification: lsp_diagnostics e2e/roster-row-controls.spec.ts returned existing implicit-any hint; bash ./bin/in-env ./bin/style-audit passed; bash ./bin/in-env typecheck passed; bash ./bin/in-env e2e e2e/roster-mobile.spec.ts passed (27/27); bash ./bin/in-env ./bin/css-inventory passed warning-only with no over-budget files; bash ./bin/in-env e2e e2e/roster-time-picker.spec.ts e2e/roster-row-controls.spec.ts passed (7/7) after updating the fixture to compose app-dense-static. Attempted bash ./bin/in-env e2e e2e/styling-regression.spec.ts; it still fails the known stale assertions (desktop header expects flex but sees grid, profile accordion/shift preference hidden, workflow dialog link timeout, phone metrics null).
