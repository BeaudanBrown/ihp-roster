---
id: ir-f09l
status: closed
deps: []
links: []
created: 2026-04-30T03:05:46Z
type: task
priority: 1
assignee: beaudan
parent: ir-lgy7
---
# Define Xero timesheet preview payload types and builder

Add the preview-domain types and deterministic builder for Xero Payroll AU timesheet payloads. The builder should consume readiness-approved period/source data, verified staff mappings, verified earnings mappings, and approved snapshot-pinned timesheet entries; produce one preview per Xero employee/period; group lines by EarningsRateID; emit NumberOfUnits in period-day order; omit TrackingItemID; and preserve source entry/pay snapshot metadata. No Xero HTTP calls or UI in this task.


## Notes

**2026-04-30T03:18:52Z**

Started preview payload types/builder slice. Scope: deterministic Xero-shaped timesheet preview generation only; no Xero HTTP calls or UI.

**2026-04-30T03:21:02Z**

Implemented Application.Xero.Timesheets.Preview with deterministic payload/domain types, local bucket key derivation from award/pay facts, Xero request-object JSON without TrackingItemID, and a no-HTTP persistence helper. typecheck passed after implementation.
