---
id: ir-2bbl
status: closed
deps: [ir-73ks]
links: []
created: 2026-05-01T00:47:12Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9hgu
tags: [area:roster, area:ui, refactor]
---
# Edit roster slot columns from the roster grid

Add manager-only draft-week controls for adding, renaming, and removing roster slot columns directly in the roster table header.

## Design Notes

- Add roster-week actions such as `CreateRosterWeekSlotDefinitionAction`, `UpdateRosterWeekSlotDefinitionAction`, and `DeleteRosterWeekSlotDefinitionAction` to `RosterWeeksController` rather than Admin.
- Reuse the existing draft guard (`ensureRosterWeekIsDraftForEdit`) and current-venue validation before mutating any definition or affected cells.
- Render slot headers as editable manager-only controls for draft weeks:
  - text input or compact inline form for the column name
  - remove button per column, disabled when it would leave the week with zero columns
  - add button near the header controls to append a column to the current week
- Adding a column should create a definition at the next sort order and blank `roster_slots` for every existing visible row in every roster day for that week.
- Removing a column should soft-delete the definition and active cells for that week only. Use a confirmation when any removed cell has staff/time/flag data.
- Renaming a column updates only the current week definition and broadcasts the current `RosterWeekScope`; no group-config scope should be needed.
- Update focused-field protection to include slot-header name inputs so remote refreshes do not clobber an actively edited name.
- Keep column ordering simple for this refactor: append on add, preserve copied order, no up/down controls, no drag sorting.

## Acceptance Criteria

- Managers can add, rename, and remove draft-week columns from the roster grid without navigating to Admin.
- Workers and non-managers see read-only column labels and no slot-column mutation controls.
- Live weeks reject slot-column mutations with the same read-only behavior as row/assignment edits.
- HTMX responses refresh the smallest practical roster fragment and open peer tabs update through existing live-fragment infrastructure.
- Roster image export still renders clean labels rather than form-control markup in the exported image.
