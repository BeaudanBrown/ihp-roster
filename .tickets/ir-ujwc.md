---
id: ir-ujwc
status: open
deps: [ir-lgy7]
links: []
created: 2026-04-30T00:09:35Z
type: feature
priority: 1
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, submission]
---
# Submit draft Xero timesheets with audit trail

Submit previewed payloads as DRAFT Xero Payroll AU timesheets, one API call per employee/pay period. Persist request/response, idempotency key, returned TimesheetID, Xero status, source entry links, success/failure audit events, and retry state. Do not approve Xero timesheets or create pay runs in this slice.

## Design

Use `POST /Timesheets` with a singleton `array[Timesheet]` body and
`Status = DRAFT`. Generate and persist idempotency keys before the API call. A
retry must reuse the persisted key for the same intended request.

Run readiness again immediately before submission so stale previews cannot submit
changed source entries.
This repeat readiness check must verify the period still matches the selected
Xero payroll calendar and still uses one pay config snapshot.

## Acceptance Criteria

- Submissions persist request payload, response payload, idempotency key, Xero
  `TimesheetID`, Xero status, source entries, and audit events.
- Partial failures are visible per employee/pay period.
- Retry behavior is deterministic and debuggable.
- Any existing remote Xero timesheet for the same employee/period blocks create
  until update support exists.
- Mixed pay config snapshots block submission.
- No approved Xero timesheet or pay run is created by this feature.

## Notes

**2026-04-30T03:05:53Z**

2026-04-30: Submission should start only after preview persistence exists. Use the refactored OpenAPI contract/mock harness for concrete HTTP tests; rerun readiness and duplicate checks immediately before POST /Timesheets; persist request/response/idempotency/source-entry audit state. Child tasks: ir-tsvi, ir-yikx.

**2026-04-30T04:46:03Z**

2026-04-30: UI product decision for first slice: put preview/submission inside the existing Xero page; venue-owner only; preview table is one row per employee; show latest run only; show submission errors and a light retry affordance, but do not build full retry UX or a historical run list yet. Child task: ir-uxn9.
