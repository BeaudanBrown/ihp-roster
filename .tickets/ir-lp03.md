---
id: ir-lp03
status: closed
deps: [ir-fnfn, ir-f5mw]
links: []
created: 2026-05-29T00:51:30Z
type: task
priority: 2
assignee: beaudan
parent: ir-cqg3
tags: [agent-loop, css, components, roster, timesheets, responsive]
---
# Extract shared horizontal day-strip layout primitives for roster and timesheets

Roster day-column layout and timesheet week layout both implement horizontally scrollable/snap-enabled day strips. Extract the common frame/grid/panel primitives while keeping feature-specific sizing and card details local.

## Design

Add shared classes such as .app-horizontal-frame, .app-horizontal-grid, and optional .app-horizontal-panel in a component module. Move common declarations from .timesheet-week-frame and .roster-grid-frame[data-roster-layout=day_columns] into the shared class: display/block overflow-x auto, padding, cursor grab/grabbing with data-horizontal-dragging, scrollbar styling, and mobile snap toggles where generic. Keep feature CSS responsible for CSS variables/counts, min column widths, gaps, and panel/card styling. Update Web/View/Timesheets/Index.hs and Web/View/RosterWeeks/Grid.hs to include shared classes while retaining existing feature classes for tests and JS. Do not change app-horizontal-scroll.js contracts.

## Acceptance Criteria

Roster day-column frame and timesheet week frame use the shared horizontal primitive classes plus their feature classes. Existing data-horizontal-snap and data-horizontal-drag-scroll attributes are unchanged. Duplicate scroll/drag/snap CSS is reduced. Mobile horizontal overflow remains local, not page-level. Focused checks pass or are noted: e2e/mobile-experience.spec.ts, e2e/roster-mobile.spec.ts, and style-audit.


## Notes

**2026-05-29T01:40:45Z**

Added shared app-horizontal-frame/grid/panel primitives and applied them to roster day-column and timesheet week strips while retaining existing feature classes and data-horizontal-* attrs. Verification: bash ./bin/in-env ./bin/style-audit passed; bash ./bin/in-env typecheck passed; bash ./bin/in-env e2e e2e/mobile-experience.spec.ts passed (24/24); bash ./bin/in-env e2e e2e/roster-mobile.spec.ts passed (27/27).
