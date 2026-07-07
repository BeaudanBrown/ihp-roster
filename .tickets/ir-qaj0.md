---
id: ir-qaj0
status: open
deps: []
links: []
created: 2026-07-07T10:26:11Z
type: task
priority: 3
assignee: Beaudan Brown
parent: ir-qhas
tags: [frontend-contracts, overlay, typescript]
---
# Design OverlayAction DSL/IR and generated TypeScript manifests

Add the overlay/global contract root and OverlayAction IR, including method/target/swap/trigger/indicator/confirm/select/push-url/custom metadata and submitted fields. Generate TypeScript manifests/validators alongside existing frontend contracts.

## Design

Implement within the narrow OverlayAction lane. Do not broaden to arbitrary global navigation or lazy fragment loading. Preserve Haskell route construction and existing dialog response behavior.

## Acceptance Criteria

Focused typecheck/tests pass; migrated code uses generated overlay helpers/manifests; docs or guardrails are updated where relevant.

