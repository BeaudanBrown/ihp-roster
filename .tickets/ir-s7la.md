---
id: ir-s7la
status: open
deps: [ir-ypt5, ir-ds06, ir-ycec]
links: []
created: 2026-07-02T04:06:39Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces, cleanup]
---
# Remove replaced FrontendCodec and old live-surface contract paths

After lab, Timesheets, and Roster prove replacement coverage, remove old surface-related `FrontendCodec`/schema registry, `TypedLiveSurfaceDefinition` authoring, `Web.LiveSurfaceRegistry` catalog, and `Application.Helper.SurfaceProjection` usage from migrated surfaces.

## Design

- Final target keeps only renderer internals fed by `SurfaceContractIR` and runtime internals needed behind `SurfaceImpl`.
- Remove compatibility paths after all migrated surfaces use `RegisteredFrontendSurfaces` and `SurfaceImpl`.
- Old non-surface/global app contracts may remain only if explicitly out of scope, and legacy live surfaces may keep old paths during hybrid migration. Surface/live/interaction contracts for lab, Timesheets, and Roster must be new-architecture-owned. The eventual final target is full unification with no legacy live paths.
- Guardrails should prevent new surface work from reintroducing old authoring paths.

## Acceptance Criteria

- No migrated surface uses old `FrontendCodec` DTO/schema groups, `TypedLiveSurfaceDefinition` authoring, `Web.LiveSurfaceRegistry` catalog entries, or `Application.Helper.SurfaceProjection`.
- Replaced old DTO/schema modules and registry branches for migrated surfaces are deleted or reduced to internal compatibility-free renderer/runtime code; unrelated legacy surfaces can remain until their own migration.
- Generated `frontend/ts/generated/contracts.ts` surface/live/interaction sections originate from `RegisteredFrontendSurfaces`.
- Guardrails and docs reflect the final state.
