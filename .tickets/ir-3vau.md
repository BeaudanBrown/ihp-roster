---
id: ir-3vau
status: open
deps: [ir-cvp3, ir-tp2e, ir-axdb, ir-p9kg]
links: []
created: 2026-04-30T00:09:34Z
type: feature
priority: 1
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, readiness]
---
# Build Xero draft-timesheet readiness validator

Build a deterministic readiness validator for the selected venue/pay period before preview or submission. It must check active connection/token refresh, successful reference sync, selected payroll calendar and exact period match, verified staff mappings, verified earnings/pay item mappings, managed pay item requirements matched or created, source entries approved/non-deleted/snapshot-pinned, no mixed snapshots, and no Xero timesheet already exists for employee/period until update support lands.

## Design

Follow the readiness validator section in
`plans/63-xero-timesheet-submission.md`.

The validator should produce structured blockers with stable codes, severity,
human message, affected local/Xero ids where available, and an action hint. It
must be shared by Admin Xero readiness, the future preview page, and the
submission action.

The first implementation should derive the pay period from the selected Xero
payroll calendar instead of assuming weekly periods. Weekly, fortnightly, or
other supported calendar periods should produce one `NumberOfUnits` value per
day in the selected period. The validator must prove the local period exactly
matches the period Xero expects for that selected payroll calendar.

## Acceptance Criteria

- Validator returns a single readiness result for venue plus selected period.
- Blockers cover connection, sync, payroll calendar, exact period mismatch,
  source entries, staff mapping, earnings/pay item mapping, managed pay item
  status, mixed snapshots, and remote duplicate timesheets.
- Existing Xero timesheets for the same employee/period block create until
  explicit update support exists.
- Focused tests cover every blocker plus at least weekly and fortnightly happy
  cases.

## Notes

**2026-04-30T00:18:32Z**

2026-04-30: Product decision: derive submission periods from the selected Xero payroll calendar instead of hard-coding weekly periods. NumberOfUnits should have one value per day in the selected period, e.g. 7 for weekly and 14 for fortnightly.

**2026-04-30T00:22:26Z**

2026-04-30: Product decision: readiness must prove the local period exactly matches the period Xero expects for the selected payroll calendar. Mixed pay-config snapshots are hard-blocked; new rates should only affect the first pay period starting after the new financial-year/effective date.
