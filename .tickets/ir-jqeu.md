---
id: ir-jqeu
status: open
deps: [ir-yznv]
links: []
created: 2026-04-29T04:45:43Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-5uzu
tags: [area:live-fragments, source:plans-62]
---
# Design server-side live surface definitions

Phase 4 from plans/62-live-fragment-system-refactor.md: define a richer server-side surface definition API that owns scope construction, auth requirements, default fragments, fragment construction, projection hooks, and active-scope fanout helpers.

## Acceptance Criteria

A small surface can broadcast via a surface definition instead of hand-built LiveFragmentRef values, with tests documenting the API.

