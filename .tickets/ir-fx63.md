---
id: ir-fx63
status: open
deps: [ir-aup5]
links: []
created: 2026-07-09T02:39:00Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, roster, automation]
---
# Update roster-timesheet automation dedupe and warnings

Make automation and roster warnings treat any active linked timesheet as materialised.

## Design

Adjust roster automation helpers and tests so the grace-period job skips when an active concrete timesheet is already linked to the roster slot, regardless of whether automation created it. Keep roster edit warnings for linked concrete timesheets and avoid mutating concrete entries after roster edits.

## Acceptance Criteria

Automation skips manually materialised linked entries. Roster edits after materialisation warn and do not mutate timesheets. Republish/live-draft lifecycle remains duplicate-safe. Existing roster automation coverage is updated.

