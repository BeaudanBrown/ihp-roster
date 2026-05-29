---
id: ir-uu3x
status: open
deps: [ir-7rif]
links: []
created: 2026-05-29T03:16:10Z
type: task
priority: 2
assignee: beaudan
parent: ir-kuyy
tags: [agent-loop, roster, row-day]
---
# Migrate roster row and day actor patch responses

Convert high-frequency row/day actor updates to the shared helper without broadening their DOM blast radius.

## Design

Replace bespoke respondWithRosterPatches row/day rendering with shared fragment responses for RosterProjectionRow and RosterProjectionDaySection; keep staff panel refresh as an optional fragment in the same response.

## Acceptance Criteria

Row/day mutations return OOB declared fragments; no full content swap for row-only edits; row/day Hspec and relevant Playwright coverage pass.

