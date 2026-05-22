---
id: ir-i3tv
status: closed
deps: [ir-qcsm]
links: []
created: 2026-05-22T01:41:01Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-gd3q
tags: [area:test, area:roster, area:timesheets, agent-loop]
---
# Cover roster timesheet job cancellation state transitions

Add focused Hspec coverage for roster timesheet job cancellation, republish rescheduling, and generated-timesheet preservation.

## Design

Extend RosterTimesheetsAutomation and/or RosterWeeks controller specs. Assert cancellation result JSON, active dedupe release after cancellation, recalculated runAt after live -> draft -> slot edit -> live, and that already generated timesheet entries remain unchanged when a roster returns to draft.

## Acceptance Criteria

Focused tests cover live-to-draft cancellation, retry/not_started targeting, republish with recalculated runAt after draft edits, and generated-timesheet preservation. Tests pass with hspec-test matches for Roster timesheet automation and RosterWeeksController.


## Notes

**2026-05-22T02:47:04Z**

HANDOFF: Added RosterWeeks controller coverage for live-to-draft cancellation of not_started/retry roster_timesheet_creation jobs while leaving running jobs alone, plus draft edit -> republish coverage proving dedupe release, recalculated runAt, and generated timesheet preservation; tests run: bash ./bin/in-env hspec-test --match "Roster timesheet" --match "RosterWeeksController" (pass); remaining risks: full suite not run.
