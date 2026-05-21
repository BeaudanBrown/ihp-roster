---
id: ir-7b4c
status: open
deps: []
links: []
created: 2026-05-21T03:35:20Z
type: bug
priority: 2
assignee: Beaudan Brown
parent: ir-asw6
tags: [agent-loop, roster, validation]
---
# Require shift type before publishing staffed shifts

Make shift type mandatory for every staffed roster slot when publishing, independent of end-times configuration.

## Design

Refactor validateRosterWeekCanGoLive so shift_type_id is always required for staffed shifts. Keep start time required. Require end time and positive duration only when venueConfig.rosterEndTimesEnabled is true. Keep the user-facing publish error concise; update wording only if needed to avoid implying end times are required when disabled.

## Acceptance Criteria

Publishing is blocked for any staffed shift missing shift type with end times enabled or disabled. End-time/duration publish blockers remain scoped to end-times-enabled venues. Focused RosterWeeks workflow tests cover both configurations.

