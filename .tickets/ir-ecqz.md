---
id: ir-ecqz
status: open
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

