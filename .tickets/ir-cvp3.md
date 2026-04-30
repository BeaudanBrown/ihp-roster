---
id: ir-cvp3
status: closed
deps: [ir-shsr]
links: []
created: 2026-04-30T00:09:34Z
type: feature
priority: 1
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, api]
---
# Add Xero timesheet API client boundary

Extend Application.Helper.Xero with typed Payroll AU timesheet read/create/update support. Add response parsers for Timesheets and TimesheetObject envelopes, include raw response payloads for audit, support GET /Timesheets with where/order/page for duplicate detection, POST /Timesheets for draft create, and POST /Timesheets/{TimesheetID} for draft update. Writes must require caller-provided durable idempotency keys.

## Design

Follow `plans/63-xero-timesheet-submission.md`.

Add typed refs for Xero timesheets and lines while preserving raw JSON on each
record. Parse Xero dates from ISO `YYYY-MM-DD` and Microsoft JSON `/Date(...)`
formats. Add query support for `If-Modified-Since`, `where`, `order`, and
`page`, with URL encoding handled inside the helper.

Expected client additions:

- `fetchTimesheets`
- `fetchTimesheet`
- `createTimesheet`
- `updateTimesheet`

## Acceptance Criteria

- `Application.Helper.Xero` can read, create, and update Payroll AU timesheets
  through the same mocked-client boundary used by the existing Xero tests.
- Response envelopes for `Timesheets` and `Timesheet` parse correctly.
- HTTP errors and Xero semantic errors remain debuggable.
- Unit tests cover GET list, GET single, POST create, POST update, and error
  parsing.

## Notes

**2026-04-30T00:40:46Z**

2026-04-30: Implemented Xero draft-timesheet foundation slice through readiness validation. Added Payroll AU Timesheets client support, submission persistence tables/types/schema checks, structured readiness blockers/validator, employee-period duplicate detection, and Admin Xero readiness checklist alignment. Verified with regen-types, typecheck, and focused Xero/Schema Hspec.
