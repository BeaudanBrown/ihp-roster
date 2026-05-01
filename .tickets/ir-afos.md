---
id: ir-afos
status: open
deps: [ir-rl1u, ir-z9jy, ir-73xk]
links: []
created: 2026-05-01T00:57:58Z
type: bug
priority: 1
assignee: beaudan
parent: ir-ujwc
tags: [area:xero, area:payroll, submission, readiness]
---
# Block Xero timesheet submission when employee payroll calendar does not match selected calendar

Xero rejected draft timesheet creation because one mapped employee had no pay run calendar and another employee's selected period did not match their Xero payroll calendar. The app currently derives one period from the venue-selected payroll calendar but does not validate each mapped Xero employee's payroll_calendar_id before preview/submission.

## Design

Keep the current one-calendar submission model. For approved entries in the selected period, resolve verified staff mappings to synced xero_employees for the active connection. Readiness should block when the mapped Xero employee is missing, has NULL payroll_calendar_id, has a payroll_calendar_id different from the selected xero_payroll_calendar_selections.xero_payroll_calendar_id, or has a calendar whose derived period does not equal the selected readiness period. Do not submit mixed-calendar employees in this slice.

## Acceptance Criteria

Readiness blocks mapped employees with no synced Xero payroll calendar. Readiness blocks mapped employees assigned to a different Xero payroll calendar than the selected calendar. Submission reruns readiness and creates no POST /Timesheets calls when these blockers exist. Blocker messages identify the affected staff/employee and action needed. Focused Hspec coverage passes.

