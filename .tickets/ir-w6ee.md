---
id: ir-w6ee
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
# Expand Bepis response fact helper coverage

Inventory and standardize response fact helpers for common response shapes.

## Design

Prefer small helpers around response boundaries; avoid noisy controller rewrites.

## Acceptance Criteria

Common response helpers emit actual response facts and focused tests pass.

