---
id: ir-n8ep
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
# Clarify Bepis audit fact semantics

Decide and enforce whether specialized audit helpers emit generic plus specialized facts or one canonical fact.

## Design

Prefer simple singular facts unless consumers need hierarchy.

## Acceptance Criteria

Audit fact tests document the chosen semantics.

