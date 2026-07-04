---
id: ir-7jqj
status: open
deps: []
links: []
created: 2026-07-04T01:20:55Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, surfaces, frontend-surface, cleanup]
---
# Finish clean generated FrontendSurface architecture

Remove all remaining legacy LiveSurface compatibility concepts and make production live/update surfaces use the generated FrontendSurface type path universally.

## Design

Final architecture has type-level FrontendSurface specs, SurfaceImpl runtime handlers, generated mount/subscription parsing, SurfaceResourceValue mutation touches, and generated dependency planning as the only production path. Delete TypedLiveSurfaceDefinition/LiveSurfaceConfig/data-live-update-surface compatibility authoring, feature-local dependency mirrors, stale docs/tests, and old names once no longer needed. Prefer clean final names over compatibility or churn minimization.

## Acceptance Criteria

Production code has no legacy typed-live-surface authoring/shims/stale resource dependency mirrors; actor and passive invalidation use generated FrontendSurface dependency metadata; docs/tests/guardrails describe and enforce the final architecture; agreed verification passes.

