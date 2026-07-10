---
id: ir-wec9
status: closed
deps: []
links: [ir-2324, ir-7b1w]
created: 2026-07-10T00:23:09Z
type: bug
priority: 2
assignee: beaudan
parent: ir-z20h
tags: [agent-loop, roster, drag, ui]
---
# Fix staff-drag empty-slot highlight coverage in day-row view

Dragging a staff member over an empty slot in day-row view only highlights a single cell instead of the whole slot/drop target.

## Design

Adjust the roster interaction/dropzone rendering or client-side highlight target for staff-create empty slots in day-row view so the entire slot area is highlighted, matching existing-shift targets. Keep authoritative server DOM and typed interaction/dropzone contracts intact.

## Acceptance Criteria

In day-row view, dragging staff over an empty slot highlights the whole slot/drop target rather than a single cell. Existing shift drag/drop highlighting still works. Focused roster UI/interaction tests or appropriate controller/render contract tests cover the empty-slot target markup.

