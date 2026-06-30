---
id: ir-asoq
status: open
deps: [ir-amxj]
links: []
created: 2026-06-30T11:03:28Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-z0j1
tags: [architecture, bepis-actions, agent-loop]
---
# Add final Bepis architecture test suite

Add tests that lock the final operation/evidence model and prevent reintroduction of legacy metadata.

## Design

Add pure/unit tests for evidence-producing helpers where possible, focused controller tests for representative paths, generated contract JSON shape tests, no-legacy token tests, and at least one OTel trace check plan for final evidence attrs.

## Acceptance Criteria

Tests fail if BepisMutationSpec or descriptive evidence components return, if contract generation drifts, or if representative effects do not produce evidence.

