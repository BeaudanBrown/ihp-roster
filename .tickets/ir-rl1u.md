---
id: ir-rl1u
status: open
deps: []
links: []
created: 2026-05-01T00:58:06Z
type: task
priority: 1
assignee: beaudan
parent: ir-afos
tags: [area:xero, area:payroll, readiness]
---
# Add employee payroll-calendar readiness blockers for Xero draft timesheets

Extend Application.Helper.XeroTimesheetReadiness so the selected payroll calendar is checked against every mapped Xero employee included in the approved timesheet period.

## Design

Fetch synced xero_employees for the active connection and mapped employee ids used by approvedSubmittableEntries. Add blocker codes for missing synced employee, missing employee payroll calendar, employee payroll calendar mismatch, and employee calendar period mismatch as needed. Use QueryBuilder and keep messages actionable. Preserve current behavior for connection/reference/calendar/entry/earnings/duplicate blockers.

## Acceptance Criteria

validateXeroTimesheetReadiness reports blockers before preview/submission for employees with missing or mismatched payroll calendars. Blockers carry affected staff id and Xero object id where available. Existing readiness tests still pass.

