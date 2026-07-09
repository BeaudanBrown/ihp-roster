---
id: ir-rlh2
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, time-picker, admin, roster, timesheets]
---
# Configure venue time-picker range

Allow venues to configure the range of hours shown by shared time pickers.

## Design

Add or reuse venue operational-day bounds to set shared time picker start/end attrs for roster and timesheet fields. Preserve 15-minute validation and overnight support. If existing hard-coded 06:00-05:45 bounds remain necessary for roster operational days, document the distinction.

## Acceptance Criteria

Venue admins can configure or clearly inherit the time-picker range. Roster/timesheet time pickers honor the range while server validation remains authoritative. Focused frontend/typecheck/tests pass.

