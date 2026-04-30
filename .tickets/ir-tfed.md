---
id: ir-tfed
status: open
deps: [ir-adtf, ir-shsr]
links: []
created: 2026-04-29T04:41:30Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-176p
tags: [area:xero, area:payroll, source:plans-57]
---
# Preview and submit draft Xero timesheets

Transform approved snapshot-pinned IHP timesheets into Xero draft timesheets with duplicate/update handling.

## Design

source_plan: plans/57-xero-payroll-integration.md
detailed_plan: plans/63-xero-timesheet-submission.md

The draft-timesheet lane is split into API client, persistence, readiness,
preview, submission, and later correction/update slices. Implement the readiness
foundation before building the preview UI.

Xero Payroll AU endpoint contract:

- `GET /Timesheets` for duplicate/status reads; response envelope is
  `Timesheets`; supports `where`, `order`, and `page`.
- `POST /Timesheets` for draft create; body is `array[Timesheet]`; IHP should
  send one singleton array per employee/pay period.
- `POST /Timesheets/{TimesheetID}` for later draft update; require remote
  `Status == DRAFT` before use.
- `TimesheetLines[].NumberOfUnits` should contain one value per day in the
  selected Xero payroll calendar period.
- The IHP period being prepared must exactly match the selected Xero payroll
  calendar period before preview or submission.
- All writes must use a durable `Idempotency-Key` no longer than 128 characters.
- Treat non-2xx HTTP responses and 2xx Xero semantic errors such as
  `ValidationException` as failures.

## Acceptance Criteria

- Xero timesheet API calls live behind `Application.Helper.Xero`.
- Submission state is stored in dedicated Xero submission tables, not
  `export_jobs`.
- Readiness validation blocks incomplete mappings, unsupported periods, stale
  source entries, and any existing Xero timesheet for the same employee/period
  until update support exists.
- Readiness validation hard-blocks mixed pay config snapshots.
- Preview builds deterministic Xero-shaped payloads from approved IHP entries.
- Submission creates only Xero `DRAFT` timesheets and persists request/response
  metadata for audit/debugging.

## Notes

**2026-04-30T00:18:32Z**

2026-04-30: Product decision: if Xero already has any timesheet for the same employee/period, block create until explicit update support exists.

**2026-04-30T00:22:26Z**

2026-04-30: Product decision: mixed pay-config snapshots are not allowed in a single Xero submission period.
