---
id: ir-zmfc
status: closed
deps: [ir-kuyy]
links: []
created: 2026-05-29T03:16:11Z
type: task
priority: 2
assignee: beaudan
parent: ir-78cn
tags: [agent-loop, research, confirmation, frontend-surface]
---
# Confirm final actor invalidation cleanup inventory after migrations

Research the final state and confirm what cleanup remains before making broad guardrail changes.

## Design

Search for `hx-swap-oob`, `render.*Oob`, feature actor-refresh helpers, `liveFragmentsRefreshEvent`, direct successful `hx-target`/`outerHTML` forms, and docs that still describe the older actor business-OOB split. Confirm intentional exceptions: validation-local fragments, extras-only OOB, pure fragment GET/refetch endpoints, non-FrontendSurface legacy, and separately ticketed future work.

## Acceptance Criteria

Ticket note lists remaining paths by category: migrate now, intentional exception, or separate future ticket. No production behavior changes are made.

## Notes

**2026-07-07T05:18:22Z**

Final cleanup inventory after migrations. Migrate/remove now: unused Web.Profiles.LeaveFragments.respondWithProfileLeaveFragments actor-business-OOB helper; unused Admin Xero renderCurrentVenueXeroSectionFragmentOob export/helper if no caller remains. Intentional exceptions: toast/dialog/error extras OOB; validation-local fragments and confirmation dialogs; plain fragment GET/refetch endpoints; Timesheets week navigation HTMX toolbar/day-columns OOB (view navigation, not successful mutation); Staff controller respondWithRosterContentOob is non-FrontendSurface staff-admin legacy response and outside migrated roster actor success paths; roster self-service leave quick-tool OOB remains direct until a future dedicated self-service panel surface; Staff leave request list/form OOB remains non-FrontendSurface local staff-admin UI; Leave archive pagination OOB is explicit pagination/refetch, not mutation success. Roster RenderData renderRowOob remains internal legacy renderer but no RosterWeeksController successful actor path calls it after respondWithRosterPatches removal. Docs already describe semantic actor invalidation as target. Focused verification already run for Profiles, LeaveRequests, RosterWeeks, Timesheets, Admin Xero/admin shift types, and SurfaceDependency.
