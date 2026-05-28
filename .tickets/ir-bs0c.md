---
id: ir-bs0c
status: closed
deps: [ir-93pf]
links: []
created: 2026-05-28T05:42:04Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-kjc9
tags: [area:roster, area:validation, agent-loop]
---
# Enforce roster slot timing rules in save and publish flows

Use the shared day-window helper to prevent invalid roster slot times from being saved or published silently.

## Design

Apply the 06:00-05:45 operational-day semantics to roster slot create/update paths and publish validation. Invalid timing should produce a controlled HTMX toast/rerender or normal redirect error, not a bad duration saved to the database. Publishing must block staffed slots whose start/end times do not form a valid shift when end times are enabled. Preserve valid overnight shifts such as late-night close shifts.

## Acceptance Criteria

Invalid start/end combinations are rejected or block publish with a clear error; valid overnight shifts still work; roster slot duration is consistent with the shared helper; Hspec covers create/update and go-live validation edge cases.

