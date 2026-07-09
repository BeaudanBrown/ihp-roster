---
id: ir-k0wt
status: open
deps: [ir-xnrz]
links: []
created: 2026-07-09T02:39:00Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, roster]
---
# Add expected-timesheet read model

Extend the timesheet week projection with expected shifts derived from live roster slots.

## Design

Load complete linked-active-staff roster slots for live roster weeks in the viewed timesheet week. Exclude roster slots with an active linked concrete timesheet. Respect current staff/manager visibility, showAllStaff, and selected staff filters. Keep expected entries as a separate render model rather than fake TimesheetEntry records.

## Acceptance Criteria

Projection returns expected shifts for eligible live roster slots, hides them for draft/unpublished weeks, excludes already-materialised slots, and applies staff/manager filter rules. Focused Hspec covers these cases.

