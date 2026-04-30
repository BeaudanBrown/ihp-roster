---
id: ir-2hwu
status: open
deps: [ir-ujwc]
links: []
created: 2026-04-30T00:09:35Z
type: feature
priority: 2
assignee: beaudan
parent: ir-tfed
tags: [area:xero, area:payroll, corrections]
---
# Define Xero draft update and correction workflow

After draft creation is stable, define and implement correction handling. Mark submissions stale when source entries change after submission, allow explicit update only when the Xero timesheet is still DRAFT, and block automatic mutation once Xero has approved or processed the timesheet.

## Design

Use `GET /Timesheets/{TimesheetID}` before any update and require remote
`Status == DRAFT`. Use `POST /Timesheets/{TimesheetID}` only for explicit manager
updates. Never silently mutate a submitted payroll period.

## Acceptance Criteria

- Submitted runs become stale when included source entries are edited,
  unapproved, or soft-deleted.
- Draft remote timesheets can be updated only through explicit user action.
- Approved/processed remote timesheets block automatic update and show a manual
  correction requirement.
- Previous request/response payloads remain preserved.
