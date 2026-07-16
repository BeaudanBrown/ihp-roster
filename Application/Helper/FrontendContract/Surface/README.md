# FrontendSurface Authoring Guide

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
    '[ TimesheetsSurface
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
`Timesheets.hs` and `Roster.hs`. Runtime feature behavior may live in the feature
area when it is tightly coupled to controllers/views, but it must implement the
same declared spec through `SurfaceImpl`.

Declaration-rich fixtures for reflection, validation, rendering, and
compile-failure coverage live under `Test/` and remain absent from
`RegisteredFrontendSurfaces`. Do not register test or diagnostic surfaces in the
production application merely to exercise DSL vocabulary.

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

`FrontendSurface` is also the source of truth for feature-specific
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

Effect declarations select the closed `InteractionEffect` kind. Clone-shadow
effects carry their required typed layer; modifier variants carry only closed
effects, not arbitrary nested options. Reflection lowers these declarations to
`Surface.SemanticIR`, whose constructors carry canonical effect classes, source,
and options. Checked-IR validation rejects missing layer declarations,
non-canonical values, duplicate effects, and effects placed outside sessions or
modifier variants. The TypeScript renderer serializes those constructors without
name-based dispatch, omission, or fallback layers.

Concrete HTMX forms remain DOM-owned and server-rendered. Opaque typed action
and intent values plus their runtime render helpers own declared field bundles,
methods, hidden inputs, targets, swaps, sync selectors, disabled selectors, and
trigger events. Mount JSON must not become a custom mutation transport contract.
The generic browser runtime only validates generated semantics and matching DOM
forms, fills declared intent fields, and dispatches the generated HTMX trigger.

## Generated HTMX Request Actions

`Action name fields options` describes surface-owned request initiators, not
successful business refresh behavior. Its `fields` list is the browser-submitted
payload/form boundary. Unrelated route params and venue/page context stay in
Haskell route builders such as `pathTo` and `appendQueryParams`; do not move IHP
routes into the type-level DSL. Declared action fields do not belong in
`FrontendSurfaceActionRoute`: construct the complete `SurfaceFields` bundle and
pass it to `frontendSurfaceAction`.

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

Runtime views combine opaque `FrontendSurfaceAction` values with a
`FrontendSurfaceActionRoute` using the form, submit-button, link, or HTMX-only
render helper. These helpers render generated `data-bepis-surface-action`
metadata plus the declared HTMX attrs. Links serialize the complete typed bundle
into the request URL and replace stale same-named query values while preserving
unrelated route context. Forms and form-owned controls remove declared fields
from route URLs; named controls in the body own mutable values, while
`renderFrontendSurfaceActionFormWithHiddenFields` emits a complete fixed bundle.
They can also render standard `method`/`action`, `formaction`, or `href` attrs for
browser semantics, but that is not a complete no-JS UX unless the controller
returns full-page or redirect fallbacks.

Controllers parse the same declaration with `parseSurfaceActionParams` or
`parseSurfaceIntentParams`. Parsing ignores unrelated request parameters,
returns declaration-ordered `SurfaceFields`, and accumulates structured field
errors. Required fields reject absence, optional fields map absence or blank to
`Nothing`, and nullable fields require presence while mapping blank to
`Nothing`. Repeated form parameters are decoded through `WireList`. Attach
transport errors to normal model validation with
`attachSurfaceRequestFieldErrors`; do not recover required fields with
`paramOrDefault`. A route that also supports partial, ordinary URL filters may
use `surfaceActionParamsComplete` only to decide whether a complete Surface
envelope was submitted. Those partial filters remain route context; after a
Surface envelope is selected, always parse it strictly and report every error.

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
`surfaceFragmentValue`, `surfaceResourceValue`, `surfaceSourceRefValue`,
`surfaceDropzoneRefValue`, `surfaceActivationRefValue`, and
`surfaceDomTokenValue` are indexed by both the owning `Surface` and marker.
Actions and intents are selected through the opaque `frontendSurfaceAction` and
`frontendSurfaceIntentForm` constructors. A marker owned by another surface is
a compile error.

Build scope, mount-state, fragment, and action payloads with declaration-ordered
`SurfaceFields`, `surfaceField`, `surfaceOptionalField`, and
`surfaceNullableField`. The field marker, presence, wire type, and Haskell value
must match the owning declaration. `WireUUID` values are `UUID`, not unchecked
text; an absent `OptionalField` is omitted, while `NullableField` retains its
explicit null. Use `surfaceFieldNameFrom` to obtain an input name only after a
complete bundle exists, and use `surfaceFieldsJson` only at the JSON boundary.
Do not introduce phantom `Aeson.Value` carriers, open field-value lists, or
runtime fallbacks for required fields.

### Compile-time diagnostic contract

Marker-indexed ownership failures name the compact Surface owner marker and the
requested scope, fragment, resource, action, intent, ref, or token marker. They
must not render the expanded `Surface ...` primitive list. Bundle field-name
accessor failures identify the marker absent from the complete bundle; action or
intent ownership failures remain attached to the opaque constructor call.

`SurfaceFields` construction keeps the exact declared field list as its
contextual type. Do not replace that context with a separately inferred generic
provided-field list: the declaration must continue to infer numeric values,
`Nothing`, nested wires, and other valid inputs. The declaration-directed
`NoSurfaceFields` and `(:&)` checks report:

- the next missing field and remaining declared shape;
- an extra field's marker and presence, explicitly noting that it has no
  declared wire;
- expected and received markers for an ordering mismatch;
- expected and received presence for a presence mismatch; and
- the affected marker, declared presence/wire, and received Haskell type for a
  wire mismatch.

Diagnostic shapes use DSL spellings such as `required WireUUID`,
`optional WireText`, and `nullable WireRef SomeDto`. GHC may qualify marker names
or wrap lines, but the diagnostic category, affected marker, and expected
contract shape are a tested authoring interface. Keep the focused expectations
in `Config/nix/scripts/frontend/surface-compile-fail-check` in sync when this
contract intentionally changes.

Live identity crosses this boundary through
`Application.Helper.FrontendContract.Surface.Live` only.
`frontendSurfaceScope` and `frontendSurfaceFragmentKey` accept the complete
marker-indexed field list and return opaque transport identities;
`matchFrontendSurfaceScope` and `matchFrontendSurfaceFragmentKey` recover only
the declaration-ordered typed values. Feature-owned adapters live beside their
contracts, for example `Surface.Roster.Live` and `Surface.Timesheets.Live`.
Adding, removing, reordering, or retyping a declared identity field therefore
breaks every incomplete constructor or matcher at compile time. Feature code
must not import `LiveUpdate.Internal`, pattern-match transport constructors, or
recover feature meaning from raw Surface/fragment text or JSON fields.

Resource identity crosses the planner seam through
`Application.Helper.FrontendContract.Surface.Resource` only.
`frontendSurfaceResource` accepts the complete marker-indexed resource field
list and returns an opaque `SurfaceResourceValue`;
`matchFrontendSurfaceResource` recovers only declaration-ordered typed values.
Concrete values and the matchers needed by feature-owned domain expansion live
beside their contracts in modules such as `Surface.Roster.Resource` and
`Surface.Profile.Resource`. Adding, removing, reordering, or retyping a resource
field breaks incomplete constructors and matchers at compile time. Feature code
must not import `Surface.Resource.Internal`, construct resource names/JSON, or
recover resource fields by text.

## Generated Haskell Adapter Foundation

Mechanical feature adapters are generated from the same checked declarations;
they are not another Surface evaluator. A nominal adapter family has one typed
`AdapterFamilySurface` association to an existing Surface alias. The
kind-indexed `SurfaceAdapterHome` aliases register only `(family, declaration
marker)` for resources, scopes, fragments, actions, and intents. Declaration
order, presence, wire shape, protocol names, and Haskell source types still come
from checked IR and the canonical `haskellWireSource` projection. The production
family registry mirrors `RegisteredFrontendSurfaces`; feature-local
`Surface.<Feature>.HaskellAdapter` modules own those associations, and later
adapter kinds reuse them instead of adding parallel family registries.

`HaskellAdapter.Core` owns the one shared implementation of home/family
resolution, `Typeable` metadata, Haskell source types, import aliasing, locality,
collision checks, deterministic module rendering, and generated-file
bookkeeping. Focused renderers supply checked declarations and their
function-level source only; they do not switch on reflected feature names or
adapter-kind text. Completeness uses these kind-indexed identities:

- a resource uses its checked shared resource identity;
- a scope uses its runtime Surface identity;
- a fragment, action, or intent uses owning Surface plus declaration identity.

An action and intent may therefore share the same marker and reflected name.
Generated-name collisions are checked across each complete physical output
module (including scope and fragment declarations sharing `Generated.Live`),
not across kind-separated modules such as Action and Intent.

The private output/facade pairs are fixed as `.Generated.Resource` / `Resource`,
`.Generated.Live` / `Live`, `.Generated.Action` / `Action`, and
`.Generated.Intent` / `Intent`. Scope and fragment declarations deliberately
share the Live pair. The focused resource renderer uses the core and the
aggregate registry assigns exactly one canonical home to every unique checked
production resource identity.
Repeated dependency occurrences do not create extra homes. The shared
`time-picker-config` identity, for example, has its canonical home in the Roster
day-timeline family even though Timesheets also depends on it.

The focused Live renderer selects every checked Surface scope and every fragment
with `Live`; non-passive fragments that already own an actor-local semantic key
require a typed, non-empty, reason-bearing exception. Those exceptions cover the
Admin and Admin Xero parent-page content keys. Scope and fragment
`CheckedAdapterDeclaration` values come only from kind-specific `SurfaceIR` +
`ScopeIR`/`FragmentIR` normalizers. Their kinds survive home resolution and only
the closed `LiveScope` / `LiveFragment` payload reaches the shared
`.Generated.Live` renderer.

`RegisteredSurfaceScopeAdapterHomes` and
`RegisteredSurfaceFragmentAdapterHomes` assign exactly one typed production home
to every selected declaration. Once the first production family migrated, the
staged empty-home branch was removed: empty, partial, extra, or duplicate Live
homes now fail the mandatory all-kind generation run. Independent literal
goldens in `Test.LiveUpdateSpec` continue to pin production scope JSON,
fragment-key JSON, and canonical `surfaceScopeKey` values across the replacement;
generated-vs-generic equality is not their source of truth.

Generated resource modules invoke `frontendSurfaceResource` and
`matchFrontendSurfaceResource`; generated Live modules invoke only
`frontendSurfaceScope`, `matchFrontendSurfaceScope`,
`frontendSurfaceFragmentKey`, and `matchFrontendSurfaceFragmentKey`. Only the
matching curated facade may import a production generated module. Resource and
Live facades re-export canonical constructors and retain handwritten domain
matchers or live orchestration only where they add meaning. Mechanical aliases,
generic builder/matcher bodies, and the old Billing, Support, Profile, Staff,
and Admin fragment naming synonyms are absent. Every generated-kind module must
stay behind its matching curated facade and must not import opaque internal
constructors.

The lightweight `HaskellAdapter.Association` module owns only
`SurfaceAdapterFamily` and `AdapterFamilySurface`. Production family modules and
private Live output import that seam, while reflection, registry validation, and
generator mechanics remain in `HaskellAdapter.Family` and
`HaskellAdapter.Core`. Focused feature compiles therefore do not transitively
load the generator implementation. Unsupported carriers stop generation with an
adapter-kind/Surface/declaration/field-specific diagnostic rather than falling
back to JSON, a generated carrier record, or a handwritten type. The generator
uses normal Haskell type-level reflection plus `Typeable` module/type metadata;
it does not parse source or compiler syntax trees.

The Timesheets family was the representative migration checkpoint. Its
handwritten `Resource` module moved from 35 lines to a 9-line curated facade,
removing all three mechanical bodies and 26 net handwritten lines. Generation
added an 80-line private adapter module and a 14-line feature-local family
association. A single isolated cold focused compile of the facade with
`typecheck Application/Helper/FrontendContract/Surface/Timesheets/Resource.hs`
changed from 22 modules in 9.711 seconds to 25 modules in 9.772 seconds: three
expected modules and 0.061 seconds (+0.6%) in that sample. This checkpoint was
accepted before registering the remaining homes; it is a compile-impact record,
not a benchmark.

Timesheets was also the representative Live migration checkpoint. Its
handwritten `Live` module moved from 38 lines to a 29-line curated facade,
removing all four mechanical constructor bodies and field assembly while
retaining the domain-shaped scope matcher: nine net handwritten lines deleted.
Generation added one 90-line private `.Generated.Live` module; the final bulk
registration emits seven Live modules (1,020 generated lines) alongside the
unchanged seven Resource modules. A paired same-host isolated cold focused
compile of the historical and candidate facades with
`typecheck Application/Helper/FrontendContract/Surface/Timesheets/Live.hs`
changed from 41 modules in 27.023 seconds to 44 modules in 22.979 seconds: the
three expected modules (`Generated.Live`, the feature family module, and the
lightweight association), and -4.044 seconds (-15.0%) in that sample. The module
closure, net deletion, and absence of `Family`/`Core` from the production import
closure were accepted before bulk home registration. This is a checkpoint
record, not a benchmark; cold wall-clock samples on the host were noisy.

The compiled unregistered Live fixture remains at
`Test.Support.FrontendSurfaceAdapterFixture.Generated.Live` and covers
zero-field, parameterized, actor-only, matcher, and collision behavior without
entering the production registry. Production behavior coverage also exercises
zero-field and parameterized Timesheets adapters through the curated facade.

`generateSurfaceAdapterModules` composes every implemented adapter lane,
accumulates diagnostics, and rejects duplicate physical module paths before the
script writes or removes files. Live generation is mandatory. A failed Live
lane exposes no managed module set; failure-injection coverage proves the staging
barrier leaves existing Resource, Action, and Intent files untouched and
publishes no partial Live tree. The write workflow renders, formats, and
typechecks the complete staged set before any managed stale deletion or write.

Write and verify output with:

```bash
bash ./bin/in-env frontend-surface-adapters
bash ./bin/in-env frontend-surface-adapters-check
```

The check formats a temporary rendering, compares the complete managed module
set, and rejects missing, extra, stale, or unformatted generated files.

## Runtime Implementation

Migrated surfaces expose mount behavior through
`Application.Helper.FrontendContract.Surface.Runtime.SurfaceImpl spec`.
`SurfaceImpl` is the feature-facing runtime value.

For a server-rendered mount whose controllers/views already own fragment
rendering and action routes, use `mkSurfaceImplFromValues`. It is the sole
production constructor and derives the surface name, canonical scope key, exact
scope/mount-state JSON, and live subscription from marker-indexed values in one
step. Build descriptors with `frontendSurfaceMountedFragmentFor`; it derives
fragment identity, the exact target ID, and lazy defaults from the owning
Surface declaration. Every fragment declares one `MountTarget marker fields`;
views render the same declaration through `surfaceFragmentTargetId`. Static and
parameterized target IDs therefore share the reflection naming evaluator and
declaration-ordered typed fields. URLs and protection remain mount-local.

Pass each concrete dynamic or repeated fragment set directly to that constructor
(or a feature helper that calls it). Each mounted fragment stores the opaque
semantic key created by its own Surface/fragment marker; actor planning maps
mounted keys directly and never reattaches a free-text Surface name or selects a
fragment through its target ID. There is no post-construction descriptor
patching and no generic handler/action/intent catalog on `SurfaceImpl`. Real
interaction intent forms are feature-owned marker-indexed values supplied to the
interaction shell; ordinary action routes remain next to their server-rendered
views. Compile-failure tests enforce Surface, marker, field completeness, and
transport opacity rather than ceremonial handler counts.

Render mounts with `renderFrontendSurfaceMount impl body`. This emits
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
mutations should report typed `SurfaceResourceValue` touches using the
feature-owned smart constructors in `Surface.<Feature>.Resource`, while
`Application.Helper.SurfaceResource` owns only `LiveMutationResult` and its
opaque touched-resource set. Mutations then return actor-local semantic
invalidation instructions plus extras. The actor tab and
passive viewers both refresh by resolving semantic scope and fragment keys
through mounted surface metadata and each mount's plain fragment GET URL, so
successful actor responses must not carry authoritative business OOB HTML.

## Live Authorization, Resources, And Fragment Rendering

`FrontendSurface` invalidations are semantic and surface-native:
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
or explicit `NoAuth` for public/test-only scopes. Authorization reflection lowers
to closed `ScopeAuthIR` constructors with the exact required field count. Every
referenced field must be a required UUID; missing, extra, absent, or incorrectly
typed fields fail checked-IR validation. The authorization field list contains
only fields consumed by that policy; other scope-identity fields remain separate
and must still be authorized by their fragment routes. Runtime authorization
pattern-matches those constructors and parses their carried field names; it never
redispatches policy text. `Web.SurfaceInvalidation` derives subscription authorization from
the reflected `RegisteredFrontendSurfaces` metadata; feature code must not add
hard-coded fallback authorization for a surface/scope pair.

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
by walking `RegisteredFrontendSurfaces`. The generic marker-indexed constructor
and matcher live in `Application.Helper.FrontendContract.Surface.Resource`;
feature modules such as `Surface.Roster.Resource` and
`Surface.Timesheets.Resource` expose concrete values such as
`rosterWeekResource`, `timesheetDayResource`, or `xeroConnectionResource`.
Mutation/domain code emits only those declared values. The carrier constructor
is internal, and no free resource-name/field constructor, undeclared sentinel,
custom dependency hook, or bridge conversion is supported.

The singular actor/passive planner is generated-data driven:

1. accept exact semantic keys from an actor mount or active subscription;
2. evaluate each key's fragment `DependsOn` declarations from scope/fragment params;
3. intersect those concrete dependency values with touched generated resources;
4. coalesce affected scope/fragment targets before actor delivery or passive broadcast.

Runtime/domain expansion is separate from static fragment dependency planning.
When a mutation has broad semantic effects, expand it in the producer or a small
feature-owned helper to concrete generated resources before invalidation (for
example, active roster-week resources for roster-affecting leave/staff changes).
Do not encode broad fanout as a `FrontendSurface` custom dependency or fragment
fanout DSL.

Use direct database/read-model rendering first. If profiling later proves
caching is needed, add an explicit feature-owned read-model/cache seam or
`SurfaceImpl` backend with viewer-aware keys, dependency versions, and tests.

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

Production feature surfaces use type-level `FrontendSurface` specs plus
`SurfaceImpl`. Keep one reflected registry, one checked IR, generated mount
parsers, and generated interaction/fragment registries; do not author parallel
mount metadata, registry catalogs, or cross-feature projection caches.

For a new surface or migration:

1. Define the type-level spec and add it to `RegisteredFrontendSurfaces`.
2. Implement `SurfaceImpl` handlers and render mounts with runtime helpers.
3. Move static interaction/action metadata into the spec or shared helper
   aliases, including generated source/dropzone/activation refs and their
   session/intent compatibility.
4. Render role-specific refs with `renderFrontendSurfaceSourceRef`,
   `renderFrontendSurfaceDropzoneRef`, or `renderFrontendSurfaceActivationRef`, and
   render intent forms through `SurfaceImpl`/runtime helpers so URLs, targets,
   swaps, sync, hidden values, and triggers remain server-owned.
5. Render fragments directly from feature read models.
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
bash ./bin/in-env hspec-test --match "FrontendSurface"
```

Run feature-specific Hspec/E2E checks for the migrated surface as well.
