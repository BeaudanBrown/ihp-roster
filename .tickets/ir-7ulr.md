---
id: ir-7ulr
status: closed
deps: [ir-zcue, ir-j08r, ir-h9w6]
links: []
created: 2026-07-09T05:06:02Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-7wsy
tags: [agent-loop, roster, frontend-contracts, interaction]
---
# Split roster drag refs for shift move-copy and staff drop

Update the roster FrontendSurface contract to use distinct source/dropzone refs for existing shift drag/drop and staff drag/drop.

## Design

Declare distinct roster refs for shift source, staff source, empty/create dropzone, day-column move dropzone, and existing-shift assignment dropzone as needed. Preserve current shift source compatibility with row-grid empty targets and whole-day-column move targets, including modifier copy. Add staff source compatibility with existing-shift targets, row-grid create targets, and day-column create-card targets. Update Web.RosterWeeks.FrontendSurface exports/helpers accordingly.

## Acceptance Criteria

Shift-to-shift is not a compatible drop. Staff-to-existing-shift and staff-to-create-target are compatible. Existing shift move/copy generated semantics remain intact. The generated roster manifest reflects distinct refs and compatibility.

