---
id: ir-jxle
status: open
deps: []
links: []
created: 2026-07-09T10:10:25Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rlh2
tags: [agent-loop, time-picker, schema, roster, timesheets]
---
# Add venue time-picker config schema and helpers

Add venue_config fields and shared helpers for the venue-wide roster/timesheet picker window and default shift times.

## Design

Add live-safe venue_config start/end fields defaulting to 06:00 and 05:45. Store values as quarter-hour minute-of-day integers or equivalent parser-safe representation. Add helpers for HH:MM formatting/parsing, quarter-hour validation, overnight window duration, 8-hour default end clamped to the configured end, and in-window option checks.

## Acceptance Criteria

Existing venues inherit 06:00 to 05:45. Schema and migration are present. Generated types are updated. Time helper tests cover overnight windows, short-window clamping, invalid values, and formatting.

