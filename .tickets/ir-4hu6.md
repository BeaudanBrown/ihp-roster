---
id: ir-4hu6
status: open
deps: [ir-ennr]
links: []
created: 2026-07-02T02:47:03Z
type: task
priority: 2
assignee: Beaudan Brown
parent: ir-9ogo
tags: [agent-loop, frontend, surfaces]
---
# Prove typed SurfaceImpl completeness

Design and implement typed `SurfaceImpl` builders/handler records that replace feature-facing `TypedLiveSurfaceDefinition` authoring and require handlers for declared runtime behavior.

## Design

- `SurfaceImpl spec` is the runtime bridge for a type-level `FrontendSurface` spec and is exposed through a `HasSurfaceImpl spec`-style instance/value so runtime enumeration can be derived from `RegisteredFrontendSurfaces`.
- Compile-time completeness should require handlers/builders for every declared dynamic requirement where practical:
  - scope value/wire conversion and scope keying;
  - authorization;
  - version/freshness;
  - mount-local fragment target id, URL, render handler, load policy runtime values if any;
  - concrete live-resource dependency resolver;
  - HTMX action method/action/target/swap/form metadata;
  - intent form binding and field contracts;
  - mount key/metadata and mount-state backend hooks. Controllers remain mutation entrypoints for this epic; `SurfaceImpl` does not own generic intent dispatch yet.
- Parametrized fragments/actions require one typed handler per fragment/action marker, accepting typed params, not one handler per concrete value.
- Runtime semantic correctness remains covered by Hspec/E2E, but missing required handlers should fail compilation.
- Add or prepare a focused negative compile-fixture strategy with stable error expectations. Full guardrail command integration can be finalized in `ir-ycec`.
- First implementation supports direct DB/read-model rendering only. Do not make `Application.Helper.SurfaceProjection` part of the `SurfaceImpl` core.

## Acceptance Criteria

- A complete lab `SurfaceImpl SurfaceLabSurface` compiles and mounts via the strengthened builder/handler records.
- A fixture missing a required fragment/action/intent handler fails the focused compile/check path with a stable diagnostic.
- Handler records/builders prove completeness for parameterized fragments and direct runtime dependencies.
- No feature-facing `TypedLiveSurfaceDefinition` authoring is required for the lab path.
