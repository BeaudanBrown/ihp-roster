---
id: ir-44kr
status: open
deps: [ir-fx63]
links: []
created: 2026-07-09T02:39:00Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-bw8v
tags: [agent-loop, timesheets, docs, tests]
---
# Document and verify expected timesheets

Update living docs and add end-to-end verification for expected timesheets.

## Design

Update Web/Timesheets/SPEC.md, Web/RosterWeeks/SPEC.md, and docs/workstreams/rooks-pilot.md with the expected-timesheet contract and non-goals. Add focused Hspec for visibility, materialisation, live/draft transitions, duplicate prevention, and automation dedupe. Add E2E only if needed for browser-only UX behavior.

## Acceptance Criteria

Living docs describe expected vs concrete timesheets, linking, materialisation, and roster lifecycle behavior. Focused Timesheets/RosterWeeks/RosterTimesheetsAutomation tests pass. Any deferred E2E rationale is noted.

