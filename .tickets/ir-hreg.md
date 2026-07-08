---
id: ir-hreg
status: open
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

