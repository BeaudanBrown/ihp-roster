# Implementation Roadmap

This file is the canonical roadmap for implementation order.

Live implementation tracking now lives in repo-local `tk` tickets under
`.tickets/`. Use this roadmap to understand ordering and dependencies, then use
`tk ready`, `tk blocked`, `tk show <id>`, and `tk dep tree <id>` for current
status, blockers, and next actions.

Use it to answer:
- what the current priorities are
- which pipelines can run in parallel
- which dependencies must land first

Do not treat the pipeline files under `plans/` as independent sources of truth
for ordering or live status. They hold durable design context for specific
workstreams, but this file defines the global sequence and `tk` defines the live
work graph.

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
  - `plans/46-payroll-export-e2e-hardening.md`
  - `plans/47-payroll-generation-parity.md`
  - `plans/48-super-admin-support-access.md`
  - `plans/49-roster-groups-and-venue-bootstrap.md`
  - `plans/50-release-readiness.md`
  - `plans/51-mobile-responsive-foundations.md`
  - `plans/52-roster-mobile-refactor.md`
  - `plans/53-programmatic-demo-seeding.md`
  - `plans/54-styling-system-refactor.md`
  - `plans/55-record-retention-soft-deletion.md`
  - `plans/56-declarative-live-fragments.md`
  - `plans/57-xero-payroll-integration.md`
  - `plans/58-xero-connection-foundation.md`
  - `plans/59-code-smell-remediation.md`
  - `plans/60-v1-schema-hardening.md`
  - `plans/61-view-helper-split.md`
  - `plans/62-live-fragment-system-refactor.md`
  - `plans/67-component-boundary-cleanup.md`
  - `plans/69-profiling-system-refactor.md`
- Historical completed and superseded slices:
  - `plans/90-historical-completed-slices.md`

## Repo-Local Ticket Epics

- `ir-qi7t` — founder super-admin support access and venue switching
- `ir-45b6` — expanded staff profiles and recurring shift preferences
- `ir-jooi` — versioned surface projection cache for live and HTMX surfaces
- `ir-9f7z` — app JavaScript runtime refactor
- `ir-t7be` — roster groups and centralized venue bootstrap defaults
- `ir-52nw` — regional Victorian public holidays and recurring refreshes
- `ir-5o6t` — auto-create empty roster weeks and reusable week controls
- `ir-sryt` — app-wide profiling instrumentation
- `ir-mwhc` — ordinary account multi-venue switching backlog
- `ir-vifu` — multi-group payroll exports backlog
- `ir-hsuu` — programmatic demo seeding
- `ir-u4mc` — record retention and soft deletion guardrails
- `ir-176p` — Xero payroll integration
- `ir-mjov` — Xero connection foundation maintenance
- `ir-6vvh` — code smell remediation backlog
- `ir-18tm` — component boundary cleanup from the 2026-04-30 scan
- `ir-caf4` — V1 schema hardening
- `ir-2usx` — view helper split
- `ir-g778` — release readiness and first-client acceptance

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
- roster scheduling should move from one venue-global roster surface toward explicit roster groups so a venue can eventually support multiple rosters such as front of house and back of house
- venue creation and fixture seeding should converge on one idempotent roster bootstrap path that guarantees sane minimum roster defaults instead of relying on ad hoc slot-name creation
- future roster-group staffing should allow venue staff to be applicable to one roster group, multiple roster groups, or all groups without conflating that with venue membership or ordinary multi-venue switching

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
7. Roster groups and venue bootstrap defaults
   - Plan: `plans/49-roster-groups-and-venue-bootstrap.md`
   - Depends on the venue/auth foundations and should land before release-readiness polish so new venues and richer roster shapes stop depending on ad hoc slot setup.
8. Record retention and soft-deletion guardrails
   - Plan: `plans/55-record-retention-soft-deletion.md`
   - Depends on timesheet/leave provenance, pay snapshots, roster groups, and export primitives.
   - Must land before paid venue data is treated as production records.
9. Release readiness, hardening, and acceptance sweep
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

### Pipeline 46 — Payroll Export E2E Hardening
- **Status:** [-]
- **File:** `plans/46-payroll-export-e2e-hardening.md`
- **Focus:** lock payroll export behavior down with E2E coverage and regression fixtures as the export workflow matures.

### Pipeline 47 — Payroll Generation Parity
- **Status:** [-]
- **File:** `plans/47-payroll-generation-parity.md`
- **Focus:** close payroll generation gaps between the IHP implementation and the historical payroll output contract.

### Pipeline 49 — Roster Groups and Venue Bootstrap Defaults
- **Status:** [-]
- **File:** `plans/49-roster-groups-and-venue-bootstrap.md`
- **Focus:** move the roster domain toward group-scoped scheduling, centralize minimum roster bootstrap defaults, and add staff-to-roster-group applicability.
- **Progress:** planning direction settled on `2026-03-31`. The first foundation slice now introduces `roster_groups`, adds group foreign keys to `slot_names` and `roster_weeks`, centralizes minimum venue roster setup into one helper, and keeps the current app behavior pinned to the default roster group until explicit multi-group UI and staff applicability land.

### Pipeline 50 — Release Readiness
- **Status:** [ ]
- **File:** `plans/50-release-readiness.md`
- **Focus:** testing coverage, UI polish, reporting, security hardening, and release acceptance.

### Pipeline 55 — Record Retention and Soft Deletion
- **Status:** [ ]
- **File:** `plans/55-record-retention-soft-deletion.md`
- **Focus:** make soft deletion the default for business records, block hard deletion of protected employment/payroll/roster/audit records at the database layer, and replace remaining destructive controller paths before paid venue data goes live.

### Cross-Cutting Note — Mobile and Responsive Foundations
- **Status:** [-]
- **File:** `plans/51-mobile-responsive-foundations.md`
- **Focus:** establish the shared cross-device design contract and automated Playwright coverage for mobile-critical surfaces before page-by-page polish diverges.

### Pipeline 20A — Roster Mobile Refactor
- **Status:** [-]
- **File:** `plans/52-roster-mobile-refactor.md`
- **Focus:** use the roster page as the first cross-device refactor surface and lock in the mobile/tablet behavior contract before visual restructuring.

### Pipeline 53 — Programmatic Demo Seeding
- **Status:** [ ]
- **File:** `plans/53-programmatic-demo-seeding.md`
- **Focus:** replace the current one-off dev seed with scenario-driven deterministic demo data generation that can scale venue shape, staffing mix, pay configuration, and roster realism for client demonstrations and manual QA.
- **Priority note:** this is the fastest path to a realistic demo environment for the current client demonstration window; land the minimum demo slice before broader scenario/export polish.

### Cross-Cutting Note — Styling System Refactor
- **Status:** [-]
- **File:** `plans/54-styling-system-refactor.md`
- **Focus:** keep shared tokens, Bootstrap bridge styles, layout primitives, and feature CSS organized as the UI surface expands.

### Cross-Cutting Note — Declarative Live Fragments
- **Status:** [-]
- **File:** `plans/56-declarative-live-fragments.md`
- **Focus:** continue moving collaborative/stale-prone surfaces onto declared live-fragment metadata instead of feature-specific JavaScript.

### Pipeline 57 — Xero Payroll Integration
- **Status:** [ ]
- **File:** `plans/57-xero-payroll-integration.md`
- **Focus:** connect each venue to Xero Payroll AU, map IHP staff and earning buckets to Xero employees and earnings rates, preview approved IHP payroll weeks as Xero timesheet payloads, and submit draft Xero timesheets with auditable request/response history.
- **Priority note:** read-only sync, base mapping, and durable pay item requirement records are in place. Next, add admin-reviewed live Xero earnings-rate pay item create/update actions from IHP/FWC award data before deterministic timesheet preview. Employee creation remains deferred; pay item creation is now part of the first practical milestone.

### Pipeline 58 — Xero Connection Foundation
- **Status:** [-]
- **File:** `plans/58-xero-connection-foundation.md`
- **Focus:** maintain the Xero OAuth/connection, token, and tenant-sync foundation that Pipeline 57 builds on.

### Maintenance — Code Smell Remediation
- **Status:** [-]
- **File:** `plans/59-code-smell-remediation.md`
- **Focus:** track repo-structure, helper-boundary, lint, and file-size cleanup that improves ongoing agent navigation.

### Maintenance — View Helper Split
- **Status:** [ ]
- **File:** `plans/61-view-helper-split.md`
- **Focus:** reduce `Application/Helper/View.hs` to a compatibility re-export wrapper and move its mixed helper implementations into focused view helper modules.

### Maintenance — Live Fragment System Refactor
- **Status:** [-]
- **File:** `plans/62-live-fragment-system-refactor.md`
- **Focus:** keep server/client live-fragment protocol, shared runtime behavior, and feature-surface declarations reusable while the JavaScript runtime is split under `ir-9f7z`.

## Parallelism Rules

These pipelines can overlap when they respect the dependency constraints above:

- `plans/20-roster-and-conflicts.md` can progress in parallel with auth/scoping work if it does not reintroduce global-role or cross-venue assumptions.
- `plans/30-timesheets-and-leave.md` can progress alongside `plans/40-pay-config-and-admin.md` once the snapshot/version contract is fixed.
- `plans/45-payroll-report-exports.md` can progress once the pay snapshot contract is fixed, but it should not hardcode legacy report variants into controller actions; keep the report-definition model in step with the export engine work.
- `plans/49-roster-groups-and-venue-bootstrap.md` should lead any future roster UX expansion that assumes more than one roster per venue or that needs guaranteed minimum slot defaults; do not build those assumptions directly into venue-global roster code first.
- `plans/50-release-readiness.md` should mostly trail the others, but test additions can happen incrementally.
- `plans/51-mobile-responsive-foundations.md` should run alongside roster, leave, and timesheet UX work so responsive contracts land before too many new desktop-first assumptions accumulate.
- `plans/52-roster-mobile-refactor.md` should lead any roster-page responsive restructuring so layout changes stay anchored to explicit mobile/tablet contracts rather than ad hoc CSS tweaks.
- `plans/53-programmatic-demo-seeding.md` can proceed alongside roster/payroll/admin work so long as it reuses existing bootstrap helpers and does not destabilize deterministic e2e fixtures or minimal bootstrap SQL.
- `plans/55-record-retention-soft-deletion.md` should run before release-readiness acceptance and before Xero submission work, because Xero sync history and venue export packs should be built on the protected-record model from day one.
- `plans/57-xero-payroll-integration.md` can start after the approved-timesheet, pay-snapshot, payroll earnings export, and protected-record foundations are stable. It should reuse those foundations rather than introducing a parallel payroll calculation path.

## Read Order For Agents

When working a feature:

1. Read the relevant canonical spec files in `specs/`.
2. Read this roadmap for global ordering and dependencies.
3. Read only the relevant file under `plans/`.
4. Check `plans/90-historical-completed-slices.md` only if prior implementation notes or superseded work matter.
