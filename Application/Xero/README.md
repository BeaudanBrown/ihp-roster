# Xero Integration

## Purpose

`Application/Xero/` owns Xero OAuth connection support, reference data, imported
and managed pay item logic, keepalive behavior, and the guided timesheet
preparation/submission workflow.

## Modules

- `Connection.hs` - connection and token boundary.
- `Keepalive.hs` - daily maintenance scheduling for independent six-day
  reference refresh and seven-day token/connection health work.
- `ReferenceSyncJob.hs` - durable connection-deduplicated, tenant-leased,
  paced reference refresh with Xero-specific retry scheduling.
- `ReferenceSyncRequest.hs` - background-safe demand request/coalescing boundary.
- `ReferenceTrust.hs` and `ReferenceTrust/` - typed seven-day snapshot trust,
  retry-chain/progress read model, and enqueue-or-join service.
- `ReferenceDemand.hs` - canonical approval-pinned pay-assignment and missing
  staff-reference demand resolution.
- `Admin/ReferenceData.hs` - the background-safe reference-data persistence
  service and atomic provider-availability reconciliation used by every sync path.
- `Admin/ReferenceSyncPolicy.hs` - Payroll AU v2 Earnings Rates pagination,
  request pacing, runtime page-limit safety, and bounded retry policy.
- `Admin/ImportedPayItems.hs` - the pay-item import boundary.
- `Admin/PayItems.hs` - managed pay item behavior used by preparation.
- `PayrollSourceKey.hs` - exact Xero source/rate key suffix policy over typed
  WageEngine source identities.
- `WorkflowState.hs` - exhaustive capability and presentation projections over
  generated app-owned Xero workflow enums.
- `Admin/ReadModel.hs` - connection-shell and preparation read models.
- `Timesheets/Prepare.hs` - the authoritative preparation workflow.
- `Timesheets/Preview.hs` and `Timesheets/Submission.hs` - internal payload and
  API orchestration used through preparation.

Web request/response behavior belongs under `Web/Controller/Admin/Xero/`. App-owned
sync, mapping, account-selection, pay-item requirement, preparation, decision,
and submission state persists as PostgreSQL enums and uses generated Haskell
constructors. Provider-owned employee, account, pay-run, and timesheet statuses
remain open `Text` at adapter/persistence seams. The ordinary Xero page loads
connection state only; operational mapping, readiness,
calendar, pay-item, and timesheet panels are not separate page surfaces. Synced
payroll calendars remain reference data, while each guided preparation run owns
its explicit selected calendar and period; there is no venue-global calendar
selection.

## Related Docs

- `SPEC.md`
- `AGENTS.md`
- `Web/Controller/Admin/Xero/AGENTS.md`
- `docs/workstreams/xero-payroll.md`
- `docs/workstreams/rooks-pilot.md`
- `vendor/xero-openapi/README.md`
