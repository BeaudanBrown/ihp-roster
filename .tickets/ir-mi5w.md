---
id: ir-mi5w
status: open
deps: [ir-4ub1]
links: []
created: 2026-07-04T02:44:57Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-888o
tags: [agent-loop, surfaces, interaction, haskell]
---
# Implement FrontendSurface-aware interaction render helpers

Add the Haskell helper layer that renders interaction markers/forms/layers from generated FrontendSurface metadata instead of feature-local string wiring.

## Design

Use existing generated/reflected FrontendSurface interaction metadata where possible. Wrap current marker primitives behind typed helpers that take surface/intent/session/action references, mount ownership context, and strongly typed field names. Do not change browser protocol unless the spec ticket proves it necessary. Preserve current runtime behavior and generated TypeScript contracts.

## Acceptance Criteria

New helpers cover existing activation intent, pointer session, dropzone, disposable layer, and hidden intent form use cases; focused tests assert emitted markup and generated metadata integration; no LiveSurface compatibility types are introduced.

