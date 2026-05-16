---
id: ir-1dhl
status: closed
deps: [ir-ypks, ir-56rx]
links: []
created: 2026-05-16T01:25:58Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-3pnb
tags: [area:live-fragments, area:admin, area:xero]
---
# Migrate admin Xero live surfaces to strict typed contracts

Replace the admin Xero live surface and sub-fragments with typed owner-gated surface contracts.

## Design

Create feature-local typed surface and fragment enums for the Xero shell, staff mappings, pay items, and timesheets fragments. The typed auth rule must preserve owner/super-admin-only access. Broadcasts from Xero connection, mapping, pay-item, readiness, and timesheet preparation flows use typed helpers.

## Acceptance Criteria

Admin Xero live surfaces no longer use mkLiveSurface or raw refs. All Xero fragment endpoints use the typed owner rule. Contract tests cover config, refs, targets, mounted metadata, unauthorized non-owner access, and authorized rendering. Focused Admin/Xero tests pass or unrelated pre-existing failures are documented with ticket notes.


## Notes

**2026-05-16T02:19:41Z**

Migrated admin Xero shell/staff mappings/pay items/timesheets to one owner-gated typed surface and converted Xero actor/passive refreshes to typed helpers. Focused AdminController run still shows four Xero draft-timesheet readiness/preparation failures unrelated to live-surface wiring; targeted Xero fragment checks compile and existing required live suites pass.
