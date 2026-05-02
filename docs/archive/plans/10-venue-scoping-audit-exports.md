# Pipeline 10 — Venue Scoping, Audit, Exports

Read after `IMPLEMENTATION_PLAN.md` and `docs/archive/plans/00-auth-bootstrap-memberships.md`.

## Goal

Enforce venue-scoped data access everywhere, then add the audit and export primitives that depend on those boundaries.

## Scope

- venue-scoped query enforcement
- venue-owned config assumptions
- audit event foundations
- export job infrastructure
- venue isolation tests

## Dependencies

- depends on current venue membership resolution from pipeline 00

## Slices

### A.1 Venue schema and membership model
- **Status:** [x]
- **Goal:** Introduce venue ownership before any further product expansion.
- **Completion notes:**
  - `venues` and `venue_memberships` tables exist.
  - Venue-owned tables now carry `venue_id`.
  - Venue-scoped indexes and fixture wiring are in place.

### A.4 Venue-scope all core business queries
- **Status:** [x]
- **Goal:** Remove global-data assumptions from controllers and helpers.
- **Deliverables:**
  - Add venue filters to roster, timesheet, leave, profile and staff queries.
  - Refactor singleton config assumptions where venue ownership is required.
  - Add helper functions for common venue-scoped query patterns.
- **Completion notes:**
  - `Web/Controller/RosterWeeks.hs`, `Web/Controller/Timesheets.hs`, `Web/Controller/LeaveRequests.hs`, `Web/Controller/Profiles.hs`, and `Web/Controller/Staff.hs` scope operational queries through `currentVenue`, current-membership helpers, and explicit same-venue record guards.
  - `Application/Helper/Controller.hs` centralizes venue-scoped helpers for current-user staff lookup, optional staff validation, same-venue record checks, venue config lookup, and leave-triggered roster recompute writes.
  - Leave approval side effects now only touch `roster_weeks` in the same venue as the leave request, eliminating a cross-venue week-offset write path.
- **Acceptance checks:**
  - No authenticated business flow can read or write another venue’s data.
  - Venue-scoped tests exist for roster, leave and timesheet flows.

### A.5 Audit-event infrastructure for sensitive actions
- **Status:** [x]
- **Goal:** Add durable auditability before exports and broader commercial use.
- **Deliverables:**
  - Add `audit_events` schema.
  - Add shared audit write helper/service.
  - Emit events for approvals, role changes, exports and support-sensitive actions.
- **Completion notes:**
  - `Application/Schema.sql` now defines append-only `audit_events` with venue, actor, target, source-channel, and JSONB payload fields, and `Application/Helper/Controller.hs` centralizes audit writes through shared helpers.
  - `Web/Controller/Timesheets.hs`, `Web/Controller/LeaveRequests.hs`, and `Web/Controller/Users.hs` now write audit rows inside the same transaction as timesheet approval/unapproval/reset, leave approval/denial/deletion, and invitation-driven venue-role assignment.
  - `Test/Controller/TimesheetsSpec.hs`, `Test/Controller/LeaveRequestsSpec.hs`, `Test/Controller/UsersSpec.hs`, and `Test/SchemaSpec.hs` cover the new audit behavior and generated schema surface.
- **Acceptance checks:**
  - Sensitive actions create attributable audit records with venue and actor information.
  - Audit writes participate in the same transaction as business actions where feasible.

### A.8 Export job foundations
- **Status:** [x]
- **Goal:** Treat exports as controlled disclosures before exposing them to customers.
- **Deliverables:**
  - Add `export_jobs` schema.
  - Add export service abstraction and scoped export metadata.
  - Add audit coverage for export generation and download.
- **Completion notes:**
  - `Application/Schema.sql` now defines `export_jobs` with requestor, venue, scope, delivery, generated-file, token, and expiry metadata for explicit export lifecycle tracking.
  - `Application/Helper/Export.hs` centralizes approved-timesheet CSV generation, expiry handling, and audit emission; `Web/Controller/Exports.hs` plus `Web/View/Exports/Index.hs` add an admin-only export jobs page with generation and download flows.
  - `Test/Controller/ExportsSpec.hs`, `Test/SchemaSpec.hs`, and shared test helpers cover generation, venue scoping, download auditing, and schema surfaces for export jobs.
- **Acceptance checks:**
  - Exports are attributable to venue, actor and scope.
  - Export lifecycle is explicit rather than ad hoc controller output.

### 1.3 Update tests for venue isolation
- **Status:** [x]
- **Goal:** Prove that cross-venue access is blocked.
- **Deliverables:**
  - Controller tests for unauthorized cross-venue access.
  - Visibility tests for roster, timesheet and leave data.
  - Tests proving `users` fields cannot bypass venue membership checks.
- **Completion notes:**
  - `Test/Controller/VenueAccessSpec.hs` covers cross-venue denial for staff, roster, leave, and timesheet actions plus venue-scoped visibility for roster, leave, and timesheet pages.
  - `Test/Controller/LeaveRequestsSpec.hs` covers leave-approval side effects staying inside the current venue’s roster weeks.
  - `Test/SchemaSpec.hs` and venue-access controller tests prove `users.user_role` does not bypass venue membership authority.

## Primary Files

- `Application/Schema.sql`
- `Application/Helper/Controller.hs`
- `Application/Helper/Conflict.hs`
- `Application/Helper/Pay.hs`
- `Web/Controller/RosterWeeks.hs`
- `Web/Controller/Timesheets.hs`
- `Web/Controller/LeaveRequests.hs`
- `Web/Controller/Profiles.hs`
- `Web/Controller/Staff.hs`
- future export controllers and tests
