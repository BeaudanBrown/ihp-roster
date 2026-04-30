---
id: ir-f09l
status: open
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

