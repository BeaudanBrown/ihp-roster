---
id: ir-81wq
status: closed
deps: []
links: []
created: 2026-07-03T04:17:38Z
type: task
priority: 1
assignee: Beaudan Brown
parent: ir-7huc
tags: [agent-loop, surfaces, dsl]
---
# Lock FrontendSurface DSL primitive model

## Design

Consolidate the DSL around the long-term primitive set. Add Live as a fragment option. Rename HtmxAction to Action and ClientEvent to Event. Remove/demote top-level LoadPolicy, OverlayLane, DisposableLayer, and InteractionEffect into scoped options where still needed. Prefer owner-specific option kinds over one universal option bag where feasible. Update GHC lowering, reflection, ContractIR, TypeScript generation, and tests.

## Acceptance Criteria

Existing surfaces compile under the new DSL. Generated contracts preserve current relevant metadata. Invalid option/reference use is covered by focused tests or compile-fail tests. Removed top-level primitives are not used in production specs.

