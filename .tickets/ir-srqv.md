---
id: ir-srqv
status: closed
deps: [ir-2bbl]
links: []
created: 2026-05-01T00:47:15Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-9hgu
tags: [area:roster, area:admin, refactor]
---
# Retire admin slot-name management and sync-slots workflow

Remove the admin slot-name subsection, admin slot-name live scope, and roster Sync Slots flow after slot columns are week-local.

## Design Notes

- Remove Admin slot-name actions from `Web/Types.hs`, `Web/Routes.hs` output paths, `Web/Controller/Admin.hs`, and `Web/Controller/Admin/Support.hs`.
- Simplify `Web/View/Admin/RosterGroups.hs` so roster group cards manage roster group name/status/default ordering only. Do not render `renderRosterGroupSlotNamesFragment` or hidden admin slot-name live surfaces.
- Remove `AdminSlotNamesScope`, `AdminSlotNamesFragment`, `RosterGroupConfigScope` usage that exists only to push group-template changes to roster pages. Roster column edits should broadcast the normal week scope.
- Remove `SyncRosterWeekSlotStructureAction`, `canSyncRosterWeekSlots`, and the "Sync Slots" menu item from the roster action menu.
- Delete admin slot-name CSS from `static/css/features/admin.css` once no view uses it.
- Update any admin copy that says slot names are managed inside each roster group.

## Acceptance Criteria

- The Admin page no longer shows a slot-name subsection under roster groups.
- There are no route/action constructors for create/update/move/delete slot names or sync slot structure.
- Roster pages no longer subscribe to hidden roster-group-config surfaces just to watch slot-name template edits.
- Existing admin roster-group CRUD, invite, export, shift-type, and Xero fragments still render and live-update as before.
