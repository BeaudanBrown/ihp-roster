---
id: ir-9mz7
status: closed
deps: [ir-nlv5]
links: []
created: 2026-06-15T23:44:59Z
type: feature
priority: 1
assignee: beaudan
parent: ir-brfx
tags: [agent-loop, area:staff, area:timesheets, area:roster, launch]
---
# Block trial staff from timesheets and roster automation

Ensure trial staff remain roster-only by excluding them from manual timesheet assignment and roster-to-timesheet automation.

## Design

Timesheet form/query paths should use linked active staff only. Harden ensureStaffAssignmentAllowed or the equivalent validation path so a tampered create/update request with a trial staff id fails safely. Update roster_timesheet_creation enqueue/perform logic so complete slots assigned to trial staff are ignored and do not produce entries or user-facing publish blockers. Prefer avoiding job creation for trial slots where practical; otherwise execution-time skip is acceptable if idempotent and quiet.

## Acceptance Criteria

Trial staff do not appear in timesheet create/edit staff selectors or manager staff filters. Tampered timesheet create/update with trial staff is rejected safely. Publishing an auto-timesheet-enabled roster with trial staff succeeds. Auto-timesheet automation creates entries only for linked staff slots and no trial-staff timesheet entry is created. Focused Timesheets and RosterTimesheetsAutomation tests pass.


## Notes

**2026-06-16T00:05:07Z**

Excluded trial staff from timesheet form/filter staff sets, hardened timesheet staff assignment validation to linked active staff, and skipped trial staff in roster-to-timesheet enqueue and execution paths. Focused TimesheetsController/Roster timesheet automation Hspec and typecheck pass.
