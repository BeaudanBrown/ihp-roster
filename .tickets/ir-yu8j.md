---
id: ir-yu8j
status: open
deps: [ir-3cky]
links: []
created: 2026-06-30T13:02:20Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-pqis
tags: [architecture, bepis-actions, agent-loop]
---
# Expand Bepis scope fact coverage

Emit scope facts from remaining important access helpers where successful checks authorize requests.

## Design

Add facts to existing helpers instead of adding call-site metadata.

## Acceptance Criteria

Scope helper success/failure tests pass and no controller metadata is added.

