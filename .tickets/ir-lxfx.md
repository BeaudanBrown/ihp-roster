---
id: ir-lxfx
status: closed
deps: [ir-tk23]
links: [ir-w8dk]
created: 2026-04-30T06:35:24Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-18tm
tags: [area:roster, area:timesheets, area:view, area:maintenance]
---
# Extract shared week navigation and path helpers for roster and timesheets

Reduce duplicated week URL and toolbar construction between roster and timesheet sections while preserving each feature specific filters and actions.

## Design

Add feature path helpers such as Web.RosterWeeks.Paths and refine Web.Timesheets.Paths so controllers and views do not duplicate appendQueryParams calls. Extract only genuinely shared week navigation/chrome helpers after verifying at least two callers. Link to the existing reusable week-controls ticket.

## Acceptance Criteria

Roster week path construction is defined once and reused by controller and view code; timesheet week paths keep showApproved and showAllStaff filters stable; shared week toolbar helpers avoid feature-specific assumptions; typecheck and focused navigation tests pass.
