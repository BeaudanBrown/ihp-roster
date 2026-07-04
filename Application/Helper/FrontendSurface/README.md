# FrontendSurface Authoring Guide

`Application.Helper.FrontendSurface` owns the type-level surface contract system
for server-rendered interactive surfaces. New production surfaces should use this
path instead of authoring `FrontendCodec` DTO schema groups,
`TypedLiveSurfaceDefinition`, `Web.SurfaceInvalidation` entries, or a shared
projection cache.

## Source Of Truth

The root registry is the type-level list in
`Application.Helper.FrontendSurface.Registry`:

```haskell
type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     ]
```

A surface is added by defining a type-level spec with the primitives from
`Application.Helper.FrontendSurface.DSL`, then adding it to this list. The GHC
extractor loads this registry, expands approved helper aliases, normalizes the
primitive declarations, validates names/conflicts, and emits the browser
contracts in `frontend/ts/generated/contracts.ts`.

Feature specs normally live beside this directory as focused modules such as
`Lab.hs`, `Timesheets.hs`, and `Roster.hs`. Runtime feature behavior may live in
the feature area when it is tightly coupled to controllers/views, but it must
implement the same declared spec through `SurfaceImpl`.

## Composition Terminology

- **Surface**: an independently mounted, typed UI owner with a scope,
  subscription metadata, generated contract, and `SurfaceImpl` handlers.
- **Fragment** or **region**: a surface-owned server-rendered DOM target that can
  be refetched and swapped. The current DSL name is `Fragment`; documentation may
  use "region" when discussing DOM lifecycle.
- **Contained child surface**: a nested surface mount rendered inside a parent
  fragment/region and declared by that parent fragment through `ContainsSurface`
  once composition support is available.
- **Runtime reconciliation**: the browser lifecycle pass that treats the current
  DOM as the source of truth for mounted surface instances, initializes newly
  inserted mounts, and disposes removed mounts recursively so websocket
  subscriptions match mounted scopes.

A contained child surface is still an independent surface: it owns its own scope,
fragments, request decoration, focused-field protection, and invalidation
handling. Parent fragments may refresh broad HTML that includes child mounts, so
composition-safe runtime code must clean up removed child/grandchild mounts and
avoid duplicate subscriptions when the same instance remains mounted.

## Type-Level Spec Shape

Use nullary marker types plus promoted DSL primitives:

```haskell
data ExampleSurfaceName
data ExampleScope
data ExampleFragment
data VenueId
data WeekOffset

type ExampleSurface =
    Surface ExampleSurfaceName
        '[ Scope ExampleScope
            '[ Field VenueId 'WireUUID
             , Field WeekOffset 'WireInt
             ]
         , Fragment ExampleFragment '[] '[ 'Eager ]
         ]
```

Available primitives include:

- `Scope` for the authorized live data slice;
- `Fragment` for refreshable server-rendered DOM targets. Add the `Live`
  fragment option when the fragment participates in websocket invalidation;
- `Action` and `Intent` for Haskell-owned HTMX action/form metadata;
- `MountState` for view state that is not part of the live subscription scope;
- `Session` plus session options such as `Layer` and `Effect` for typed
  interaction runtime coordination;
- `ConflictPolicy` for session/fragment conflict behavior;
- `Event`, `DomToken`, and `Dto` for narrow browser-boundary metadata.

Wire fields use the closed browser wire universe: `WireText`, `WireInt`,
`WireBool`, `WireUUID`, `WireDay`, `WireList`, `WireOptional`, `WireNullable`,
and `WireRef`. Do not serialize arbitrary domain models through surface fields;
convert to a narrow browser DTO or feature-specific render model first.

Shared declarations are type aliases, not a second registry. Compose helpers
with `Append`/`Concat`, for example the reusable drag/drop bundles in
`Application.Helper.FrontendSurface.Interaction`. The generator expands helpers
and rejects conflicting normalized declarations with the same marker/name.

## Naming Policy

Generated names are derived from marker type names by
`Application.Helper.FrontendSurface.Naming` using context-aware suffix stripping
and acronym handling. Prefer descriptive marker names and avoid exact-name
overrides unless the naming guardrails require them. Run the naming and surface
checks after adding markers.

## Runtime Implementation

Every migrated surface supplies runtime behavior through
`Application.Helper.FrontendSurface.Runtime.SurfaceImpl spec`. `SurfaceImpl`
replaces feature-facing `TypedLiveSurfaceDefinition` for migrated surfaces.

Use `mkSurfaceImpl` with typed handler lists:

- `FrontendSurfaceScopeHandler` supplies the concrete scope value and scope key;
- `FrontendSurfaceMountStateHandler` supplies typed view state defaults;
- `FrontendSurfaceFragmentHandler` supplies mount-local target id, GET URL,
  protection/load policy, and server rendering for each fragment;
- `FrontendSurfaceActionHandler` supplies generated HTMX request metadata;
- `FrontendSurfaceIntentHandler` supplies generated intent form metadata.

The handler lists are indexed by the declared spec. Missing fragment, action,
intent, scope, or mount-state handlers fail the focused compile-failure tests
rather than becoming runtime validation gaps.

Render mounts with `renderFrontendSurfaceMount impl body`. This emits
`data-bepis-surface` and `data-bepis-surface-config`. Do not handwrite these
attributes in feature views except in guardrail fixtures. Lazy fragments should
use `renderFrontendSurfaceLazyFragment`; intent/action forms should use the
runtime render helpers so HTMX attributes and hidden fields stay Haskell-owned.

Controllers remain normal IHP mutation entrypoints in this epic. They parse and
authorize params, call feature mutation/read-model code, and render validation
failures or successful actor extras. Successful mutations should report typed
`SurfaceResourceValue` touches using the generated smart constructors exported from
`Application.Helper.SurfaceResource` so actor duplicate mounts and passive viewers
refresh through the unified live invalidation/refetch path.

## Live Authorization, Resources, And Fragment Rendering

Migrated `FrontendSurface` invalidations are semantic and surface-native:
transport identifies generated kebab-case surface names, generated scope DTOs,
and generated fragment names plus typed params. Haskell emits ready-to-use mount
subscription JSON from `Scope` plus `Fragment ... Live`; composition-only parent
surfaces omit `Live` fragments and therefore do not subscribe. The browser
runtime reads the generated subscription payload and must not parse scope keys or
switch on app-specific surface/fragment names.

`Scope` owns websocket subscription identity and authorization. Every scope must
carry exactly one auth marker: `Authorize SomePolicy` for server-checked scopes,
or explicit `NoAuth` for public/test-only scopes. `Web.SurfaceInvalidation`
derives subscription authorization from the reflected `RegisteredFrontendSurfaces`
metadata; feature code must not add hard-coded fallback authorization for a
surface/scope pair.

Fragments that participate in passive invalidation declare `Live` and then one
invalidation mode. Prefer explicit `DependsOn SomeResource '[ ...sources... ]`,
where each dependency field is sourced with `FromScope ScopeField` or
`FromFragment FragmentField`. Use `ResyncOnly` only when a live fragment is
refreshed by reconnect/resync or actor paths and has no passive business-resource
dependency. The generator validates that live fragments have one mode and that
resource field sources are concrete and non-conflicting.

`Resource` declarations live in the type-level surface specs and are discovered
by walking `RegisteredFrontendSurfaces`. Generated Haskell smart constructors in
`Application.Helper.FrontendSurface.Resource` / `Application.Helper.SurfaceResource`
construct concrete `SurfaceResourceValue`s such as `rosterWeekResource`,
`timesheetDayResource`, or `xeroMappingsResource`. Mutation/domain code emits
those concrete generated values; it must not introduce legacy sentinel resources,
custom dependency hooks, or bridge conversions.

The passive planner is generated-data driven:

1. collect mounted fragments from active surface-native subscriptions;
2. evaluate each fragment's `DependsOn` declarations from scope/fragment params;
3. intersect those concrete dependency values with touched generated resources;
4. broadcast the affected generated wire fragments.

Runtime/domain expansion is separate from static fragment dependency planning.
When a mutation has broad semantic effects, expand it in the producer or a small
feature-owned helper to concrete generated resources before invalidation (for
example, active roster-week resources for roster-affecting leave/staff changes).
Do not encode broad fanout as a `FrontendSurface` custom dependency or fragment
fanout DSL.

Use direct database/read-model rendering first. There is no shared
`Application.Helper.SurfaceProjection` cache. If profiling later proves caching
is needed, add an explicit feature-owned read-model/cache seam or `SurfaceImpl`
backend with viewer-aware keys, dependency versions, and tests.

`MountState` models view state separately from the live subscription scope. Keep
query-param or future persisted state behind a small backend seam so changing
storage does not change the type-level surface spec.

## Generated TypeScript Consumption

`frontend/ts/generated/contracts.ts` is backend-owned. Runtime TypeScript should
consume generated types, constants, guards, parsers, encoders, manifests, static
interaction schemas, field names, fragment names, and conflict-policy unions.
Use generated `parseX` at unknown JSON/data boundaries and `encodeX` for outbound
surface DTOs. If TypeScript switches on a generated closed union, use
`assertNever` so `frontend-check` fails when Haskell adds a new variant.

Generic browser code may decorate HTMX requests from the closest mounted surface,
manage disposable sessions/layers, fill generated intent forms, and refetch
mount-local fragments. It must not infer feature URLs, target ids, canonical
field names, surface names, or mutation endpoints.

## Authoring Rules

Production feature surfaces have migrated to the `FrontendSurface` path. Do not
start new production work with `TypedLiveSurfaceDefinition`,
`data-live-update-surface`, `serveTypedLiveFragment`, handwritten
live-surface manifest DTOs, legacy registry/catalog adapters, or a shared
`SurfaceProjection` cache. Feature-facing authoring uses
type-level specs plus `SurfaceImpl`.

For a new surface or migration:

1. Define the type-level spec and add it to `RegisteredFrontendSurfaces`.
2. Implement `SurfaceImpl` handlers and render mounts with runtime helpers.
3. Move static interaction/action metadata into the spec or shared helper
   aliases.
4. Render fragments directly from feature read models; do not add a
   `SurfaceProjection` cache.
5. Generate contracts and update TypeScript to consume generated surface data.
6. Add/adjust Hspec, frontend, and E2E coverage for mount discovery, duplicate
   mounts, actor refresh, passive invalidation, lazy fragments, and interaction
   behavior as applicable.
7. Add guardrails if the migration removes a legacy path that should not return.

## Verification

Use focused checks while developing and the broader frontend gate before commit:

```bash
bash ./bin/in-env frontend-contracts
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env surface-compile-fail-check
bash ./bin/in-env surface-guardrails
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface"
```

Run feature-specific Hspec/E2E checks for the migrated surface as well.
