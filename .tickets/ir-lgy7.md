---
id: ir-lgy7
status: open
deps: [ir-3vau]
links: []
created: 2026-04-30T00:09:35Z
type: feature
priority: 1
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, preview]
---
# Build Xero-shaped timesheet preview payloads

Transform approved IHP timesheets into deterministic Xero Payroll AU payloads after readiness passes. Reuse the approved payroll/pay-result pipeline, derive stable local bucket keys, group one timesheet per employee/pay period, group lines by EarningsRateID, and produce one NumberOfUnits value per day ordered from StartDate through EndDate.

## Design

Do not group by CSV display name. Build the Xero local bucket key from the same
classification, employment basis, effective date, and condition facts used by
managed pay item requirements.

For the first version, derive the period from the selected Xero payroll calendar
and emit one unit per day in that period. Omit `TrackingItemID`; Xero tracking is
only needed later if a client wants payroll cost-centre/category reporting.
Preview must use the exact period that Xero expects for the selected payroll
calendar, not an arbitrary local date range.

## Acceptance Criteria

- Preview is deterministic without calling Xero.
- Preview creates one payload per Xero employee and selected payroll-calendar
  period.
- Lines group by `EarningsRateID`.
- Source timesheet entry ids and pay snapshot versions are preserved in preview
  metadata.
- Tests prove daily unit ordering from period start through period end.
- Tests prove the preview period is the selected Xero payroll-calendar period.

## Notes

**2026-04-30T00:18:32Z**

2026-04-30: Product decision: omit TrackingItemID in v1. Xero tracking categories are optional cost-centre/reporting metadata and are not needed for first draft-timesheet submission.

**2026-04-30T00:22:26Z**

2026-04-30: Product decision: preview period must come from the selected Xero payroll calendar and match Xero's expected period exactly.

**2026-04-30T03:05:53Z**

2026-04-30: Next chunk scoped after the OpenAPI refactor. Implement preview as a deterministic builder plus persisted preview run, using the selected Xero payroll calendar period, readiness-approved entries, verified staff/earnings mappings, and no Xero HTTP calls. Child tasks: ir-f09l, ir-4jzo, ir-1urs.
