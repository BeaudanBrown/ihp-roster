---
id: ir-73ks
status: closed
deps: [ir-5dzy]
links: []
created: 2026-05-01T00:47:09Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-9hgu
tags: [area:roster, area:schema, refactor]
---
# Add week-local roster slot-definition model

Introduce a roster-week-owned slot definition table and migrate roster slot structure away from group-level slot_names.

## Design Notes

- Add a week-owned column-definition table, e.g. `roster_week_slot_definitions`, with `roster_week_id`, `name`, `sort_order`, `deleted_at`, `deleted_by_user_id`, `delete_reason`, timestamps, and a non-empty/120-character name check.
- Add `roster_slots.roster_week_slot_definition_id` and migrate each active historical cell from its `slot_name_id` to a definition row for that row's `roster_week_id` and current `slot_sort_order`/name.
- Replace the active-cell uniqueness index with `(roster_day_id, row_index, roster_week_slot_definition_id) WHERE deleted_at IS NULL`.
- Add a trigger that ensures a roster slot's `roster_day_id` belongs to the same `roster_week_id` as its `roster_week_slot_definition_id`. This replaces the old indirect slot-name/group consistency check.
- Update `Web/RosterWeeks/Service.hs` so `ensureRosterWeekExists` creates days plus week-local definitions and cells:
  - existing week: leave definitions unchanged
  - missing week with a previous available week in the same roster group: clone only active definitions into the new week and create blank cells
  - no previous week: create definitions from `defaultRosterSlotNames`
- Update `copyRosterWeek` and `replaceRosterWeekFromSource` to create new target-week definitions and map copied cells onto those new ids.
- Replace `SlotName` render data with the new week-slot definition type across `Web/RosterWeeks/Types.hs`, `RenderData.hs`, `Grid.hs`, and test helpers.
- Keep `slot_names` only as a temporary migration source during this slice; active roster-week code should no longer read it.

## Acceptance Criteria

- `regen-types` produces a typed week-slot-definition model and roster slots no longer need `slot_name_id` in active code.
- Existing roster weeks backfill to week-local definitions without changing rendered column labels, row counts, assignments, times, flags, or live/draft state.
- Creating a missing week copies column definitions from the previous available week for that roster group, but does not copy assignments.
- Copying or replacing a roster week copies both definitions and cell data while preserving target-week independence.
- Database constraints reject cells whose day and slot definition belong to different roster weeks.
