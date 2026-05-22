---
id: ir-gd3q
status: closed
deps: []
links: [ir-7xks]
created: 2026-05-22T01:41:01Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [area:roster, area:timesheets, area:async, agent-loop]
---
# Cancel stale roster timesheet jobs on draft rollback

When an auto-timesheet-enabled roster week is moved from live back to draft, pending roster-timesheet jobs for that week should stop blocking fresh scheduling. Re-publishing should enqueue new jobs from current roster slot state and recalculated run times.

## Design

Add feature-local cancellation for roster_timesheet_creation app jobs. On live-to-draft transition, mark not_started and retry roster timesheet jobs for slots in the week as JobStatusSucceeded with result {status: cancelled, reason: roster_week_moved_to_draft}. Leave running jobs to the worker's existing live-state safety check. Do not delete jobs or mutate already generated timesheets.

## Acceptance Criteria

Moving a live roster week back to draft cancels pending/retry roster-timesheet jobs for that week; running jobs are not force-cancelled; republishing after draft edits creates fresh jobs with recalculated runAt; existing generated timesheets remain unchanged; focused Hspec and docs cover the state transitions.


## Notes

**2026-05-22T02:40:06Z**

HANDOFF from ir-qcsm: Cancellation helper now exists and is wired into roster week live-to-draft mutation; ir-i3tv can focus on controller/state-transition coverage including republish recalculated jobs, while ir-jh3g can document result {status: cancelled, reason: roster_week_moved_to_draft}.

**2026-05-22T02:49:03Z**

HANDOFF from ir-jh3g: Final child ticket closed after documenting roster-timesheet draft-rollback cancellation semantics in roster and timesheet living specs. Epic acceptance appears covered by implementation, focused Hspec from sibling tickets, and docs; doc-drift-check currently fails on unrelated AGENTS.md navigation text mismatch.

**2026-05-22T02:49:26Z**

All descendant tickets are closed; closing epic after ir-jh3g.
