---
id: ir-zt9h
status: closed
deps: []
links: []
created: 2026-07-10T00:37:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-z20h
tags: [agent-loop, admin, ui, shift-types]
---
# Align admin valid shift window controls horizontally

The Admin page valid shift window start/end controls are stacked and should be easier to scan.

## Design

Adjust the Admin valid shift window UI so the start and end controls align horizontally where viewport width allows, wrapping responsively on smaller screens. Preserve existing form field names, validation, and save behavior.

## Acceptance Criteria

Valid shift window start and end controls appear side-by-side on desktop/tablet widths and wrap cleanly on narrow screens. Existing admin config save behavior and focused admin view/controller tests continue to pass.

