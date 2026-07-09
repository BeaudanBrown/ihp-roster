---
id: ir-bw8v
status: open
deps: []
links: [ir-9jap]
created: 2026-07-09T02:39:00Z
type: epic
priority: 1
assignee: Beaudan Brown
tags: [agent-loop, area:timesheets, area:roster, venue:rooks]
---
# Expected timesheets from live roster shifts

Show live roster shifts as expected/phantom timesheet cards and allow staff or managers to materialise them into concrete linked timesheets without duplicate automation rows.

## Design

Expected timesheets are read-model derived from complete live roster slots, not persisted proposed rows. Concrete timesheet_entries remain the only persisted timesheet records. Materialising an expected shift creates an unapproved concrete entry linked through source_roster_slot_id. One active non-deleted linked timesheet is allowed per roster slot. Staff see only their own expected shifts; managers/admins see expected shifts according to current timesheet filters. Live-to-draft-to-edit-to-live recomputes expected cards from current live roster state. Later roster edits do not mutate linked concrete timesheets.

## Acceptance Criteria

Timesheet pages show expected roster shifts with clear non-concrete styling; eligible expected shifts can be materialised into linked unapproved timesheets; manual materialisation and automation dedupe through the same roster-timesheet link; live/draft roster transitions do not create duplicate timesheets; docs and focused tests cover visibility, materialisation, duplicate prevention, and roster lifecycle behavior.

