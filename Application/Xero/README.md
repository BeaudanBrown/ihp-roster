# Xero Integration

## Ownership

`Application/Xero/` owns Xero OAuth/token handling, reference synchronization,
managed/imported pay items, and the preparation/preview/submission services for
Payroll AU timesheets. Web request and response behavior belongs under
`Web/Controller/Admin/Xero/`.

## Start Here


- `Connection.hs` - connection and token boundary.
- `Keepalive.hs` - daily maintenance scheduling for independent six-day
  reference refresh and seven-day token/connection health work.
- `ReferenceSyncJob.hs` - durable connection-deduplicated, tenant-leased,
  paced reference refresh with Xero-specific retry scheduling and typed
  transition publication through the background-job seam.
- `ReferenceSyncRequest.hs` - background-safe demand request/coalescing boundary.
- `ReferenceSyncFence.hs` - transaction-local lease/run/connection fencing for
  category and run publication.
- `ReferenceTrust.hs` and `ReferenceTrust/` - typed seven-day snapshot trust,
  retry-chain/progress read model, and enqueue-or-join service.
- `ReferenceDemand.hs` - canonical approval-pinned pay-assignment and missing
  staff-reference demand resolution.
- `Admin/ReferenceData.hs` - the background-safe reference-data persistence
  service and atomic provider-availability reconciliation used by every sync path.
- `Admin/ReferenceSyncPolicy.hs` - Payroll AU v2 Earnings Rates pagination,
  request pacing, runtime page-limit safety, and bounded retry policy.
- `Admin/ImportedPayItems.hs` - the pay-item import boundary; its dialog observes
  venue-scoped sync state through a live, side-effect-free fragment before
  rendering candidates from local reference rows.
- `Admin/PayItems.hs` - managed pay item behavior used by preparation.
- `PayrollSourceKey.hs` - exact Xero source/rate key suffix policy over typed
  WageEngine source identities.
- `WorkflowState.hs` - exhaustive capability and presentation projections over
  generated app-owned Xero workflow enums.
- `Admin/ReadModel.hs` - connection-shell, read-only reference-sync fragments,
  and preparation read models.
- `Timesheets/Prepare.hs` - the authoritative preparation workflow; its waiting
  dialog observes venue-scoped sync state through a live, side-effect-free
  fragment before one explicit transition into preparation.
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


## Reference Sync Verification Seams

Keep the runtime clock, sleep and jitter seams, plus provider-source and database
fault injection. Publication is not a runtime callback: tests observe committed
invalidation events, exact resources, sequence order and latest resource versions.
Category persistence and final run completion are separate production operations;
exercise stale completion and rollback there rather than recreating an aggregate
completion adapter in test support. Request/coalescing tests use the real request
boundary without installing an otherwise-unused job runtime override.

## Related Docs

- `SPEC.md` — durable authorization, synchronization, and payroll contracts.
- `AGENTS.md` and `Web/Controller/Admin/Xero/AGENTS.md` — editing rules.
- `vendor/xero-openapi/README.md` — provider-contract provenance.
