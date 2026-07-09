---
id: ir-7np6
status: open
deps: []
links: []
created: 2026-07-09T02:39:01Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-z20h
tags: [agent-loop, ui, shift-types]
---
# Check Mac colour picker behavior

Investigate the shift-type colour picker issue reported on Macs.

## Design

Review current shift-type colour control implementation and test on/for macOS behavior where possible. Prefer app-owned palette controls over native color input quirks if relevant. If unreproducible, document limitation and ask for reproduction details.

## Acceptance Criteria

Mac colour picker issue is fixed if reproduced as app-side, or documented with reproduction needs/follow-up. Existing shift-type colour behavior and tests remain valid.

