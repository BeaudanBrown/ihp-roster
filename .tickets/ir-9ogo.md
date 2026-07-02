---
id: ir-9ogo
status: closed
deps: []
links: []
created: 2026-07-02T02:47:03Z
type: epic
priority: 2
assignee: Beaudan Brown
tags: [agent-loop, frontend, surfaces, architecture]
---
# Type-level FrontendSurface contract generator

Replace the current ad hoc/generic frontend contract and live-surface authoring pipeline with a type-level `FrontendSurface` architecture extracted by the GHC API. Static frontend protocol facts live in declarative surface specs. Runtime implementations supply dynamic scope values, mount state, rendering, mount-local URLs/targets, authorization, versions, dependencies, and action metadata through `SurfaceImpl`.

## Design

Locked planning decisions:

- The root source of truth stays a single explicit surface registry:

  ```haskell
  type RegisteredFrontendSurfaces =
      '[ SurfaceLabSurface
       , TimesheetsSurface
       , RosterSurface
       ]
  ```

- Surfaces use fully type-level specs in flat primitive normal form after helper expansion:

  ```haskell
  type RosterSurface =
      Surface Roster
          '[ Scope RosterWeek '[ Field VenueId WireUUID, Field RosterGroupId WireUUID, Field WeekOffset WireInt ]
           , Fragment RosterRow '[ Field RosterDayId WireUUID, Field RowIndex WireInt ] '[ Eager ]
           , Intent MoveRosterShiftToSlot '[ Field SourceItemKey WireText, Field TargetDropzoneKey WireText ] '[]
           ]
  ```

- Shared sub-declarations such as scopes, DTOs, fields, events, DOM tokens, sessions, layers, and helper bundles are included by aliases inside surfaces. The extractor expands helpers and merges identical normalized declarations by marker/name. Conflicting shared declarations fail generation with clear diagnostics.
- No separate top-level scope registry is introduced initially. Shared scopes emerge when multiple surfaces include the same normalized `Scope` marker/spec.
- Core primitives are promoted data constructors. Marker types are nullary data types at kind `Type`; browser wire types use namespaced closed constructors such as `WireText`, `WireInt`, `WireBool`, `WireUUID`, `WireDay`, `WireList`, `WireOptional`, `WireNullable`, and `WireRef`. Type synonyms/approved type families are authoring sugar only and must normalize to primitive lists without recursion.
- Naming is derived globally from marker type names with context-aware suffix stripping and robust acronym handling. Exact names are rare, type-level, allowlisted, and visible to the generator.
- During migration, legacy self-describing live wire surfaces coexist with new `FrontendSurface` mount-resolved surfaces. The final target removes/replaces old author-facing `FrontendCodec`, `FrontendSchema`, DTO schema groups, `TypedLiveSurfaceDefinition`, `Web.LiveSurfaceRegistry`, and `Application.Helper.SurfaceProjection` for migrated surfaces, then eventually unifies all live surfaces on the new protocol with no legacy paths. Renderer-internal IR is fine if it is fed only by the new `SurfaceContractIR`.
- The GHC API extractor is Nix/devenv-owned. It loads the explicit registry module, normalizes type synonyms/helpers/type families, validates the full contract graph, and renders generated TypeScript/Haskell runtime metadata. GHC API package exposure belongs in the Nix generator command path, not ad hoc developer commands.
- Static spec well-formedness and `SurfaceImpl` handler completeness should be compile-time where practical. Registry/global validation, generated-file drift, and TypeScript exhaustiveness remain deterministic generator/CI gates.
- `SurfaceImpl spec` replaces `TypedLiveSurfaceDefinition` as the feature-facing runtime bridge. It must require handlers/builders for every declared dynamic requirement: scope/wire conversion, authorization, version, mount-local fragment target/url/render, concrete live-resource dependencies, HTMX action details, intent/action form metadata, mount key/metadata, and mount-state backend hooks. Runtime enumeration is derived from the single `RegisteredFrontendSurfaces` type list via `HasSurfaceImpl`/typeclass fold machinery.
- The first implementation uses direct database/read-model fragment rendering only. The generic `SurfaceProjection` cache/projection system is not used by lab, Timesheets, or Roster. Optional cache/projection backends can be added later behind `SurfaceImpl`.
- `LiveResource` remains the semantic mutation boundary, but successful business mutations for migrated surfaces refresh authoritative UI through the live invalidation/refetch path for actor, duplicate mounts, and passive viewers. Actor HTTP responses carry only non-authoritative extras such as toasts/dialog cleanup, or validation-local failures.
- Fragment/scope keys become generated surface-scoped contracts with shared transport envelopes. Migrated invalidations carry surface/scope/fragment identity, not concrete global target ids; each mount resolves target ids, URLs, protection, and mount state locally. Shared scopes may be reused across surfaces; fragment keys remain surface-local.
- Request decoration should move away from selector lists. HTMX requests inside a typed surface mount are decorated from the closest mount by default. Opt-out exists only if a real case appears.
- Type-level `MountState` models view state separately from live subscription scope. Timesheets initially preserves current query-param behavior behind a swappable query-backed mount-state backend, so a future DB-backed user/venue/mount state backend can replace it without changing the surface spec.
- Generated TypeScript may change shape where cleaner, but should continue to expose generated types, guards, parsers, and encoders. Branded TypeScript aliases should be generated for semantically meaningful ID fields while keeping primitive JSON wire shapes.
- Haskell JSON/field encoding uses a closed browser-boundary wire-type universe and reusable typeclass/reflection/field-list machinery initially, not arbitrary domain model serialization. Generated Haskell ADTs are deferred unless ergonomics require them.
- The surface lab is support-super-admin-only. It covers every primitive, uses real runtime mounting/HTMX/generated TS consumption, and has no old frontend contract authoring.
- Timesheets migrates before Roster. Roster proves typed containment, lazy policy, drag/drop helper expansion, disposable layers, effects, fragment-specific conflict policies, direct rendering, and duplicate-mount guarantees.

## Acceptance Criteria

- A support-only surface lab defines every primitive in the type-level DSL, mounts through `SurfaceImpl`, exercises generated TypeScript and at least one real HTMX/intent path, and uses no old author-facing frontend contract machinery.
- The GHC API generator emits TypeScript contracts, branded aliases, guards, parsers, encoders, constants, manifests, and runtime metadata from `RegisteredFrontendSurfaces` with deterministic Nix-owned commands/checks.
- `SurfaceImpl` completeness is proven by typed builders/handler records and focused negative compile fixtures.
- Timesheets and Roster are migrated to `FrontendSurface` specs and direct `SurfaceImpl` rendering without `Application.Helper.SurfaceProjection`.
- Live invalidation, duplicate mounts, actor-originated successful mutation refreshes, lazy fragments, typed interactions, and conflict policies work through the new registry/runtime model.
- Old replaced surface-related `FrontendCodec`/schema registry, `TypedLiveSurfaceDefinition`, `Web.LiveSurfaceRegistry`, and projection authoring paths are removed or guarded from reintroduction after replacement coverage.
- Living docs and agent rules describe the implemented authoring workflow and migration rules.

## Notes

**2026-07-02T02:48:09Z**

Planning workstream created at docs/workstreams/type-level-frontend-surfaces.md with locked decisions: fully type-level specs, flat primitive normal form, global derived naming, GHC API extraction from RegisteredFrontendSurfaces, typed SurfaceImpl completeness, type-level DTO generation, surface lab first, Timesheets then Roster migration.

**2026-07-02T04:10:00Z**

Plan refined: root remains a single list of surfaces; shared declarations are aliases included by surfaces and merged/validated after normalization. `SurfaceImpl` replaces `TypedLiveSurfaceDefinition`; first implementation avoids `SurfaceProjection`; request decoration uses closest surface mount; Timesheets query params are modeled as typed swappable mount state; final target removes old `FrontendCodec`/`FrontendSchema` surface contract machinery.

**2026-07-02T05:08:00Z**

Clarification pass locked mount-local transport and ticket-plan decisions: new `FrontendSurface` surfaces use surface/scoped fragment identities resolved per mount; successful business mutations use unified live invalidation/refetch for actor, duplicate mounts, and passive viewers; legacy self-describing wire surfaces coexist during migration but final target is fully unified with no legacy paths; runtime enumeration is derived from the single type-level registry through `SurfaceImpl` typeclass/fold machinery. Added early tickets `ir-npm8`, `ir-p3c3`, and `ir-g6z3`.

**2026-07-02T10:20:50Z**

Roster migration started after Timesheets close. First chunk targets Roster FrontendSurface contract, metadata-only SurfaceImpl bridge, and compatibility cleanup until the interaction modeling decision point.

**2026-07-02T12:54:18Z**

Closeout: all child tickets are closed. FrontendSurface DSL/registry/GHC generator, SurfaceImpl completeness checks, support lab, Timesheets and Roster migrations, native interaction/lazy/fragment behavior, SurfaceProjection removal, guardrails, generated TypeScript pipeline, and durable authoring docs are implemented. Legacy live-surface infrastructure remains only for non-migrated surfaces and is tracked outside this epic as future app-wide migration/unification work. Verified latest closeout chunk with doc-drift-check, frontend-surface-guardrails, and frontend-contracts-check.
