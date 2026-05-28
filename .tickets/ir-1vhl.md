---
id: ir-1vhl
status: open
deps: [ir-mm13]
links: []
created: 2026-05-27T23:58:34Z
type: task
priority: 1
assignee: beaudan
parent: ir-gz9k
tags: [area:roster, area:mobile, area:static]
---
# Migrate roster snapping to the shared component

Replace roster-specific phone snapping with the shared horizontal snap component while preserving current behavior.

## Design

Keep day-row equal slot-group snapping and day-column nearest-day centering. Preserve data-roster-snap-dragging or migrate CSS safely with tests updated to the shared contract.

## Acceptance Criteria

Existing roster-mobile snap tests pass or are updated to equivalent shared data attrs; day rail/scroller layout remains stable; mouse drag-scroll for day columns remains functional.

