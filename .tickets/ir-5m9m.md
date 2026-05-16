---
id: ir-5m9m
status: closed
deps: [ir-ypks, ir-56rx]
links: []
created: 2026-05-16T01:25:53Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:admin]
---
# Migrate admin simple live surfaces to strict typed contracts

Replace admin invites and roster-group live surfaces with typed contracts and align the roster staff self-service quick-timesheet surface with the typed timesheet contract.

## Design

Model admin invites and roster groups like the typed admin shift-types surface. Replace the staff self-service quick-timesheet card's manual timesheets surface with the existing typed timesheet surface key and typed refs, preserving request decoration and focused-field behavior.

## Acceptance Criteria

Admin invites, admin roster groups, and roster staff self-service quick-timesheet card have no manual live surface config construction. Fragment endpoints use typed auth. Contract/controller tests cover authorized and unauthorized access plus mounted metadata. Existing admin and roster live-update tests pass.


## Notes

**2026-05-16T02:19:41Z**

Migrated admin invites and roster groups to typed contracts and replaced roster quick-timesheet manual config with the typed timesheet surface.
