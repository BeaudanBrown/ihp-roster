---
id: ir-73xk
status: open
deps: []
links: []
created: 2026-05-01T00:58:11Z
type: task
priority: 1
assignee: beaudan
parent: ir-afos
tags: [area:xero, area:payroll, tests]
---
# Cover Xero employee calendar readiness and blocked submission paths

Add focused Hspec coverage for employee payroll-calendar readiness blockers and for submission stopping before Xero create calls when readiness fails.

## Design

Add tests in Test/XeroTimesheetReadinessSpec for no employee payroll_calendar_id and selected-calendar mismatch. Add a submission/service test in Test/XeroTimesheetSubmissionSpec using a mock XeroClient that would fail if createTimesheet is called, proving readiness blocks before POST /Timesheets. Add or update reference sync coverage to assert PayrollCalendarID from Xero employees is persisted to xero_employees.payroll_calendar_id.

## Acceptance Criteria

Focused hspec-test for XeroTimesheetReadiness and XeroTimesheetSubmission passes. Tests fail on current behavior before the readiness implementation. No network calls are required.

