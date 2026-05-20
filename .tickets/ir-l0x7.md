---
id: ir-l0x7
status: closed
deps: [ir-mjos, ir-omzt, ir-szt9]
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

Carry selected `payrollCalendarId`, period start/end, payment date, and pay-run metadata from the preparation run into persisted preview and submit actions. Preview/submission must not recompute the period from today or from `xero_payroll_calendar_selections`. Validate that the selected period belongs to the selected/synced Xero payroll calendar before preview and again before submit.

Preserve duplicate checks and source entry/pay-version audit state. The persisted submission run should be traceable back to the preparation run/selected period and should include the readiness snapshot and duplicate-check snapshot used for preview/submission.

## Acceptance Criteria

Preview and submission operate on the selected Xero period, including historical periods returned by Xero, without relying on global calendar selection. Tampered/mismatched period or calendar params cannot preview or submit. Persisted preview/submission rows keep source entry/pay-version audit state and selected period metadata. Existing preview/submission tests cover explicit period selection, historical periods, and no-global-calendar behavior.

