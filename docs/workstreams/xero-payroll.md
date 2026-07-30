# Xero Payroll Integration

Status: active

Tickets:

- `#4` - original Xero payroll parent epic
- `#84` - connection foundation maintenance
- `#47`, `#101`, `#78`, `#103`, `#109`, `#119`
- `#142` - retire disconnected operational panels and pre-wizard endpoints
- `#244` - reliable Xero reference data for large tenants
- `#245` - current vendored OpenAPI contracts and local Earnings Rates supplement
- `#246` - provider-availability reconciliation and historical pay preservation
- `#247` - paced, tenant-scoped durable bulk sync
- `#248` - initial and six-day scheduled sync automation
- `#249` - trusted-reference-data import/preparation UX

Living docs to update:

- `Application/Xero/README.md`
- `Application/Xero/SPEC.md`
- `Application/Xero/AGENTS.md`
- `Web/Controller/Admin/Xero/AGENTS.md`
- `Application/Helper/Export/SPEC.md`
- `Application/Helper/View/PageHelp.hs`

Archived context:

- `docs/archive/plans/57-xero-payroll-integration.md`
- `docs/archive/plans/58-xero-connection-foundation.md`
- `docs/archive/plans/63-xero-timesheet-submission.md`
- `docs/archive/plans/64-xero-openapi-contract-and-probes.md`

## Goal

Connect approved, reproducible Bepis payroll data to Xero Payroll AU through
managed pay items and draft timesheet submission.

## Current State

The app has owner-only connection management, one shared synchronous
reference-data sync service, imported-pay-item support, explicit staff/shift pay
assignment modes with immutable pay versions, and a guided preparation workflow
covering staff decisions, managed pay items, readiness, preview, and submission.
The ordinary Xero page is connection-state-only; disconnected operational panels
and pre-wizard preview/submit/retry endpoints have been retired. Initial sync is
still browser-triggered after OAuth, and preparation still performs synchronous
reference refresh. Open work remains around reliable background reference sync,
audit trails, correction behavior, and custom pay item overrides.

## Reliable Reference Data

Epic `#244` moves complete reference refresh onto the existing durable
`app_jobs` worker. Sync requests coalesce by connection, serialize by Xero tenant,
pace provider calls, preserve `Retry-After`, and retain the prior successful
snapshot until every phase succeeds. The daily maintenance sweep requests refresh
around six days; snapshots become stale at seven days.

Provider availability is distinct from owner archival. Missing or inactive Xero
records remain historical facts but cannot be selected for new work. Current
explicit `xero_rate` assignments become remediation-required. Immutable pay
versions and sealed calculations are never silently remapped; approved entries
pinned to an unavailable remote rate block Xero preparation/submission and use
the explicit correction/reapproval path.

Owners join background sync automatically from connection, stale import or
preparation, and missing payroll-eligible staff mappings. Effective roster-only
work does not trigger Xero mapping refresh. Super admins can inspect sanitized
job state and request a coalescing refresh.

## Intended Contract

- Xero management is visible only to venue owners and super admins.
- OAuth/session/security flows remain native full-page flows unless there is a
  concrete in-place workflow need.
- Payroll submission uses approved timesheets with locked pay version context.
- Xero remains payroll/tax/STP authority; Bepis does not calculate tax.
- Submission records should be auditable and should prevent silent destructive
  edits to submitted rows.

## Guided Draft-Timesheet Preparation

Draft-timesheet submission is initiated from the Xero connection shell and
continues inside a workflow modal mounted in the shared dialog overlay lane.
There is no standalone timesheet or readiness panel.

The modal owns period selection, connection checks, token refresh/reconnect handoff,
reference-data sync, explicit preparation-run payroll-calendar/period choice,
account-code deduction, staff mapping resolution, managed pay-item
approval/creation, remote pay-run/timesheet checks, readiness validation,
preview, and final draft submission. Synced calendars remain reference rows;
there is no venue-global payroll-calendar selection.

Staff matching is automated by default, but proposed matches must be shown for
approval before they persist. The modal must also allow manual Xero employee
selection with dropdown controls and persistent `not paid through Xero`
decisions. Do not keep a separate "match" button in the new flow.

Managed pay items that need to be created in Xero must be approved in the same
modal before creation. If there is exactly one synced payroll calendar or pay
item account code, the flow may select it automatically, but the event should
still be visible to the user.

Use Xero Payroll AU pay runs and timesheets to describe period state. Periods
whose Xero pay run is `POSTED` are hard-blocked. For v1, any existing Xero
timesheet for the same employee and selected period blocks creation until
explicit update support is designed and implemented.

Relevant tickets:

- `#123` - research draft-timesheet update support

## Exit Criteria

- Xero preview and submission use the same locked payroll facts as exports.
- Guided preparation clearly shows missing staff, pay item, and mapping inputs.
- Submission results and errors are auditable.
- Large reference snapshots are paced, recoverable, availability-reconciled, and
  refreshed without browser-dependent owner action.
- Living Xero docs replace archived plan instructions for future agents.
