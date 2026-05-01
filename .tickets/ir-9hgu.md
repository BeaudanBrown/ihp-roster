---
id: ir-9hgu
status: closed
deps: [ir-5dzy]
links: [ir-tbjx]
created: 2026-05-01T00:47:05Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-t7be
tags: [workstream, coordinator:coordinator-wii, area:roster, refactor]
---
# Refactor roster slot names into week-local roster columns

Replace the separate roster-group slot-name admin/template workflow with week-local roster slot columns edited directly from the roster grid.

## Current Findings

- `slot_names` is currently a roster-group-level template table. `roster_slots` stores `slot_name_id` plus `slot_sort_order`, so an existing roster week only changes column structure after `SyncRosterWeekSlotStructureAction`.
- The roster page already derives rendered column order from the slots present in that week via `fetchRosterWeekOrderedSlotNamesFromSlots`; this is close to the desired week-local behavior, but it still depends on global slot-name rows for identity and display names.
- Admin slot-name CRUD is spread through `Web/Controller/Admin.hs`, `Web/Controller/Admin/Support.hs`, `Web/View/Admin/RosterGroups.hs`, `Application.Helper.LiveUpdate` admin slot-name scopes/fragments, Hspec admin config/access specs, and `e2e/admin-slot-names.spec.ts`.
- Roster structure is created in `Web/RosterWeeks/Service.hs`: `createEmptyRosterWeek`, `copyRosterWeek`, `replaceRosterWeekFromSource`, `ensureRosterDayHasMinimumRows`, and `syncRosterWeekSlotStructure`.

## Target Direction

Slot columns should belong to a roster week, not to roster-group configuration. Managers edit the current draft week's columns directly in the roster grid header with small add/remove controls and inline names. When a future week is first created for a roster group, it should inherit the previous available week's column definitions for that same roster group; if no prior week exists, use the hard-coded bootstrap defaults from `Application.Helper.RosterGroups`.

Manual `Copy Previous Week` remains the full roster-copy action for assignments, times, flags, day closed state, rows, and column definitions. Opening a missing week should only inherit column structure, not staff assignments.

## Child Work

- `ir-73ks` - schema/service foundation for week-local slot definitions.
- `ir-2bbl` - roster-grid inline slot-column controls.
- `ir-srqv` - remove admin slot-name section and Sync Slots flow.
- `ir-zqb2` - update fixtures, Hspec, E2E, and seed/profile data.

## Acceptance Criteria

- Draft roster weeks let managers add, rename, and remove roster columns from the roster UI without visiting Admin.
- Slot column names/order/count can differ between roster weeks for the same roster group.
- Missing future weeks inherit column definitions from the previous available week for that roster group, falling back to default slot names for the first week.
- `Sync Slots` and the admin slot-name card are gone from the product surface.
- Roster live-update invalidation remains week-scoped for column mutations and protects focused roster inputs.
