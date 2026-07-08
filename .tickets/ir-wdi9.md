---
id: ir-wdi9
status: closed
deps: []
links: [ir-cpkv]
created: 2026-07-07T07:24:38Z
type: task
priority: 3
assignee: Beaudan Brown
tags: [roster, frontend-contracts, htmx]
---
# Migrate Roster request actions

Classify roster header view-state controls, sort/copy/publish mutations, staff panel dialog launchers, shift dialogs, and overview lazy loads. Migrate surface-owned controls to generated action contracts while keeping shell navigation, lazy loads, and global dialogs separate.

## Design

Use the generated SurfaceAction pattern only for surface-owned request initiators. Preserve standard method/action/href where useful; do not promise no-JS UX without matching controller fallbacks. Successful migrated surface mutations should emit actor-local invalidation plus passive resource invalidation, not business OOB HTML.

## Acceptance Criteria

Callsites in scope are classified; migrated surface-owned controls render through generated helpers; any CustomHtmx use is declared with a reason; focused typecheck/tests pass for the subsystem.


## Notes

**2026-07-08T01:59:33Z**

Migrated Roster surface-owned request initiators to generated FrontendSurface actions: week navigation arrows, warning/wage preferences, sort, live toggle, assignment filters, copy previous week, roster column add/delete, day closed toggle, row add/remove, and staff-scope toggle. Roster staff add/edit dialog launchers were classified as missed OverlayAction initiators and migrated in ir-cynv. Remaining hx-* in roster scope is response OOB, lazy month overview load, and staff self-service leave form (classified under Leave/Profile/Staff rather than Roster). typecheck, frontend-check, and focused roster specs pass.
