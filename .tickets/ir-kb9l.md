---
id: ir-kb9l
status: closed
deps: [ir-tarj]
links: []
created: 2026-07-03T02:45:01Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-rjfp
tags: [agent-loop, frontend, surfaces, contracts]
---
# Generate contained-surface topology contracts

Expose contained-surface topology in generated TypeScript contracts for tooling, tests, and diagrams.

## Design

Extend TypeScript generation with parent surface, parent fragment, and child surface topology entries. Add Hspec/frontend contract tests that consume the generated topology.

## Acceptance Criteria

frontend/ts/generated/contracts.ts includes topology for ContainsSurface edges; generated types/guards/constants are usable by runtime/tests; frontend-contracts-check passes.

