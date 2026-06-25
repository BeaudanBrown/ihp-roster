---
id: ir-libm
status: closed
deps: []
links: []
created: 2026-06-25T01:39:18Z
type: task
priority: 2
assignee: beaudan
parent: ir-jsyd
tags: [agent-loop, haskell, interaction, live-fragments]
---
# Fold interaction capability into TypedLiveSurfaceDefinition

Move the interaction-capability slot from the temporary ir-fq28 wrapper shape into the canonical TypedLiveSurfaceDefinition so live fragments and interaction metadata share one surface origin before render helpers and runtime work build on it.

## Design

Add an explicit interaction capability field/type slot to TypedLiveSurfaceDefinition. Existing live surfaces should pass emptyInteractionCapability (or a compatibility alias/helper that expands to it). Keep the wrapper only as migration ergonomics if useful, not as a parallel registry for codegen/render helpers. Update type signatures, constructors, focused tests, and docs/comments so downstream ir-w50d helpers read interaction metadata from the surface definition itself.

## Acceptance Criteria

TypedLiveSurfaceDefinition carries the interaction capability directly; existing live surfaces compile with explicit empty capabilities; no separate wrapper registry is required for render helpers/codegen; typecheck and focused LiveSurface/Interaction tests pass.

