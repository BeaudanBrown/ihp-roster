# Implementation Roadmap

This file is the canonical roadmap for implementation order.

Use it to answer:
- what the current priorities are
- which pipelines can run in parallel
- which dependencies must land first

Do not treat the pipeline files under `plans/` as independent sources of truth for ordering. They hold the detailed task breakdowns for a specific workstream, but this file defines the global sequence.

Business requirements remain canonical in `specs/`.

## Planning Structure

- Root roadmap: `IMPLEMENTATION_PLAN.md`
- Detailed pipeline plans:
  - `plans/00-auth-bootstrap-memberships.md`
  - `plans/10-venue-scoping-audit-exports.md`
  - `plans/20-roster-and-conflicts.md`
  - `plans/30-timesheets-and-leave.md`
  - `plans/40-pay-config-and-admin.md`
  - `plans/45-payroll-report-exports.md`
  - `plans/48-super-admin-support-access.md`
  - `plans/50-release-readiness.md`
- Historical completed and superseded slices:
  - `plans/90-historical-completed-slices.md`

## Current Direction

The current implementation direction is:

- local, founder-managed rollout
- small number of venues
- standardised managed SaaS with venue as the current customer boundary
- no public self-serve venue creation in the near term

The current high-priority business-logic decisions are:

- business authority comes from `venue_memberships`, not `users`
- privileged access uses founder-managed venue bootstrap, not bootstrap-admin signup
- development resets should keep a deterministic founder bootstrap login in `Application/Fixtures.sql`
- payroll-adjacent records use correction-safe history
- pay/config history uses immutable snapshot versions created by venue admin bulk-save actions
- a future founder-only cross-venue `super_admin` / `platform_admin` capability should be modelled separately from venue roles, not by stretching `users.user_role` or `venue_memberships.venue_role`
- the active founder support-access lane should reuse the existing `currentVenueId` session slot through a dedicated support surface rather than inventing synthetic venue memberships

## Status Legend

- `[ ]` Not started
- `[-]` In progress
- `[x]` Done
- `[!]` Superseded or legacy context only

## Global Order

These steps are globally ordered. Detailed task breakdowns live in the linked pipeline files.

1. Membership-scoped auth and bootstrap hardening
   - Plan: `plans/00-auth-bootstrap-memberships.md`
   - Must land before broad controller/query work.
2. Venue-scoped queries, audit foundations, and export primitives
   - Plan: `plans/10-venue-scoping-audit-exports.md`
   - Depends on membership-scoped auth helpers.
3. Timesheet/leave correction-safe flows
   - Plan: `plans/30-timesheets-and-leave.md`
   - Depends on auth and audit foundations.
4. Snapshot-based pay/config versioning and venue admin save workflow
   - Plan: `plans/40-pay-config-and-admin.md`
   - Depends on venue scoping and should shape exports.
5. Roster and conflict UX expansion
   - Plan: `plans/20-roster-and-conflicts.md`
   - Can proceed in parallel where it does not conflict with auth/scoping changes.
6. Payroll report export parity
   - Plan: `plans/45-payroll-report-exports.md`
   - Depends on pay/config snapshot foundations and should reuse export job primitives instead of ad hoc report endpoints.
7. Release readiness, hardening, and acceptance sweep
   - Plan: `plans/50-release-readiness.md`
   - Depends on the foundations above.

## Active Pipelines

### Pipeline 00 — Auth, Bootstrap, Memberships
- **Status:** [x]
- **File:** `plans/00-auth-bootstrap-memberships.md`
- **Focus:** remove bootstrap-admin logic, resolve current venue membership on each request, and stop using `users` as the source of venue business authority.
- **Progress:** A.2 and A.3 are complete. Public signup is now invite-only via `venue_invitations`, first-user auto-admin logic is removed, and operational auth resolves venue authority from active `venue_memberships`.

### Pipeline 10 — Venue Scoping, Audit, Exports
- **Status:** [x]
- **File:** `plans/10-venue-scoping-audit-exports.md`
- **Focus:** enforce venue-scoped queries everywhere, add audit primitives, and introduce export job infrastructure.
- **Progress:** A.4, A.5, A.8, and 1.3 are complete. Core business controllers/helpers now scope reads and writes to `currentVenue`; `audit_events` plus shared audit helpers now cover timesheet approvals/unapproval/reset, leave approval/denial/deletion, invitation-driven venue-role assignment, and export generation/download; `export_jobs` plus a centralized export service now provide venue-scoped approved-timesheet CSV exports with expiring download tokens and admin UI/tests; venue-isolation tests cover roster, leave, timesheet, export, and cross-venue side effects.

### Pipeline 20 — Roster and Conflicts
- **Status:** [-]
- **File:** `plans/20-roster-and-conflicts.md`
- **Focus:** roster page workflow, conflict rendering, roster-side staff editing, and related UX slices.
- **Note:** parts of this stream are already delivered; remaining work should respect auth/scoping foundations.

### Pipeline 30 — Timesheets and Leave
- **Status:** [x]
- **File:** `plans/30-timesheets-and-leave.md`
- **Focus:** exact time validation, approval workflows, edit windows, leave lifecycle, and correction-safe history.
- **Progress:** 5.1, 5.2, 5.3, 5.4, and A.6 are complete. Timesheet mutations now append `timesheet_entry_versions`, leave lifecycle transitions append `leave_request_events`, invitation assignment plus role changes append `venue_membership_role_events`, and reviewed payroll-adjacent records are no longer silently deleted; coverage was added in timesheet, leave, user, and schema specs.

### Pipeline 40 — Pay Config and Admin
- **Status:** [-]
- **File:** `plans/40-pay-config-and-admin.md`
- **Focus:** SQL pay engine, immutable pay/config snapshot versions, and the venue admin bulk-edit/save workflow.
- **Progress:** A.7 and 7.1 are complete. The app now stores immutable `pay_config_snapshots`, binds approved timesheets to snapshot versions, carries snapshot version metadata on exports, keeps approved pay calculations stable after later config changes, and exposes venue-scoped admin config-table screens for pay levels, shift types, pay-level day rules, slot names, and day names. Venue configuration editing and wage/hour summaries remain open.

### Pipeline 45 — Payroll Report Exports
- **Status:** [-]
- **File:** `plans/45-payroll-report-exports.md`
- **Focus:** legacy Go payroll report parity on top of `export_jobs`, snapshot-pinned pay output, and a venue-scoped report-definition model.
- **Progress:** parity inventory and SQL-fit assessment are now captured; implementation still needs the report-definition model, pay-engine fixes for actual shift-type/pay-level resolution, the first staff-pay CSV, the hourly ZIP, and admin/report configuration UI.

### Pipeline 50 — Release Readiness
- **Status:** [ ]
- **File:** `plans/50-release-readiness.md`
- **Focus:** testing coverage, UI polish, reporting, security hardening, and release acceptance.

## Parallelism Rules

These pipelines can overlap when they respect the dependency constraints above:

- `plans/20-roster-and-conflicts.md` can progress in parallel with auth/scoping work if it does not reintroduce global-role or cross-venue assumptions.
- `plans/30-timesheets-and-leave.md` can progress alongside `plans/40-pay-config-and-admin.md` once the snapshot/version contract is fixed.
- `plans/45-payroll-report-exports.md` can progress once the pay snapshot contract is fixed, but it should not hardcode legacy report variants into controller actions; keep the report-definition model in step with the export engine work.
- `plans/50-release-readiness.md` should mostly trail the others, but test additions can happen incrementally.

## Read Order For Agents

When working a feature:

1. Read the relevant canonical spec files in `specs/`.
2. Read this roadmap for global ordering and dependencies.
3. Read only the relevant file under `plans/`.
4. Check `plans/90-historical-completed-slices.md` only if prior implementation notes or superseded work matter.
