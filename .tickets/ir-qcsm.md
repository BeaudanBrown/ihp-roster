---
id: ir-qcsm
status: open
deps: []
links: []
created: 2026-05-22T01:41:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-gd3q
tags: [area:roster, area:timesheets, area:async, agent-loop]
---
# Implement roster timesheet job cancellation on draft rollback

Cancel stale roster_timesheet_creation jobs when a roster week is moved from live back to draft.

## Design

Add cancelPendingRosterTimesheetCreationJobsForWeek in Application/RosterTimesheets/Automation.hs. It should find roster slot ids for the target week, update matching roster_timesheet_creation app_jobs with related_table = roster_slots, related_id in those slots, and status in not_started/retry to JobStatusSucceeded with a cancellation result. Call it from toggleRosterWeekLiveStatusMutation when nextLiveStatus is False. Preserve the existing worker live-state guard for races.

## Acceptance Criteria

Live-to-draft transition cancels not_started/retry roster timesheet jobs for the week; succeeded/failed/running jobs are left alone; generated timesheets are not deleted or changed; no schema migration or generic job cancellation lifecycle is introduced.

