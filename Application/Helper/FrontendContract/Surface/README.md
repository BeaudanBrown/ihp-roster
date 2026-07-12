# FrontendContract Surface Authoring Guide

`Application.Helper.FrontendContract.Surface` owns the type-level surface contract system
for server-rendered interactive surfaces. New production surfaces should use this
path instead of authoring parallel DTO schema groups,
`Web.SurfaceInvalidation` entries, or a shared
projection cache.

## Source Of Truth

The root registry is the type-level list in
`Application.Helper.FrontendContract.Surface.Registry`:

```haskell
type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     , RosterDayTimelineSurface
     , LeaveRequestsSurface
     , BillingSurface
     , SupportSurface
     , ProfileSurface
     , StaffSurface
     , AdminPageSurface
     , AdminXeroPageSurface
     , AdminVenueSettingsSurface
     , AdminInvitesSurface
     , AdminExportsSurface
     , AdminShiftTypesSurface
     , AdminRosterGroupsSurface
     , AdminXeroSurface
     ]
```

A surface is added by defining a type-level spec with the primitives from
`Application.Helper.FrontendContract.Surface.DSL`, then adding it to this list.
`Application.Helper.FrontendContract.Surface.Reflect` recursively evaluates the
closed type-level DSL with typeclass instances, and
`Application.Helper.FrontendContract.Surface.Contracts` validates that reflected
value into the single checked `SurfaceContractIR`. Its `SurfaceIR` values are
embedded directly in the unified `FrontendContractIR`; no compact Surface copy
or conversion layer exists. Field, wire, schema, diagnostic, and HTMX values come
from `Application.Helper.FrontendContract.Core`, and both global and Surface
reflection use `Application.Helper.FrontendContract.Naming`. The same checked
model is the authority for runtime behavior, browser contracts in
`frontend/ts/generated/contracts.ts`, and semantic Surface architecture facts.

Contract generation does not inspect GHC compiler internals. Concrete type
synonyms and approved `Append`/`Concat` helpers reduce before reflection; every
supported DSL constructor has an explicit reflection instance. Add new DSL
vocabulary to the reflection and checked-IR path rather than introducing another
evaluator.

Feature specs normally live beside this directory as focused modules such as
`Lab.hs`, `Timesheets.hs`, and `Roster.hs`. Runtime feature behavior may live in
the feature area when it is tightly coupled to controllers/views, but it must
implement the same declared spec through `SurfaceImpl`.

## Composition Terminology

- **Surface**: an independently mounted, typed UI owner with a scope,
  subscription metadata, generated contract, and one-step `SurfaceImpl` runtime
  values.
- **Fragment** or **region**: a surface-owned server-rendered DOM target that can
  be refetched and swapped. The current DSL name is `Fragment`; documentation may
  use "region" when discussing DOM lifecycle.
- **Contained child surface**: a nested surface mount rendered inside a parent
  fragment/region and declared by that parent fragment through `ContainsSurface`.
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
- `MountState` for server-side view state that is not part of the live
  subscription scope or emitted browser mount contract;
- `Session` plus session options such as `Layer` and `Effect` for typed
  interaction runtime coordination;
- generated source, dropzone, and activation refs for generic browser
  interactions;
- `ConflictPolicy` for session/fragment conflict behavior;
- `Event`, `DomToken`, and `Dto` for checked Surface metadata. `DomToken` is
  server-only; use `BrowserDomToken` only when production TypeScript also
  imports the semantic token. Guardrails require every emitted browser token to
  have a production consumer.

Wire fields use the closed browser wire universe: `WireText`, `WireInt`,
`WireBool`, `WireUUID`, `WireDay`, `WireList`, `WireOptional`, `WireNullable`,
and `WireRef`. Do not serialize arbitrary domain models through surface fields;
convert to a narrow browser DTO or feature-specific render model first.

Shared declarations are type aliases, not a second registry. Compose helpers
with `Append`/`Concat`, for example the reusable drag/drop bundles in
`Application.Helper.FrontendContract.Surface.Interaction`. The generator expands helpers
and rejects conflicting normalized declarations with the same marker/name.

## Naming Policy

Generated names are derived from marker type names by
`Application.Helper.FrontendContract.Naming` using context-aware suffix stripping
and acronym handling. Prefer descriptive marker names and avoid exact-name
overrides unless the naming guardrails require them. Run the naming and surface
checks after adding markers.

## Generated Interaction Registry

`FrontendContract Surface` is also the source of truth for feature-specific
browser interaction names. `InteractionContract` keeps only generic runtime
shapes and generated DOM vocabulary. Reflection emits one minimal
`FrontendSurfaceInteractionRegistry` containing only production-consumed source,
dropzone, activation, and session runtime definitions. It does not emit the
server-only action catalog, intent/DTO aliases, contained-surface topology, or a
second static-schema copy. TypeScript consumes that registry to interpret
mounted surface instances; it must not invent feature-local interaction names,
depend on old global `Interaction*` roster enums, or infer business behavior
from ad-hoc DOM strings. Live-update code separately imports the minimal
`FrontendSurfaceFragmentRegistry`, so either bundle can tree-shake the other
feature lane.

Feature views still own ordinary HTML layout. They attach minimal role-specific
refs through generated Haskell helpers:

- `data-bepis-source-ref` plus `data-bepis-source-key` for pointer/session
  sources;
- `data-bepis-dropzone-ref` plus `data-bepis-dropzone-key` for compatible
  targets;
- `data-bepis-activation-ref` for controls that immediately emit an intent;
- generated intent form/field attrs for DOM-owned HTMX forms.

Ref values are generated static names. Key values are dynamic opaque strings
rendered by the server and submitted back through generated intent fields; the
browser may forward them but must not parse them as domain authority.

For pointer drag/drop, prefer the shared aliases in
`Application.Helper.FrontendContract.Surface.Interaction` over hand-assembling
low-level primitives. `DragSessionDefinition`, `DragSourceRefFor`,
`DragDropzoneRefFor`, `DragDropIntent`, and
`DragDropInteractionWithRefsAndVariants` cover the common pattern: one drag
session, one or more named source refs, named compatible dropzone refs, opaque
`sourceItemKey`/`targetDropzoneKey` fields, optional modifier variants, and a
DOM-owned HTMX intent form. Multi-source surfaces should give each semantic
source and target a distinct generated ref, then list the compatible dropzone
refs on each source; the browser runtime uses that manifest data for hit-testing
and highlighting while controllers keep validating opaque keys server-side.

Concrete HTMX forms remain DOM-owned and server-rendered. `SurfaceImpl` intent
handlers/render helpers own action URLs, methods, hidden inputs, targets, swaps,
sync selectors, disabled selectors, and trigger events. Mount JSON must not
become a custom mutation transport contract. The generic browser runtime only
validates generated semantics and matching DOM forms, fills declared fields, and
dispatches the generated HTMX trigger.

## Generated HTMX Request Actions

`Action name fields options` describes surface-owned request initiators, not
successful business refresh behavior. Its `fields` list is the browser-submitted
payload/form boundary. Route params and venue/page context stay in Haskell route
builders such as `pathTo` and `appendQueryParams`; do not move IHP routes into
the type-level DSL.

Use standard HTMX options for stable request metadata:

- `HtmxMethod` for `hx-get`, `hx-post`, `hx-put`, `hx-patch`, or `hx-delete`;
- typed selectors such as `HtmxId`, `HtmxClass`, `HtmxClosest`, and `HtmxFind`;
- typed triggers such as `HtmxClick`, `HtmxChange`, and `HtmxLoad`;
- typed swaps such as `HtmxInnerHTML`, `HtmxOuterHTML`, and `HtmxNoSwap`;
- typed synchronization such as
  `HtmxSyncOn (HtmxClosest (HtmxId Shell)) HtmxSyncReplace`;
- `HtmxRawSelector`, `HtmxRawTrigger`, `HtmxRawSwap`, or `HtmxRawSync` only
  when the closed recipes cannot express the value. Every raw node carries a
  non-empty reason and validation rejects an empty reason;
- `CustomHtmx Marker "reason"` only for extra HTMX attributes that a standard
  option does not describe. The reason remains in the checked Haskell IR for
  validation and architecture review; it does not force a browser action
  manifest to be generated.

Reflection renders common punctuation deterministically: an ID selector owns its
`#`, class selectors own `.`, traversal recipes own their separating space, and
sync recipes own their `:` strategy delimiter. Views must not add or strip this
punctuation.

Runtime views combine the generated action IR with a `FrontendSurfaceActionRoute`
using the form, submit-button, link, or HTMX-only render helper. These helpers
render generated `data-bepis-surface-action` metadata plus the declared HTMX
attrs. They can also render standard `method`/`action`, `formaction`, or `href`
attrs for browser semantics, but that is not a complete no-JS UX unless the
controller returns full-page or redirect fallbacks.

Successful migrated mutations must not return authoritative business fragment
HTML/OOB for the same surface. They should set `HX-Reswap: none`, emit
actor-local live-fragment refresh metadata through
`setActorLocalFragmentsRefresh` only for requester-local workflows where no
shared resource changed. Mutations reporting touched resources use
`setActorLiveResourcesRefresh`, so actor mount keys and passive subscription keys
are evaluated by the same planner over the same
`SurfaceResourceValue`s. Passive invalidation handles other tabs/viewers. OOB
remains valid for extras such as dialog clears, toasts, disposable-layer cleanup,
focus/scroll hints, and validation-local responses. Plain fragment GET/refetch
endpoints should return the target node itself, not OOB wrappers.

Admin Roster Groups is the reference migration: create/update/move/toggle
request initiators are declared in `Surface.Admin`, rendered from generated
helpers in `Web.View.Admin.RosterGroups`, and successful create/update/move
responses use actor-local invalidation instead of roster-group business OOB.

Legacy semantic marker attributes such as `data-bepis-marker`,
`data-bepis-pointer-session`, `data-bepis-session-kind`,
`data-bepis-session-intent`, `data-bepis-activation-intent`, and
`data-bepis-activation-trigger` are deleted from production helpers and the
browser runtime. Production feature views author generated refs through
`Application.Helper.FrontendContract.Surface.Interaction`; guardrails prevent
reintroducing the old semantic marker protocol.

## Marker-Indexed Runtime Values

Use `Application.Helper.FrontendContract.Surface.Values` instead of scanning the
reflected registry by protocol strings. `surfaceNameValue`, `surfaceScopeValue`,
`surfaceFragmentValue`, `surfaceActionValue`, `surfaceIntentValue`,
`surfaceResourceValue`, `surfaceSourceRefValue`, `surfaceDropzoneRefValue`,
`surfaceActivationRefValue`, and `surfaceDomTokenValue`
are indexed by both the owning `Surface` and marker. A marker owned by another
surface is a compile error.

Build scope, mount-state, fragment, and action payloads with declaration-ordered
`SurfaceFields`, `surfaceField`, `surfaceOptionalField`, and
`surfaceNullableField`. The field marker, presence, wire type, and Haskell value
must match the owning declaration. `WireUUID` values are `UUID`, not unchecked
text; an absent `OptionalField` is omitted, while `NullableField` retains its
explicit null. Use `surfaceFieldsJson` only at the JSON boundary and
`frontendSurfaceActionFields` for hidden/query fields; do not introduce phantom
`Aeson.Value` carriers or recover required fields with runtime fallbacks.

## Runtime Implementation

Migrated surfaces expose mount behavior through
`Application.Helper.FrontendContract.Surface.Runtime.SurfaceImpl spec`.
`SurfaceImpl` is the feature-facing runtime value.

For a server-rendered mount whose controllers/views already own fragment
rendering and action routes, use `mkSurfaceImplFromValues`. It is the sole
production constructor and derives the surface name, canonical scope key, exact
scope/mount-state JSON, and live subscription from marker-indexed values in one
step. Build descriptors with `frontendSurfaceMountedFragmentFor`; it derives
fragment identity and lazy defaults from the owning Surface declaration while
URLs, target IDs, and protection remain mount-local.

Pass each concrete dynamic or repeated fragment set directly to that constructor
(or a feature helper that calls it). There is no post-construction descriptor
patching and no generic handler/action/intent catalog on `SurfaceImpl`. Real
interaction intent forms are feature-owned marker-indexed values supplied to the
interaction shell; ordinary action routes remain next to their server-rendered
views. Compile-failure tests enforce Surface, marker, and field ownership rather
than ceremonial handler counts.

Render mounts with `renderFrontendContract SurfaceMount impl body`. This emits
`data-bepis-surface` and `data-bepis-surface-config`. Do not handwrite these
attributes in feature views except in guardrail fixtures. Reflection generates a
surface-discriminated exact `FrontendSurfaceMountConfig` parser. The only mount
properties are `surface`, `scopeKey`, `mountKey`, `fragments`, and
`subscription`; each descriptor contains only `fragmentKey`, `targetId`, `url`,
and `protection`, while a non-null subscription contains only the typed `scope`.
Server `MountState`, load behavior, and derived resync lists must not be added to
the browser envelope without a browser consumer. DOM/config surface disagreement
is an invalid mount and must be reported rather than coerced.

The websocket endpoint, client-id header, and surface config/action/owner DOM
attribute names come from reflected global constants shared by Haskell and
TypeScript. Add or change those values in the frontend contract registry, not as
runtime string literals.

Lazy placeholders must
use the `renderFrontendSurfaceLazyFragmentWithConfig` runtime helper (or its
plain default wrapper) so canonical UI-region attrs, HTMX swap attrs, retry
metadata, and primitive-derived lazy behavior stay Haskell-owned. Use
`customPlaceholderFrontendSurfaceLazyFragmentConfig` when the placeholder markup
already renders its own panel/card chrome, so the outer lazy region stays a
transparent HTMX/region shell instead of visually nesting surfaces. Feature views
may pass root/slot classes in the config; the shared runtime must not infer
layout geometry. Intent/action forms should use the runtime render helpers so
HTMX attributes and hidden fields stay Haskell-owned.

Controllers remain normal IHP mutation entrypoints in this epic. They parse and
authorize params, call feature mutation/read-model code, and render validation
failures or successful actor extras. Successful migrated `FrontendSurface`
mutations should report typed `SurfaceResourceValue` touches using the generated
smart constructors exported from `Application.Helper.SurfaceResource`, then return
actor-local semantic invalidation instructions plus extras. The actor tab and
passive viewers both refresh by resolving semantic scope and fragment keys
through mounted surface metadata and each mount's plain fragment GET URL, so
successful actor responses must not carry authoritative business OOB HTML.

## Live Authorization, Resources, And Fragment Rendering

Migrated `FrontendContract Surface` invalidations are semantic and surface-native:
transport identifies generated kebab-case surface names, generated scope DTOs,
and generated fragment names plus typed params. Haskell emits ready-to-use mount
subscription JSON from `Scope` plus mounted `Fragment ... Live` values;
composition-only parent surfaces omit `Live` fragments and therefore do not
subscribe. The emitted subscription contains the typed scope only. The browser
uses mounted descriptors plus the generated reflected `Live` fragment set for
initial/reconnect resync keys; it must not parse scope keys or switch on
app-specific surface/fragment names.

`Scope` owns websocket subscription identity and authorization. Every scope must
carry exactly one auth marker: `Authorize SomePolicy` for server-checked scopes,
or explicit `NoAuth` for public/test-only scopes. `Web.SurfaceInvalidation`
derives subscription authorization from the reflected `RegisteredFrontendContract Surfaces`
metadata; feature code must not add hard-coded fallback authorization for a
surface/scope pair.

Fragments that participate in passive invalidation declare `Live` and then one
invalidation mode. Prefer explicit `DependsOn SomeResource '[ ...sources... ]`,
where each dependency field is sourced with `FromScope ScopeField` or
`FromFragment FragmentField`. Parameterized fragments are the preferred shape for
homogeneous repeated regions that differ mainly by a typed key/section, such as
leave section count/list fragments, timesheet day sections, roster day sections,
or roster rows. The parameter should also be the natural resource boundary so
actor-local `setActorLiveResourcesRefresh` and passive websocket invalidation plan
through the same `DependsOn ... FromFragment ...` declaration. Do not
parameterize unrelated tabs/sections merely because they appear together in a
page; keep distinct fragments when dependencies, permissions, forms, or response
modes differ materially. Use `ResyncOnly` only when a live fragment is refreshed
by reconnect/resync or actor paths and has no passive business-resource
dependency. The generator validates that live fragments have one mode and that
resource field sources are concrete and non-conflicting.

`Resource` declarations live in the type-level surface specs and are discovered
by walking `RegisteredFrontendSurfaces`. Generated Haskell smart constructors in
`Application.Helper.FrontendContract.Surface.Resource` / `Application.Helper.SurfaceResource`
construct concrete `SurfaceResourceValue`s such as `rosterWeekResource`,
`timesheetDayResource`, or `xeroMappingsResource`. Mutation/domain code emits
those concrete generated values; it must not introduce legacy sentinel resources,
custom dependency hooks, or bridge conversions.

The singular actor/passive planner is generated-data driven:

1. accept exact semantic keys from an actor mount or active subscription;
2. evaluate each key's fragment `DependsOn` declarations from scope/fragment params;
3. intersect those concrete dependency values with touched generated resources;
4. coalesce affected scope/fragment targets before actor delivery or passive broadcast.

Runtime/domain expansion is separate from static fragment dependency planning.
When a mutation has broad semantic effects, expand it in the producer or a small
feature-owned helper to concrete generated resources before invalidation (for
example, active roster-week resources for roster-affecting leave/staff changes).
Do not encode broad fanout as a `FrontendContract Surface` custom dependency or fragment
fanout DSL.

Use direct database/read-model rendering first. There is no shared
`Application.Helper.SurfaceProjection` cache. If profiling later proves caching
is needed, add an explicit feature-owned read-model/cache seam or `SurfaceImpl`
backend with viewer-aware keys, dependency versions, and tests.

`MountState` models Haskell/server view state separately from the live
subscription scope. Keep query-param or future persisted state behind a small
backend seam so changing storage does not change the type-level surface spec.
The generator does not emit browser `MountState` types or mount JSON unless a
future contract adds an actual browser consumer.

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

Production feature surfaces have migrated to the `FrontendContract Surface` path. Do not
start new production work with deleted typed-live compatibility concepts,
legacy mount attributes, handwritten
live-surface manifest DTOs, legacy registry/catalog adapters, or a shared
`SurfaceProjection` cache. Feature-facing authoring uses
type-level specs plus `SurfaceImpl`.

For a new surface or migration:

1. Define the type-level spec and add it to `RegisteredFrontendContract Surfaces`.
2. Implement `SurfaceImpl` handlers and render mounts with runtime helpers.
3. Move static interaction/action metadata into the spec or shared helper
   aliases, including generated source/dropzone/activation refs and their
   session/intent compatibility.
4. Render role-specific refs with `withFrontendContract SurfaceSourceRef`,
   `withFrontendContract SurfaceDropzoneRef`, or `withFrontendContract SurfaceActivationRef`, and
   render intent forms through `SurfaceImpl`/runtime helpers so URLs, targets,
   swaps, sync, hidden values, and triggers remain server-owned.
5. Render fragments directly from feature read models; do not add a
   `SurfaceProjection` cache.
6. Generate contracts and update TypeScript to consume generated surface data.
7. Add/adjust Hspec, frontend, and E2E coverage for mount discovery, duplicate
   mounts, actor-local invalidation, passive invalidation, lazy fragments, and
   interaction behavior as applicable.
8. Add guardrails if the migration removes a legacy path that should not return.

## Architecture Facts And Diagrams

`Application.Helper.FrontendContract.Surface.Architecture` renders deterministic
semantic facts from `registeredFrontendSurfaceContractIR`; it is a renderer of
the checked reflected value, not another evaluator. `architecture-facts` embeds
those facts in the project architecture model, and the `generated-contracts`
architecture query can render the whole reflection/generation pipeline or a
focused Surface topology:

```bash
bash ./bin/in-env architecture-facts
printf '%s\n' '{"name":"generated-contracts","args":{"target":"roster"}}' \
  | bash ./bin/in-env architecture-query
```

Module imports, routes, schema relationships, and runtime traces continue to use
their dedicated source scanners or telemetry. Do not reintroduce compiler-type
inspection as Surface contract authority for those diagrams.

## Verification

Use focused checks while developing and the broader frontend gate before commit:

```bash
bash ./bin/in-env frontend-contracts
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-surface-compile-fail-check
bash ./bin/in-env frontend-surface-guardrails
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendContract Surface"
```

Run feature-specific Hspec/E2E checks for the migrated surface as well.
