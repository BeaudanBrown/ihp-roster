# Xero Integration

## Purpose

`Application/Xero/` owns Xero OAuth connection support, reference data, imported
and managed pay item logic, keepalive behavior, and the guided timesheet
preparation/submission workflow.

## Modules

- `Connection.hs` - connection and token boundary.
- `Keepalive.hs` - recurring token/connection health support.
- `ReferenceSyncJob.hs` - durable connection-deduplicated, tenant-leased,
  paced reference refresh with Xero-specific retry scheduling.
- `ReferenceSyncRequest.hs` - background-safe demand request/coalescing boundary.
- `Admin/ReferenceData.hs` - the background-safe reference-data persistence
  service and atomic provider-availability reconciliation used by every sync path.
- `Admin/ReferenceSyncPolicy.hs` - PayItems pagination, request pacing, and
  bounded retry policy.
- `Admin/ImportedPayItems.hs` - the pay-item import boundary.
- `Admin/PayItems.hs` - managed pay item behavior used by preparation.
- `Admin/ReadModel.hs` - connection-shell and preparation read models.
- `Timesheets/Prepare.hs` - the authoritative preparation workflow.
- `Timesheets/Preview.hs` and `Timesheets/Submission.hs` - internal payload and
  API orchestration used through preparation.

Web request/response behavior belongs under `Web/Controller/Admin/Xero/`. The
ordinary Xero page loads connection state only; operational mapping, readiness,
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
