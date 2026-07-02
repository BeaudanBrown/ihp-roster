---
id: ir-4hu6
status: closed
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

## Notes

**2026-07-02T08:49:06Z**

Started the recommended marker-indexed compile-time SurfaceImpl completeness path. Runtime now has HandlerList plus SurfaceImplHandlers indexed by type-family-extracted scope, mount-state, fragment, HTMX action, and intent markers. Lab SurfaceImpl is built via mkSurfaceImpl with complete handlers, and focused DSL tests assert action/intent metadata comes from typed handler records. Added a negative compile fixture and Nix-owned frontend-surface-compile-fail-check command proving that omitting the LabPanel fragment handler fails compilation. Next decision point: whether to deepen handlers from marker-presence to typed param/scope/mount-state value conversion and URL/render signatures, or first integrate this compile-fail command into broader guardrail checks under ir-ycec.

**2026-07-02T09:00:29Z**

Deepened SurfaceImpl handlers from marker-only presence to type-indexed runtime requirements. HandlerList now carries filtered SurfacePrimitive requirements, so fragment/action/intent/scope/mount-state handlers are indexed by their declared field lists/options. Handlers now expose typed FrontendSurfaceFieldValues for default params/fields/state and typed functions for scope keying, mounted fragment URL/target building, fragment rendering, action request building, and intent form building. mkSurfaceImpl derives mount scope key/state/fragments plus action/intent metadata from handlers. Lab updated and compile-fail fixture still proves missing LabPanel handler fails. Next decision point: whether to add field-level typed codecs/accessors for FrontendSurfaceFieldValues or move this into ir-ycec guardrail integration before Timesheets.

**2026-07-02T09:11:50Z**

Added field-level typed accessors/codecs for SurfaceImpl handler values. FrontendSurfaceFieldValues fields now supports getSurfaceField/requireSurfaceField @Marker, with compile-time undeclared-field rejection, stable parse diagnostics, and closed wire parsing for Text/Int/Bool/UUID/Text Day/list/optional/nullable/ref. Lab handlers now use typed accessors for panel/action/intent fields. Expanded compile-fail guardrails to missing fragment, missing action, missing intent, and undeclared field accessor fixtures. Focused Hspec, typecheck, compile-fail check, frontend-contracts-check, and frontend-test pass.
