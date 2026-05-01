---
id: ir-afos
status: closed
deps: [ir-rl1u, ir-z9jy, ir-73xk]
links: []
created: 2026-05-01T00:57:58Z
type: bug
priority: 1
assignee: beaudan
parent: ir-ujwc
tags: [area:xero, area:payroll, submission, readiness]
---
# Exclude different-calendar employees from Xero timesheet submission

Xero rejected draft timesheet creation because one mapped employee belonged to a different payroll calendar than the venue-selected calendar. The app should submit only employees assigned to the selected Xero payroll calendar and treat employees on other calendars as excluded warnings, not whole-run blockers.

## Design

Keep the current one-calendar submission model, but scope the payload to that calendar. For approved entries in the selected period, resolve verified staff mappings to synced xero_employees for the active connection. Employees with payroll_calendar_id equal to the selected xero_payroll_calendar_selections.xero_payroll_calendar_id are eligible for preview/submission. Employees with a different payroll_calendar_id are excluded from preview/submission and surfaced as readiness warnings. Employees missing from synced reference data or missing payroll_calendar_id remain blockers because the app cannot prove whether they belong in the selected calendar.

## Acceptance Criteria

Readiness warns, but does not block, when mapped employees are assigned to a different Xero payroll calendar than the selected calendar. Preview and submission exclude those employees and their timesheet entries from generated Xero payloads. Submission reruns readiness and still creates POST /Timesheets calls for eligible selected-calendar employees. Employees with no synced Xero payroll calendar remain blockers. Warning messages identify the exclusion. Focused Hspec coverage passes.

## Notes

**2026-05-01T02:34:53Z**

2026-05-01: Product decision reversed from hard-blocking different-calendar employees to selected-calendar filtering. Implemented readiness warning employee_payroll_calendar_excluded, scoped duplicate checks and preview/submission payloads to employees assigned to the selected payroll calendar, and kept missing employee payroll calendars as blockers. Verified with typecheck and focused Xero readiness/preview/submission Hspec.
