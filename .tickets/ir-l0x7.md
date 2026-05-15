---
id: ir-l0x7
status: open
deps: [ir-mjos, ir-omzt]
links: []
created: 2026-05-08T04:22:38Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, preview]
---
# Wire explicit Xero pay period through preview and submission

Stop deriving draft-timesheet preview/submission from today's current payroll-calendar period only; use the user-selected Xero period from the preparation flow.

## Design

Carry selected payrollCalendarId, periodStart, periodEnd, and payRun metadata through prepare, readiness, persisted preview, and submit actions. Validate that the selected period belongs to the selected/synced Xero payroll calendar. Preserve duplicate checks and source entry/pay-version audit state.

## Acceptance Criteria

Preview and submission operate on the selected Xero period, including historical periods returned by Xero, and reject tampered/mismatched period params. Existing preview/submission tests cover explicit period selection.

