---
id: ir-7xks
status: closed
deps: [ir-rob3]
links: []
created: 2026-05-02T01:12:10Z
type: feature
priority: 1
assignee: Beaudan Brown
parent: ir-9jap
tags: [area:timesheets, area:roster, area:pilot, venue:rooks]
---
# Auto-create pending timesheets from live rosters

## Design

Add venue opt-in automation that creates pending timesheets from live roster shifts 2 hours after the actual shift end datetime. Only live rosters participate. Auto-created timesheets copy roster staff, date/time, and shift type. Later roster edits do not mutate existing timesheets; surface a warning/toast instead.

Workstream: `docs/workstreams/rooks-pilot.md`

## Acceptance Criteria

Venue-level opt-in controls automation; only live roster staffed shifts create timesheets; creation waits until 2 hours after actual end datetime including overnight shifts; created entries are pending and not approved; repeated jobs are idempotent; later roster edits leave existing timesheets unchanged and notify the actor with a warning/toast.

## Notes

**2026-05-02T08:10:24Z**

2026-05-02: Implemented venue opt-in auto-created pending timesheets from live complete roster slots. Added venue_config.auto_timesheet_creation_enabled, timesheet_entries.source_roster_slot_id, delayed app_jobs dispatch, idempotent performer, publish-time queueing, and a roster-edit warning when a generated timesheet already exists. Verified with regen-types, typecheck, make db, focused Hspec, seed-dev app, and UI screenshot coverage.
