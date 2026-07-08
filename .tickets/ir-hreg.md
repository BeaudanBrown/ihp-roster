---
id: ir-hreg
status: closed
deps: [ir-dvoi]
links: []
created: 2026-07-08T04:59:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5146
tags: [frontend-contracts, surface, htmx]
---
# Migrate remaining local feature request initiators

Migrate remaining local feature-owned raw HTMX request initiators into FrontendSurface or AppShell ownership.

## Design

Move Web/View/Staff/Edit.hs leave form to StaffSurface, Web/View/RosterWeeks/StaffSelfServicePanel.hs leave form to RosterSurface, Web/View/RosterWeeks/Overview.hs lazy load to generated Roster surface fragment/lazy helper, and classify/migrate Web/View/Admin/Xero/TimesheetPreparation.hs staff mapping fragment to AppShell dialog action or AdminXero surface action based on ownership discovered during implementation.

## Acceptance Criteria

Listed raw HTMX callsites removed; ownership decision documented in ticket notes; focused Staff/Roster/Admin Xero tests pass.


## Notes

**2026-07-08T06:03:57Z**

Migrated remaining listed local feature request initiators: Staff edit leave form now uses StaffSurface create-staff-leave-request; roster self-service leave form now uses RosterSurface create-roster-self-service-leave-request; roster week overview lazy loading now uses the generated FrontendSurface lazy fragment helper with a RosterSurface roster-week-overview fragment; Xero preparation staff-mapping edit reload is classified as AdminXeroSurface ownership and uses show-xero-timesheet-preparation-staff-mappings. Added guardrails for the migrated files. Verified with: bash ./bin/in-env typecheck; bash ./bin/in-env frontend-check; bash ./bin/in-env hspec-test --match "StaffController" --match "RosterWeeksController" --match "AdminController" --match "Xero" --match "Frontend contract" --match "SurfaceGuard".
