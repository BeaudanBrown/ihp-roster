---
id: ir-8usq
status: closed
deps: [ir-omzt, ir-mjos, ir-szt9]
links: []
created: 2026-05-08T04:22:39Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9u78
tags: [area:xero, area:payroll, readiness]
---
# Apply Xero period and duplicate blockers in preparation flow

Harden readiness/preparation around Xero pay-run status and existing remote timesheets.

## Design

Hard-block periods whose selected Xero pay run is POSTED. For v1, block any existing remote Xero timesheet for the same included employee and selected period, regardless of draft/approved status, until explicit update support lands. Duplicate checks must use the selected period/calendar from the preparation run, after excluding staff whose mapped Xero employee belongs to another synced payroll calendar.

Surface clear modal blockers/events and keep pay-run/duplicate snapshots on preparation/submission records. Different-calendar employee exclusions are warnings, not duplicate blockers. Missing synced employee/calendar data remains a blocker because duplicate/inclusion checks cannot be trusted.

## Acceptance Criteria

Posted pay runs cannot reach preview. Existing remote employee-period timesheets for included selected-calendar employees prevent create and are visible in modal blockers. Different-calendar employees are excluded with warnings before duplicate matching. Preparation/submission records keep duplicate/pay-run snapshots. Tests cover posted pay-run, existing-timesheet, different-calendar exclusion, and missing-calendar-data blocker paths.


## Notes

**2026-05-20T00:33:06Z**

Verified existing preparation/readiness implementation against selected-period pay-run and duplicate blockers; added focused Hspec coverage for preparation duplicate snapshots and different-calendar duplicate exclusion.
