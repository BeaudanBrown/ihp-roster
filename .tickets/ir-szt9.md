---
id: ir-szt9
status: open
deps: [ir-omzt, ir-9gkd]
links: []
created: 2026-05-19T04:20:51Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, calendar, backend]
---
# Make selected Xero period calendar authoritative

Remove the modal submission dependency on the venue-global Xero payroll-calendar selection. The selected Xero period option already carries payroll calendar id/name and period dates, so preparation, readiness, preview, and submission should use that selected calendar/window as the source of truth.

## Design

Thread selected `payrollCalendarId`, calendar name, `periodStart`, `periodEnd`, payment date, and pay-run metadata through `XeroTimesheetReadinessRequest`, preview input, duplicate checks, and submission. Readiness should load the selected synced `XeroPayrollCalendar` by id from the preparation run/selected period instead of `fetchVerifiedPayrollCalendarSelection`. Preview employee filtering should use employees whose synced Xero `payrollCalendarId` matches the run-selected calendar, not `xero_payroll_calendar_selections`.

Reject inconsistent state early: selected period key, selected calendar id, stored run calendar id, synced payroll calendar, and period dates must agree. If the selected calendar cannot derive/validate the selected dates, show a blocker. Employees mapped to synced Xero employees on other calendars are excluded with a warning. Mapped employees with no synced employee record or no payroll calendar remain blockers because Xero source-of-truth data is missing.

Keep the old global selection only for legacy/admin defaults until all modal paths no longer reference it. Do not remove `xero_payroll_calendar_selections` in this ticket unless code search proves it is unused outside the modal; if still used, create a follow-up cleanup ticket.

## Acceptance Criteria

Preparing from a dropdown period works without any `xero_payroll_calendar_selections` row. Readiness/preview/submission use the selected period calendar and reject tampered/mismatched period-calendar state. Employees on other synced Xero payroll calendars are excluded with a clear warning, not treated as user-assigned local state. Missing synced employee/calendar data remains actionable as a blocker. Tests cover no global calendar selection, weekly/fortnightly selected windows, selected-calendar employee filtering, and tamper/mismatch rejection.

