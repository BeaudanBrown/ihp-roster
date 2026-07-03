# Type-Level FrontendSurface Contracts

Status: implementation record. The DSL, GHC extraction/generation,
`SurfaceImpl` runtime bridge, support lab, Timesheets migration, Roster
migration, and SurfaceProjection removal have landed. Durable authoring rules now
live in `Application/Helper/FrontendSurface/README.md` and the subsystem
README/SPEC/AGENTS files; this workstream remains as architectural context until
`ir-9ogo` closes.

Tickets:

- Epic: `ir-9ogo` - Type-level FrontendSurface contract generator
- `ir-8w6w` - Define and enforce FrontendSurface naming policy
- `ir-npm8` - Design FrontendSurface mount-local transport and unified invalidation flow
- `ir-p3c3` - Define legacy and FrontendSurface registry coexistence
- `ir-g6z3` - Draft FrontendSurface architecture contract docs
- `ir-ennr` - Build type-level FrontendSurface lab
- `ir-xopg` - Generate surface TypeScript and DTO contracts from GHC API
- `ir-4hu6` - Prove typed SurfaceImpl completeness
- `ir-yupd` - Wire FrontendSurface generator into Nix/dev scripts
- `ir-ycec` - Add FrontendSurface guardrails and compile-failure checks
- `ir-aleo` - Migrate Timesheets to FrontendSurface spec
- `ir-ypt5` - Migrate Roster to FrontendSurface spec
- `ir-ds06` - Document FrontendSurface authoring workflow
- `ir-s7la` - Remove replaced FrontendCodec and old live-surface contract paths

## Intent

Replace the current frontend contract and live-surface authoring stack with a
surface-centered architecture where static browser protocol facts are declared in
fully type-level `FrontendSurface` specs. Runtime code supplies only dynamic
behavior through `SurfaceImpl`: concrete scope values, authorization, versions,
fragment URLs/target ids/renderers, concrete live-resource dependencies,
HTMX/intent behavior, mount metadata, and mount-state backend behavior.

The final target removes/replaces author-facing surface contract machinery based
on `FrontendCodec`, `FrontendSchema`, manual DTO schema groups,
`TypedLiveSurfaceDefinition`, `Web.LiveResourceInvalidation`, and the removed generic
server render cache for migrated surfaces. Renderer-internal IR/data structures
may remain when they are fed only by the new
`SurfaceContractIR`.

Server-rendered HTML remains authoritative. The architecture improves how the
browser contract is declared and generated; it does not move business authority
or persistence into TypeScript. The durable authoring rules live in the local README/SPEC/AGENTS files updated
by `ir-ds06`; this workstream records the architecture and migration decisions.

## Root Source Of Truth

Generation starts from a single explicit type-level registry containing only
surfaces. The registry module is
`Application.Helper.FrontendSurface.Registry`; the current migrated surface specs
live under `Application.Helper.FrontendSurface` as `Lab`, `Timesheets`, and
`Roster`, with runtime/view helpers in the relevant feature modules where useful.

```haskell
type RegisteredFrontendSurfaces =
    '[ SurfaceLabSurface
     , TimesheetsSurface
     , RosterSurface
     ]
```

Do not introduce a separate top-level scope registry initially. Shared scopes,
DTOs, events, DOM tokens, sessions, layers, field aliases, and helper bundles are
included by type aliases inside surface specs. After helper expansion, the
extractor merges identical shared declarations and rejects conflicting ones.

Example shared declaration reuse:

```haskell
type RosterWeekScope =
    Scope RosterWeek
        '[ Field VenueId WireUUID
         , Field RosterGroupId WireUUID
         , Field WeekOffset WireInt
         ]

type RosterSurface =
    Surface Roster
        '[ RosterWeekScope
         , Fragment RosterRow
            '[ Field RosterDayId WireUUID
             , Field RowIndex WireInt
             ]
            '[ Eager ]
         ]

type RosterSummarySurface =
    Surface RosterSummary
        '[ RosterWeekScope
         , Fragment SummaryTotals '[] '[ Eager ]
         ]
```

The shared `RosterWeekScope` is generated once and used by both surfaces. If a
second surface declares `Scope RosterWeek` with different fields, generation
fails with a clear conflict error.

The same explicit type-level list is also the source for runtime enumeration.
Each listed surface supplies exactly one `SurfaceImpl spec` through a small
`HasSurfaceImpl spec`-style interface, and a typeclass fold derives the runtime
registry used for planning, authorization, manifests, and generic helpers. There
must not be a second hand-maintained runtime list for migrated surfaces; a
registered surface without an impl should fail compilation.

## Hybrid Registry Coexistence

During migration, the application has two registry families with an explicit
boundary:

- Legacy `TypedLiveSurfaceDefinition` surfaces remain in `Web.LiveResourceInvalidation`
  and continue to emit self-describing wire fragments containing concrete
  `targetId`, `url`, protection, and containment metadata.
- Migrated `FrontendSurface` surfaces live only in
  `Application.Helper.FrontendSurface.Registry` as members of
  `RegisteredFrontendSurfaces`. Their runtime metadata is derived from
  `HasSurfaceImpl` instances by a typeclass fold over that type-level list.

`Web.LiveResourceInvalidation` may remain the temporary orchestration module for
shared planner/authorization entrypoints, but it must consume the derived
`FrontendSurface` registry rather than re-listing migrated surfaces. In other
words, a migrated surface can flow through a legacy-named compatibility function,
but the migrated surface's membership comes only from `RegisteredFrontendSurfaces`.

Hybrid planning is a concatenation of two derived target sets:

```text
touched LiveResource set + active scopes
  -> surface-native dependency planner
       -> legacy self-describing wire-fragment invalidations
  -> FrontendSurface dependency planner
       -> mount-resolved surface/scope/fragment invalidations
  -> websocket/actor delivery envelope containing one or both target kinds
```

The browser runtime keeps both transport interpreters during migration. Legacy
mounts process concrete wire fragments exactly as they do today. New mounts
ignore legacy fragment payloads and resolve only `FrontendSurface` invalidations
for their own surface/scope/mount metadata.

Manifest generation follows the same split. Legacy `LiveSurfaceManifest` remains
derived from legacy surface entries for non-migrated surfaces. New generated
surface contracts/manifests are derived from `RegisteredFrontendSurfaces`. A
surface family name must not appear in both registries at the same time; the
migration step for a surface removes its legacy catalog entry in the same slice
that adds it to the type-level registry. Guardrails in `ir-ycec` should fail on
cross-registry duplicate surface names and on migrated surfaces using old
feature-facing authoring paths.

Authorization remains server-side and registry-specific:

- legacy surfaces authorize through their existing `TypedLiveSurfaceDefinition`
  values;
- migrated surfaces authorize through `SurfaceImpl` handlers derived from the
  type-level registry;
- shared controller entrypoints may ask both registries whether a wire scope is
  authorized during the hybrid period.

Final unification removes the legacy registry adapter, old manifest sections, and
self-describing wire-fragment transport after all surfaces migrate. At that point
all live invalidation planning, authorization, manifest output, request
decoration, and browser refresh behavior derive from `RegisteredFrontendSurfaces`
and `SurfaceImpl`.

## DSL Normal Form

Specs are fully type-level. Do not infer contracts from arbitrary Haskell value
expressions. The canonical syntax normalizes to:

```haskell
Surface SurfaceMarker '[ primitive, primitive, primitive ]
```

Core primitives are promoted data constructors. Marker names are ordinary
nullary data types at kind `Type`. Wire field types are a closed promoted
universe with namespaced constructors such as `WireText`, `WireInt`,
`WireBool`, `WireUUID`, `WireDay`, `WireList t`, `WireOptional t`,
`WireNullable t`, and `WireRef DtoMarker`; specs do not use bare domain names
such as `Text` or `UUID` for browser wire types.

Type synonyms and approved DSL helper type families are allowed only as
authoring sugar that expand to primitive normal form. V1 supports type synonyms,
closed type families from approved DSL helper modules, list append/concat and
flattening, and nested option lists. Arbitrary feature-specific type-family
logic and recursion are out of scope. Helper composition is allowed; expansion
cycles fail generation with a clear diagnostic naming the cycle.

Initial primitive set:

```haskell
Surface name capabilities
Scope name fields
Fragment name params options
HtmxAction name fields options
Intent name fields options
Field name type
OptionalField name type
NullableField name type
MountState name fields
Session name options
DisposableLayer name
InteractionEffect kind fields
ConflictPolicy sessionSelector fragmentSelector resolution
LoadPolicy kind
OverlayLane name
ClientEvent name detail
DomToken name
Dto name fields
```

A flat top-level list is syntax. The normalized contract graph still validates
relationships between primitives.

Validation uses a closed set of declaration and reference kinds so cross
references remain exhaustive. Declaration kinds include surface, scope,
fragment, HTMX action, intent, field, DTO, mount state, session, layer, effect,
overlay lane, client event, and DOM token. Reference options such as `Target`,
`BackedBy`, `Layer`, `Session`, `Emits`, `UsesDto`, and `Contains` each map to
exactly one expected declaration kind. Missing or wrong-kind references fail
generation, and the implementation should keep the mapping covered by
`-Werror=incomplete-patterns`.

### Example Surface

```haskell
type SurfaceLabSurface =
    Surface SurfaceLab
        '[ Scope LabScope
            '[ Field VenueId WireUUID
             , Field WeekOffset WireInt
             ]

         , MountState LabViewState
            '[ Field ShowArchived WireBool
             , OptionalField StaffFilterId WireUUID
             ]

         , Fragment LabShell '[] '[ Eager ]
         , Fragment LabPanel '[ Field PanelId WireUUID ] '[ Lazy '[ Trigger Load, Placeholder Panel ] ]

         , HtmxAction RefreshPanel
            '[ Field PanelId WireUUID ]
            '[ Target LabPanel ]

         , Intent MoveLabCard
            '[ Field SourceItemKey WireText
             , Field TargetDropzoneKey WireText
             ]
            '[ BackedBy RefreshPanel ]

         , Session DragSession '[]
         , DisposableLayer DragPreview
         , InteractionEffect CloneShadow '[ Layer DragPreview ]
         , InteractionEffect DropzoneHighlight '[]
         , ConflictPolicy DragSession LabPanel Defer

         , OverlayLane Dialog
         , ClientEvent LabCommitted '[ Field PanelId WireUUID ]
         , DomToken LabRoot
         , DomToken LabDropzone

         , Dto LabPayload
            '[ Field Label WireText
             , OptionalField Count WireInt
             , NullableField Note WireText
             ]
         ]
```

## Field And Wire Type Universe

Frontend fields use a closed browser-boundary wire type universe. Do not expose
arbitrary database/domain records to TypeScript.

Supported initial shapes:

- `WireText`
- `WireInt`
- `WireBool`
- `WireUUID`
- `WireDay`
- `WireList t`
- optional field presence through `OptionalField`
- nullable values through `NullableField` or equivalent `Nullable t`
- references to declared DTOs via `WireRef DtoMarker`

Fields are context-sensitive: the same `Field` primitive describes scope fields,
fragment params, action/intent fields, event details, mount state, or DTO fields.
The containing primitive determines semantics.

Meaningful ID fields should generate branded TypeScript aliases while preserving
primitive JSON wire shapes:

```ts
export type RosterDayId = string & { readonly __brand: "RosterDayId" };
```

Runtime parsers still validate the primitive shape, e.g. string/UUID format.

## Naming Policy

Names are derived from marker types by global policy.

- Robust word splitting preserves acronym runs: `HTMXAction -> htmx-action`, not
  `h-t-m-x-action`; `XeroOAuthCallback -> xero-oauth-callback`.
- Contextual suffix stripping:
  - `Surface`, `Scope`, `Fragment`, `Intent`, `Action`, `Session`, `Layer`,
    `Field`.
- Do not strip feature prefixes automatically at first.
- New `FrontendSurface` protocol names prefer lower kebab for surfaces,
  fragments, actions, intents, sessions, layers, DOM tokens, and events.
  Existing legacy live-update tags keep their current snake names during hybrid
  migration; the final unified protocol should be consistent after legacy paths
  are removed.
- Canonical marker examples use clean marker names without role suffix where
  practical, e.g. `data Roster; type RosterSurface = Surface Roster ...`.
  Contextual suffix stripping still supports authoring markers such as
  `RosterSurface` or `RosterFragment` when that improves readability.
- Intent/action/session/layer names are lower kebab.
- JSON fields are lower camel.
- DOM attributes/tokens use `data-bepis-` plus lower kebab where attributes are
  generated.
- Event names use a generated namespace plus lower kebab.
- Exact-name escape hatch is type-level, rare, allowlisted in a generator-owned
  naming allowlist module, and reported by the generator. Do not use value-level
  escape hatches. Unauthorized exact names fail generation with marker, context,
  requested name, and an instruction to add a justified allowlist entry.

Name collisions fail generation in the relevant namespace. Duplicate checks use
namespace plus generated protocol name; fully qualified Haskell names are
diagnostic metadata. Shared declarations with the same marker/name are allowed
only when their normalized declarations are identical and the namespace is
shareable.

## GHC API Extractor

The extractor is Nix/devenv-owned and starts from the explicit registry module.
It loads/types the registry using the same project package set as canonical
checks, exposing the GHC API package only through the generator command path.
Normal app builds may import the lightweight registry and type-level specs for
runtime enumeration, but GHC API use is script-only and must not be an app
runtime dependency.

Pipeline:

1. Load `RegisteredFrontendSurfaces`.
2. Resolve and normalize type synonyms, helper aliases, required type families,
   list append/flattening, and nested options to primitive normal form.
3. Build raw extracted surfaces close to the type syntax.
4. Derive protocol names from markers.
5. Merge identical shared declarations and reject conflicts.
6. Lower to `SurfaceContractIR`.
7. Validate the graph.
8. Render generated TypeScript and runtime metadata.

The extractor must support all lab, Timesheets, and Roster needs without
feature-specific special cases. It must support parametrized fragment shapes
without sample IDs.

### SurfaceContractIR

The main checked IR is a graph like:

```haskell
data SurfaceContractIR = SurfaceContractIR
    { surfaces     :: Map SurfaceName SurfaceIR
    , scopes       :: Map ScopeName ScopeIR
    , dtos         :: Map DtoName DtoIR
    , domTokens    :: Map DomTokenName DomTokenIR
    , clientEvents :: Map EventName EventIR
    , overlayLanes :: Set OverlayLaneName
    }

data SurfaceIR = SurfaceIR
    { surfaceName :: SurfaceName
    , marker      :: TypeRef
    , scope       :: ScopeName
    , mountState  :: Maybe MountStateName
    , fragments   :: Map FragmentName FragmentIR
    , actions     :: Map ActionName ActionIR
    , intents     :: Map IntentName IntentIR
    , sessions    :: Map SessionName SessionIR
    , layers      :: Map LayerName LayerIR
    , effects     :: [EffectIR]
    , policies    :: [ConflictPolicyIR]
    }
```

Fields carry marker/source info, derived JSON name, wire type, presence, and
optional brand name.

Validation covers malformed specs, unsupported wire types, duplicate/conflicting
shared declarations, duplicate field names, one normalized scope per surface,
invalid cross references, invalid exact-name usage, and namespace collisions.
Diagnostics should include marker/type name, declaration or reference kind,
derived protocol name, source module/span when available, and suggested fix;
tests should assert stable diagnostic substrings rather than exact spans.

## Generated TypeScript

Generated TypeScript may change shape where cleaner than current contracts, but
must remain generated and consumption-friendly. It should include:

- branded aliases for meaningful IDs;
- shared scope DTOs;
- surface-local fragment key unions;
- mount-state DTOs;
- DTO/event payload types;
- intent/action/session/layer closed vocabularies;
- live-update transport envelopes;
- guards, parsers, and encoders;
- constants/manifests required by generic runtime code.

The final source of generated surface/live/interaction contracts is
`RegisteredFrontendSurfaces`, not manual DTO schema modules. During hybrid
migration, legacy contract sections may coexist in generated output for
non-migrated surfaces; migrated surfaces must be generated only from the new
registry.

The generator may emit a deterministic compact checked debug manifest or IR JSON
if useful for reviewers/runtime metadata. Avoid large noisy checked-in IR unless
it becomes a valuable drift gate.

## Haskell Encoding And Parsing

V1 uses reusable typeclass/reflection machinery over the closed DSL/wire-type
universe. It should derive Haskell JSON, URL/query, and field encode/decode
behavior for scopes, fragment params, DTOs, event details, intent/action fields,
and mount state without writing per-surface `ToJSON`/`FromJSON` instances by
hand.

This is not universal arbitrary Haskell serialization. Unsupported field/domain
types should fail at compile time or generator validation. V1 should not generate
Haskell ADT modules; use reflected typed field-list/HList values with ergonomic
helpers/accessors. Generated Haskell records may be added later if implementation
ergonomics become painful, especially during Roster.

## SurfaceImpl Runtime Bridge

`SurfaceImpl spec` replaces `TypedLiveSurfaceDefinition` as the feature-facing
runtime bridge. Missing required handlers should be compile-time errors where
practical.

`SurfaceImpl` owns dynamic behavior:

- concrete scope values and wire/scope key conversion;
- authorization;
- current version/freshness;
- fragment URL builders;
- fragment target id builders;
- fragment renderers;
- concrete live-resource dependencies;
- HTMX method/action/target/swap details;
- intent/action behavior;
- mount key and metadata;
- mount-state backend behavior;
- role-dependent visibility/rendering.

Parametrized fragments/actions require one handler per marker accepting typed
params, not one handler per concrete instance. Authors fill typed handler records
or builders indexed by the spec and expose them through a `HasSurfaceImpl spec`
instance/value. Type families compute the required handler slots from the
normalized spec so missing required handlers fail compilation.

First implementation uses direct DB/read-model rendering only. The removed generic
server render cache is not part of the new core and must not be used by lab,
Timesheets, or Roster. Optional cached backends can be added later behind
`SurfaceImpl`.

`SurfaceImpl` supplies browser contract metadata and rendering. Existing IHP
controllers remain the mutation entrypoints for this epic: they parse,
authorize, validate, mutate, and report touched resources. A later ticket may
explore generic intent dispatch through `SurfaceImpl` if repeated controller
boilerplate justifies it.

## Live Updates And Invalidation

Keep `LiveResource` as the semantic mutation boundary, but change the
successful-update flow for new `FrontendSurface` surfaces to be mount-resolved
and universal. The server plans invalidations once, then delivers the same
semantic invalidation through two request-correlated channels:

1. A mutation writes data and reports touched business resources.
2. The live planner finds affected active scopes/surfaces and asks `SurfaceImpl`
   which surface-local candidate fragments depend on the touched resources.
3. The server returns the actor HTMX response with only non-authoritative extras
   and an actor-local invalidation instruction. Extras include toast/dialog
   cleanup, disposable-layer cleanup, focus/scroll hints, or validation-local
   failure fragments. A successful mutation response must not carry the updated
   authoritative business fragment HTML for migrated surfaces.
4. The server also broadcasts the same semantic invalidation over the websocket
   to all subscriptions for the affected scope, tagged with the actor tab's
   `sourceClientId` when the mutation came from a browser request.
5. The actor tab processes the HTMX-delivered invalidation and suppresses its own
   websocket echo (`sourceClientId == activeClientId`) to avoid duplicate and
   racy refreshes. Other tabs, duplicate clients, and passive viewers process the
   websocket invalidation normally.
6. Each browser mount resolves the invalidation against its own mount-local
   metadata and refetches authorized server-rendered HTML. If the same
   surface/scope is mounted twice in one tab, both mounts refetch using their own
   target ids, URLs, protection policy, and mount state.

Type-level specs declare dependency kinds/intents. `SurfaceImpl` resolves
concrete resources from scope/fragment params. Example:

```haskell
Fragment TimesheetDaySection
    '[ Field DayOffset WireInt ]
    '[ DependsOn TimesheetDay ]
```

Runtime resolver:

```haskell
dependencies TimesheetDaySection scope params =
    [ TimesheetDayResource scope.venueId scope.weekOffset params.dayOffset ]
```

Shared scopes are allowed across surfaces. Scope answers “what data slice is
mounted?” Surface answers “which UI/fragments should refetch for that data
slice?” Fragment keys are surface-local; migrated transport envelopes carry
surface, scope, and fragment identity so each mount can resolve its own target
ids, URLs, protection, and mount state.

### Mount-Resolved Transport Contract

Legacy live-update wire fragments are concrete and self-describing. A migrated
`FrontendSurface` invalidation is semantic and mount-resolved. It identifies the
surface, logical scope, and surface-local fragments, but not concrete DOM target
ids or GET URLs:

```json
{
  "protocol": "frontend-surface-v1",
  "surface": "timesheets",
  "scope": { "kind": "timesheet-week", "venueId": "...", "weekOffset": 0 },
  "scopeKey": "timesheets:...:0",
  "version": 42,
  "sourceClientId": "optional-browser-client-id",
  "fragments": [
    { "kind": "timesheet-day-section", "params": { "dayOffset": 2 } }
  ]
}
```

The checked generated DTO names may differ, but the semantic boundaries are
fixed:

- `surface` is a generated `FrontendSurface` surface name.
- `scope` is the generated wire DTO for the declared scope.
- `scopeKey` is a server-generated stable key for grouping active subscriptions;
  the browser must not synthesize it from field values.
- `version` is the semantic scope/resource version used for gap/stale handling.
- `sourceClientId` is present when a browser-originated mutation supplied a
  client id; the same tab suppresses websocket echoes with this id.
- `fragments` are generated surface-local fragment keys with typed params. They
  are not URLs, CSS selectors, or global target ids.

Each mounted surface renders a mount-local config, generated from `SurfaceImpl`,
that lets the browser resolve semantic fragment keys into concrete request and
swap metadata:

```json
{
  "surface": "timesheets",
  "scopeKey": "timesheets:...:0",
  "mountKey": "primary",
  "mountState": { "showApproved": false, "showAllStaff": true },
  "fragments": {
    "timesheet-day-section:{\"dayOffset\":2}": {
      "targetId": "timesheets-primary-day-2",
      "url": "/Timesheets/day-section?...",
      "protection": { "kind": "replace" },
      "loadPolicy": { "kind": "eager" }
    }
  }
}
```

The fragment-map key is generated by the runtime from the generated fragment DTO;
it is shown as a string only to explain lookup behavior. Author code must not
hand-build these keys.

### Actor, Duplicate-Mount, And Passive Request Flow

For a page with two mounts of the same surface/scope:

1. The initial page GET renders two mount configs with the same `surface` and
   `scopeKey` but different `mountKey` values and different target ids/URLs.
2. The browser subscribes once per logical scope, while retaining both mount
   records locally.
3. An HTMX mutation from mount A is decorated from the closest mount. The server
   receives the client id, surface, scope key, mount key, and any mount-state
   metadata needed by the action.
4. On success, the server returns extras plus an actor-local invalidation; it
   also broadcasts the websocket invalidation for the same scope/fragments.
5. The actor tab suppresses the websocket echo but resolves the actor-local
   invalidation for both mount A and mount B. Each mount performs its own
   authorized fragment GETs and swaps into its own targets.
6. Other tabs/viewers receive the websocket invalidation and perform the same
   local resolution/refetch for their mounted copies.

Validation failures are the intentional exception: the mutation response may
return the submitted form or dialog fragment directly to the HTMX target so field
errors stay localized. Validation failures do not broadcast invalidations unless
they also committed a business mutation.

During migration the app uses a hybrid protocol: legacy surfaces keep the current
self-describing wire fragments (`targetId`, `url`, protection policy), while
migrated `FrontendSurface` surfaces use mount-resolved surface fragment
invalidations. The final target is unified and consistent: all live surfaces move
to the new protocol and legacy live paths are removed. Stale browser tabs from a
previous deploy may stop functioning until reload; this is acceptable as long as
failures are safe and do not corrupt state or authorize unintended mutations.

Versions remain semantic scope/resource ordering signals, not per-mount caches.
Viewer- or mount-state-dependent HTML is fetched fresh from the server on each
fragment request. Background-plannable surfaces can decide affected fragments
from active scopes and touched resources without a current controller context;
Timesheets should be background-plannable, the lab can be request-context-only,
and Roster should target background planning where practical while allowing a
request-context-only fallback if role/viewer-dependent planning requires it.

## Request Decoration

Do not carry forward selector-list request decoration as the preferred model.
In the new architecture every mounted surface has a typed mount root. The generic
HTMX hook decorates requests from the closest surface mount by default. Duplicate
and nested mounts resolve through `closest(...)`, so a control inside mount B
uses mount B metadata even when mount A has the same surface/scope.

Use generated headers for generic live metadata:

- `X-Bepis-Client-Id`: browser tab/client id used for websocket echo
  suppression;
- `X-Bepis-Surface`: generated surface name;
- `X-Bepis-Scope-Key`: server-generated scope key from the closest mount;
- `X-Bepis-Mount-Key`: mount-local key;
- `X-Bepis-Mount-State`: optional generated/encoded mount-state payload or
  fingerprint when the action needs view state.

Generated hidden inputs remain the source for intent/action fields. Query params
are used only for explicitly query-backed mount state such as the initial
Timesheets filters. Opt-out or explicit-only decoration should be added only if a
concrete request requires it. This replaces current `decorateRequestsWithin`
string lists for migrated surfaces.

## Mount State

Mount/view state is distinct from live subscription scope. Type-level
`MountState` declares state shape. `SurfaceImpl` supplies the backend.

Timesheets will initially preserve current query-param behavior behind a typed
query-backed mount-state backend. Defaults stay `ShowApproved = False`,
`ShowAllStaff = True`, and `StaffFilterId = Nothing`; query names remain
`showApproved`, `showAllStaff`, and `staffFilterId`, with blank/invalid staff
ids normalizing to `Nothing`. Future DB-backed user/venue/mount state should
be able to replace the backend without changing the surface spec.

Do not introduce in-memory server state for production view state.

## Surface Lab Acceptance

The first implementation target is a support-super-admin-only lab page. It must:

- define every initial primitive in the type-level DSL;
- use marker types and derived names;
- include at least one helper alias expansion;
- mount with a minimal `SurfaceImpl` scaffold that later `ir-4hu6` strengthens
  into full completeness proofs;
- render an eager fragment and lazy fragment;
- exercise one real HTMX action and one intent path;
- emit/consume generated TypeScript contract shapes;
- avoid old author-facing `FrontendCodec`, DTO schema groups,
  `TypedLiveSurfaceDefinition`, `Web.LiveResourceInvalidation`, manual
  `InteractionStaticSchema`, and raw protocol attrs in lab views.

## Timesheets Migration

Timesheets is the first production migration.

- Scope: `TimesheetWeek` with `VenueId` and `WeekOffset`.
- Mount state: current filters (`ShowApproved`, `ShowAllStaff`, optional
  `StaffFilterId`) with initial query-param backend.
- Fragments:
  - `TimesheetToolbar`
  - `TimesheetDayColumns`
  - `TimesheetDaySection '[ Field DayOffset WireInt ]`
- Runtime: direct DB/read-model rendering through `SurfaceImpl`; no generic
  server render cache.
- Successful actor mutations emit touched resources/surface invalidations and
  let the actor, duplicate mounts, and passive viewers refetch through the same
  live path. Fragment GET routes use new surface helpers. Validation failures may
  still render local form/dialog errors directly.
- Live dependencies resolve concrete `TimesheetWeekResource` and
  `TimesheetDayResource` values from scope/params.

Timesheets splits the old request-key shape into a logical scope
value (`venueId`, `weekOffset`) and `TimesheetsMountState` (`showApproved`,
`showAllStaff`, `staffFilterId`). The current passive-planning workaround that
reconstructs default filters and relies on mounted `data-live-update-url` should
be removed for the migrated surface; each mount resolves its own refetch URL from
mount-local config/state. Acceptance includes removal of old Timesheets
legacy live-surface authoring paths.

## Roster Migration

Roster is the complex proof.

- Scope: reusable `RosterWeek` with `VenueId`, `RosterGroupId`, `WeekOffset`.
- Fragments:
  - content, grid toolbar, grid frame, day columns, day rail, wage rail, slots
    grid, staff panel;
  - `RosterDaySection '[ Field RosterDayId WireUUID ]`;
  - `RosterRow '[ Field RosterDayId WireUUID, Field RowIndex WireInt ]`.
- Containment uses typed fragment relationships, not raw target-id paths.
- Staff panel lazy policy is declared as a fragment option.
- Drag/drop helper sugar expands to primitives: session, disposable layer,
  effects, intent/action fields, and conflict policies.
- Fragment-specific conflict policies must be supported, not only `AnyFragment`.
- Role-dependent visibility, authorization, version/freshness, and rendering live
  in `SurfaceImpl`.
- Duplicate mounts are required to work; all generated ids/forms/layers/fragments
  are mount-local and TypeScript resolves from closest surface mount. Stable
  semantic classes/data/test attributes should replace tests or CSS that depend
  on exact global ids.
- No generic server render cache.
- Fragment-specific conflict policies support at least `AnyFragment`, fragment
  kind selectors, and fragment subtree selectors. Concrete param predicates may
  wait unless Roster proves they are necessary.
- Successful actor mutations emit invalidations/touched resources; actor HTTP
  responses carry extras such as toasts/dialog cleanup or validation-local
  errors.

## Guardrails And Verification

Expected gates across the epic:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "FrontendSurface"
bash ./bin/in-env hspec-test --match "LiveSurface"
bash ./bin/in-env hspec-test --match "Interaction"
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env ./bin/doc-drift-check
```

Add a Nix-owned focused compile-failure check for missing `SurfaceImpl` handlers.
Use focused Hspec/generator tests for naming, normalization, merge/conflict
validation, unsupported types, cross-reference kind validation, stale generated
output, and old-path guardrails. Use frontend unit/DOM
checks for generated TypeScript consumption and exhaustive handling. Use E2E only
when browser/HTMX/live behavior is part of the contract.

## Migration Order

1. Naming policy (`ir-8w6w`).
2. Mount-local transport and unified invalidation design (`ir-npm8`).
3. Legacy/new registry coexistence design (`ir-p3c3`).
4. Draft architecture contract docs (`ir-g6z3`).
5. DSL, minimal `SurfaceImpl` scaffold, and support lab (`ir-ennr`).
6. GHC API extractor and generated TypeScript/runtime metadata (`ir-xopg`).
7. `SurfaceImpl` completeness (`ir-4hu6`).
8. Nix/dev script integration (`ir-yupd`).
9. Guardrails and compile-failure checks (`ir-ycec`).
10. Timesheets migration (`ir-aleo`).
11. Roster migration (`ir-ypt5`).
12. Living docs update (`ir-ds06`).
13. Old-path removal for migrated surfaces (`ir-s7la`).

As implementation lands, move durable facts from this workstream into the local
README/SPEC/AGENTS files listed in `ir-ds06`.
