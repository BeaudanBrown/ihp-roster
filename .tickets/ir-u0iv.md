---
id: ir-u0iv
status: closed
deps: []
links: []
created: 2026-04-30T00:09:33Z
type: task
priority: 1
assignee: beaudan
parent: ir-176p
tags: [area:xero, area:payroll, source:plans-57, planning]
---
# Document Xero Payroll AU timesheet API contract

Capture the current official Xero Payroll AU API contract for pay item and timesheet endpoints in docs/archive/plans/57 and a focused implementation plan so future agents can implement without rediscovering endpoint shape. Include scopes, payloads, response envelopes, idempotency, duplicate detection, and known Xero semantic-error behavior.


## Notes

**2026-04-30T00:09:58Z**

2026-04-30: Reviewed official Xero Payroll AU OpenAPI for PayItems and Timesheets. Planning docs should cite /PayItems, /Timesheets, /Timesheets/{TimesheetID}, scopes, response envelopes, and Idempotency-Key behavior.
