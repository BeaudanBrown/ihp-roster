---
id: ir-tj9u
status: open
deps: [ir-61x2]
links: []
created: 2026-06-26T07:25:29Z
type: feature
priority: 2
assignee: Beaudan Brown
parent: ir-ewlr
tags: [agent-loop, frontend, live-surfaces, registry, contracts]
---
# Reduce live surface descriptor manifest duplication

Continue ir-udbq by deriving more manifest fields from typed live surface definitions instead of manually listing strings.

## Design

Extend RegisteredLiveSurfaceDescriptor or TypedLiveSurfaceDefinition metadata so surface family, scope kinds, fragment kinds, interaction schema, authorization, and invalidation registration live in one descriptor where feasible. Add omission/regression tests for descriptor-to-manifest coverage. Preserve support for context-specialized definitions.

## Acceptance Criteria

Adding a surface has a single descriptor registration path for runtime and manifest coverage, or remaining manual fields are guarded by tests with clear rationale; LiveSurface and Frontend contract tests pass.

