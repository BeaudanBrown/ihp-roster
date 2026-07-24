# Live Update And Live Surface Specification

This file describes the shared live-fragment architecture implemented by
`Application/Helper/LiveUpdate.hs`, migrated `FrontendSurface` helpers,
websocket controllers, and `static/app-live-updates.js`.

## Current Contract

- Server-rendered HTML remains the source of truth.
- Migrated `FrontendSurface` successful mutations return actor-local semantic
  invalidation instructions plus extras, not authoritative business HTML/OOB.
- Passive viewers receive websocket invalidation messages and refetch
  authorized fragments over HTTP.
- Server-mutating UI that can leave another mounted copy stale should use this
  live-fragment path by default: commit data, report touched resources, and run
  actor mount keys plus passive subscription keys through the same dependency
  planner. Passive broadcasts carry the actor `sourceClientId`; actor responses
  emit only their coalesced non-empty target keys. The browser resolves both
  actor-local and websocket invalidations through mounted surface metadata.
- A browser tab should use one websocket connection with many scope
  subscriptions.
- A scope is an authorized logical data slice, not a page.
- Subscription, websocket invalidation, and actor-event payloads carry canonical
  `SurfaceFragmentKey` values only, never executable URLs, targets, selectors,
  defer flags, or protection policies.
- Fragment GET endpoints must enforce the same authorization and visibility as
  full-page routes.
- Each `data-bepis-surface-config` value is parsed through the generated exact
  per-surface `FrontendSurfaceMountConfig` union. Unknown properties, malformed
  scope/fragment/protection values, or a mismatch with the owner element's
  generated `data-bepis-surface` value are rejected and reported; they never
  fall back to a handwritten aggregate parser.
- The websocket endpoint, client-id header, and surface mount/action/config DOM
  attributes are reflected global constants consumed by both Haskell and
  generated TypeScript. Runtime code must not duplicate their string values.
  Live TypeScript imports the generated fragment registry only; interaction
  TypeScript imports a separate interaction registry. Server-only action,
  intent/DTO, and containment metadata does not enter either bundle.
- Scope keys are server-owned and carried through surface config/messages. Typed
  construction canonicalizes from the exact reflected scope field list; this
  also lets unregistered compiled contract fixtures exercise the same algorithm.
  The websocket boundary still validates against registered production Surfaces
  and rejects browser-supplied scope or fragment keys whose Surface identity
  disagrees; browser keys are assertions, not authority.
- Bepis live facts are emitted by `invalidateTouchedResources*` after actual
  touched-resource expansion/planning/broadcast. Their target and target-fragment
  counts describe coalesced executable targets, not hypothetical candidate or
  planning scopes.

## Surface Declaration

For the step-by-step checklist and glossary used when adding a fragment, see
`Application/Helper/FrontendContract/Surface/README.md`. For typed disposable layers,
intent fields, generated browser contracts, and live-fragment conflict policy,
see `Application/Helper/Interaction.SPEC.md`.

Declarative UI region capabilities are a browser-facing layer on top of
server-owned fragments. Haskell owns the allowed `data-bepis-*` names,
transition profile vocabulary, and lifecycle event names in
`Application.Helper.UiRegion`; `frontend/ts/generated/contracts.ts` exposes
matching unions, guards, and constants. The frontend HTMX adapter is deliberately
thin: it translates raw HTMX events into Bepis region events only for
`data-bepis-fragment="true"` roots, and downstream lazy/retry/transition code is
parameterized by those server-rendered attrs.

Production live surfaces must be declared with a type-level `FrontendSurface`
spec in `Application.Helper.FrontendContract.Surface.Registry` and rendered with
`SurfaceImpl` helpers as `data-bepis-surface` plus
`data-bepis-surface-config`. This is the only production mount format.

A surface owns:

- feature/surface name
- the shared generated live-update transport constants
- scope and scope key
- wire-scope conversion
- authorization rule
- default resync fragments
- feature-local fragment enum to canonical semantic fragment keys
- mount-local target ids and refetch URLs
- request decoration from the closest mount
- optional focused-field protection policies
- a fragment contract for each feature-local fragment
- semantic dependency intent for each rendered fragment
- server-side fragment containment paths used to avoid overlapping DOM swaps
- optional contained child-surface topology declared on fragments/regions
- optional server-side mount state, interaction sessions/layers/effects,
  intents, and conflict policies

A fragment/region may contain child surface mounts. Containment is static
surface topology; it does not make the child part of the parent subscription.
The browser runtime treats current DOM mounts as the source of truth and must
recursively reconcile child/grandchild lifecycles after page loads and swaps:
new mounts initialize, removed mounts dispose, and websocket subscriptions remain
the union of currently mounted surface scopes.

Each live fragment declares invalidation intent in the type-level
`FrontendSurface` spec with `DependsOn` or `ResyncOnly`. One-step `SurfaceImpl`
runtime values materialize the mounted fragment target id, URL, and protection policy for the
current request. Fragments are eager by default; `Lazy`, `Trigger`, and
`Placeholder` options control server-rendered lazy placeholders without adding
browser mount `loadPolicy` fields. Initial lazy placeholders are rendered through
the canonical `FrontendSurface` lazy-fragment runtime helper, which emits the
same target id and GET URL as the loaded fragment plus generated UI-region attrs
such as `data-bepis-fragment` and `data-bepis-lazy-surface`. Feature views own
layout slot classes via the lazy render config. Use `DependsOn` when a fragment
is passively invalidated by semantic
`SurfaceResourceValue` changes, and use `ResyncOnly` only for fragments that
have no passive resource subscription and are refreshed by resync or actor
paths.

`SurfaceResourceValue` declares what business data changed. FrontendSurface dependency
contracts declare which fragments read those resources. The dependency planner
matches changed/expanded resources against active surface-native subscriptions to
decide which mounted scope fragments are stale. Fragment containment paths then
normalize the selected refs before transport: exact duplicates collapse, a child
ref is dropped when an ancestor ref is present, and sibling refs are preserved.

Containment metadata is server-only. It complements, but does not replace,
`SurfaceResourceValue`: resources describe data semantics; containment paths describe DOM
ownership among already-selected fragments. Semantic fragment keys cross the
transport boundary; each browser's local mount descriptor alone determines how
that browser refetches and swaps HTML.

The semantic-key transport boundary is isolated behind
`Application.Helper.LiveUpdate.Runtime`, `Application.Helper.LiveUpdate.Internal`,
`Application.Helper.FrontendContract.Surface.Live`, and
`Application.Helper.FrontendContract.Surface.Runtime`. `SurfaceScope` and
`SurfaceFragmentKey` constructors are visible only to the transport internals.
The public live facades expose opaque carriers. Private feature-adjacent
`.Generated.Live` modules construct and match them with the marker-indexed,
declaration-complete functions in `Surface.Live`; each private module is imported
only by its matching curated `Surface.<Feature>.Live` facade. Feature code uses
those canonical facade exports, while handwritten facade logic is limited to
domain-shaped matching and active-scope orchestration. Generic transport,
authorization, dependency planning, coalescing, and bus code may inspect internal
transport identity mechanically, but it contains no feature Surface, fragment,
or field catalog.

Browser-visible live-update
contracts are owned by `Application.Helper.FrontendContract.LiveUpdate` and the
registered surface contracts: generated TypeScript exposes closed `SurfaceScope`
and `SurfaceFragmentKey` unions derived from the registered surface scope and
fragment payloads, generated canonical fragment-key identity/equality, and live
command/message/actor-detail guards, `parseX`, and `encodeX` helpers consumed by
the runtime. The Haskell carrier ADTs live in
`Application.Helper.FrontendContract.Wire.LiveUpdate`. Their Aeson instances use
the marker-indexed record/event/tagged-union interface in
`Application.Helper.FrontendContract.Wire.Carrier`: field names, presence,
recursive wire source types, discriminator, case tags, and complete inbound case
handlers all come from registered declarations. Inbound unknown JSON is checked
exactly against `registeredFrontendContractIR` and is then mapped from direct
typed field values to the ergonomic carrier constructor; there is no JSON
encode/decode round trip or carrier-side string dispatch. The same reflected
Surface IR generates the
exact mount envelope for every registered surface: `{ surface, scopeKey,
mountKey, fragments, subscription }`. Each local descriptor is exactly `{
fragmentKey, targetId, url, protection }`; the optional subscription contains
only the typed `scope`. Live/resync keys are derived from the mounted descriptors
and reflected `Live` fragment set, so configs do not duplicate key lists.
Server-side `MountState` remains available to Haskell renderers and route
builders but is not emitted as a browser contract when the browser has no
consumer.
Feature modules should keep fragment enums feature-local and cross the
typed-to-wire boundary only through strict helpers. Scope/fragment construction
uses complete `SurfaceFields`; scope/fragment matching returns complete typed
field values and never raw JSON. Mounted fragments retain the opaque semantic
key created by their owning marker, so actor helpers map mounted keys directly
rather than reconstructing identity from a Surface name or target ID. Feature
modules cross the surface-to-key boundary through
`SurfaceImpl`/`renderFrontendSurfaceMount` and mount-local
fragment/action/intent handlers. The runtime exposes semantic-key transport and
typed mutation response helpers only through its focused public facades.

Actor responses and passive live updates should use one semantic fragment model
with multiple delivery triggers. A feature-local fragment enum and `SurfaceImpl`
name the fragments once. For migrated `FrontendSurface` successful mutations,
the actor response emits selected semantic fragment refs as an actor-local
invalidation instruction. Successful resource-backed mutations use
`setActorLiveResourcesRefresh`, which submits their exact mounted keys to the same
planner used for passive subscription keys. `setActorLocalFragmentsRefresh` is
reserved for explicit requester-local workflows where no shared resource changed.
Empty dependency plans emit no actor trigger. The browser
resolves those refs against every matching mounted surface instance in the
current tab and refetches each mount's own plain fragment GET URL. Passive
viewers receive the same semantic keys over websocket and refetch through their
own mounted GET endpoints. Actor responses may append extras such as
toasts or dialog clears, but successful actor responses must not include
authoritative business OOB HTML for the refreshed fragments.

Prefer a simple, non-cached feature-local fragment model for new migrations:
keep a single authoritative plain fragment renderer behind `SurfaceImpl` and
fragment GET actions, then select semantic fragments for actor-local/passive
invalidation. If a future ticket intentionally opts into cache behavior, add it
behind the feature read-model or `SurfaceImpl` seam rather than adding a shared
author-facing cache helper. Feature code should not recreate local
`renderXxxOob` actor helpers for migrated success paths; OOB is reserved for
extras and documented legacy seams.

Validation failures are the main exception: return the submitted form or dialog
fragment directly to the request target so field errors stay localized. Do not
force validation failures through the actor-local success helper. Do not turn
fragment GET endpoints into OOB responses; GET endpoints return the plain target
node and the browser/live runtime performs the swap.

Feature-facing fragment selectors should be closed ADTs. Route/query strings may
be parsed into those constructors, but the typed surface contract should not be
backed by open `Text` values because that bypasses exhaustiveness checks. Use
parameterized fragments/resources for homogeneous repeated regions whose key is
the natural invalidation boundary (`DependsOn ... FromFragment ...`). Do not
parameterize unrelated page tabs or panels when dependencies, permissions, forms,
or response modes differ materially; distinct fragments are clearer in that case.
Unknown JSON at browser boundaries should be accepted only through generated
`parseX` helpers, and outbound browser commands should use generated `encodeX`
helpers.

Feature-facing code must not use compatibility/manual authoring helpers such as
`mkLiveSurface`, `mkDefinedLiveSurface`, `mkLiveFragmentRef`, raw
`LiveFragmentRef` constructors, executable transport-fragment descriptors,
raw live broadcasts, raw actor-refresh payloads, or fallback
`authorizeSurfaceScope` checks. The `SurfaceGuard` Hspec coverage
enforces this across `Web/` and feature `Application/` modules.

## UI Region Lifecycle Boundaries

`data-bepis-fragment="true"` is the opt-in boundary for generic Bepis UI
region lifecycle events. The HTMX adapter listens to raw HTMX lifecycle events,
but it only emits `bepis:region-*` events when the HTMX source or target is
inside a server-declared fragment region. TypeScript must not infer regions from
routes, target ids, CSS classes, or feature names.

Use UI region attrs for server-owned DOM that is intentionally replaceable as a
unit, such as typed live fragments and lazy fragment placeholders. Do not add
`data-bepis-fragment` to ordinary HTMX controls just to reuse a spinner or
animation. In particular, keep these out of the region lifecycle unless a future
ticket deliberately defines a typed region contract for them:

- dialog, picker, and toast overlay lanes;
- validation-local form or dialog responses that must preserve field errors at
  the submitted target;
- partial navigation, page-shell swaps, and auth/layout transitions;
- ordinary local controls, autosave widgets, filters, sort buttons, and form
  helpers that are not live-fragment roots;
- feature-specific one-off HTMX snippets whose routes, target ids, or business
  meaning are not declared by Haskell live-surface/region helpers.

When a current HTMX interaction should become a region, migrate it through the
Haskell contract first: closed fragment/region identity, stable target id,
authoritative GET URL, optional lazy/retry/transition attrs, and focused-field
or interaction conflict policy if needed. TypeScript may read the generated
generated UI-region DOM attribute constants, event constants, and the `UiRegionTransitionProfile` contract, but
it must not invent attribute names, fragment names, routes, target ids, or
business semantics. After that, the generic adapter may
emit `bepis:region-request-start`, `bepis:region-before-swap`,
`bepis:region-after-swap`, `bepis:region-settle`, and `bepis:region-error` for
that region only.

## Refetch And Protection

- Clients refetch only mounted invalidated fragments. An incoming semantic key
  is resolved by exact scope key and canonical fragment-key equality to every
  matching local mount descriptor. Only that local descriptor's URL, target id,
  and protection policy are used; there is no fallback when the key is not
  locally mounted. Transport messages and actor details are also parsed by the
  generated exact scope/fragment guards, so extra descriptor-shaped fields are
  rejected rather than ignored. HTMX injects an `elt` carrier property when it
  dispatches an `HX-Trigger` event; the browser removes only that property after
  verifying it equals the event target, then submits the untouched server
  payload to the exact generated actor parser.
- Parameterless mounted fragment keys serialize `params` as `{}`, matching the
  server wire normalization. Structural matching does not depend on top-level
  JSON property order.
- A single actor or websocket invalidation may carry multiple fragment keys;
  every key resolves against the same mounted-subscription snapshot, including
  when subscriptions originate from a one-shot iterator such as `Map.values()`.
- Same-scope surface declarations should merge rather than clobber each other.
- Fragment renderers should return exactly the DOM target owned by the fragment,
  not sibling live fragments. If a broad parent and a child are both selected,
  the typed surface should rely on containment normalization instead of emitting
  overlapping swaps.
- Focused-field protection is policy-driven. Do not hard-code feature selectors
  in the shared runtime. The generated local descriptor supplies an exact
  `activeSelector`, `fieldKeyAttr`, `fieldNameFallback`, and nullable
  `containerSelector`; the browser must not recover missing values through old
  `data-live-field-key` or feature defaults.
- `frontend/ts/live-updates/focus.ts` is the single focused-field protection
  owner. It defers the latest protected fragment while a matching field is
  focused, captures its exact configured key/name/value, refetches on blur, and
  restores that value in the replacement row/container. Keep this as the only
  DOM replacement/focus-protection owner. Fragments with `replace` protection,
  including roster shift launchers, refresh immediately.
- `frontend/ts/app-live-updates.ts` is orchestration-only. Mount parsing,
  subscription merge/request scoping, websocket/reconnect lifecycle,
  invalidation/version routing, authorized fragment fetch/swap, HTMX request
  decoration, focus protection, and diagnostics each have one focused module
  under `frontend/ts/live-updates/`. Subscription diagnostics, not a
  `data-live-update-client-id` DOM write, are the readiness signal for E2E.
- Reconnect/version gaps should trigger configured resync fragments through the
  same protection decision as ordinary actor/passive invalidations.
- Lazy placeholders use the same target id and GET URL as the loaded fragment
  and carry any feature-owned root slot classes needed to match final layout
  geometry, so live invalidations before the lazy trigger may safely replace the
  placeholder with authorized server-rendered HTML.

## LiveBus Boundary

`Application.Helper.LiveUpdate.Runtime.LiveBus` is the boundary around live
subscriptions, scope versions, active-scope discovery, and invalidation
broadcasts. The default implementation is the single-process in-memory bus.

Feature callers should use the safe `Application.Helper.LiveUpdate` facade for
scope/key types and version reads. Runtime, registry, websocket, and transport
tests use `Application.Helper.LiveUpdate.Runtime` for semantic fragment keys,
broadcasts, subscriptions, and isolated `LiveBus` helpers.

Future distributed implementations, such as Postgres `LISTEN`/`NOTIFY` or
Redis pub/sub, must preserve the public `LiveBus` contract: semantic
`SurfaceFragmentKey` invalidations, monotonically increasing versions per
`SurfaceScope`, and server-side authorization before websocket
subscription.

## Mutation Invalidation Boundary

`Application.Helper.SurfaceResource` is the business-mutation boundary for passive
live invalidation. A mutation returns `LiveMutationResult a`, where
`liveMutationValue` is the domain result and `liveMutationTouchedResources` is
the set of semantic, opaque `SurfaceResourceValue` values changed by the write.
Concrete values come from the owning `Surface.<Feature>.Resource` module. Those
modules build declaration-complete values through `frontendSurfaceResource` and
use `matchFrontendSurfaceResource` for typed domain expansion; feature code
cannot construct or inspect raw resource names and JSON fields.

Mutation modules own three things together:

- business database writes and their audit/version side effects
- semantic touched-resource calculation, including old/new scope comparisons
- passive invalidation via `Web.SurfaceInvalidation.invalidateTouchedResources`

Controllers should parse, authorize, choose actor response shape, and inspect
`liveMutationValue`. They should not perform passive refresh/broadcast calls
after a migrated write path. For migrated `FrontendSurface` success paths,
controllers may return actor-local semantic invalidation plus requester-only
extras such as toasts and dialog updates; authoritative business OOB fragments
must stay out of success responses. Validation-local direct fragments and
legacy/non-FrontendSurface exceptions must be explicit.

`Application.Helper.FrontendContract.Surface.DependencyPlanner` is the singular
pure actor/passive planning seam. It receives concrete marker-indexed
`SurfaceResourceValue`s plus exact mounted/subscribed semantic keys, evaluates
reflected `DependsOn` metadata without constructing resource values or
redispatching feature names, and returns coalesced scope/fragment targets.
`Web.SurfaceInvalidation` observes active subscriptions and owns passive broadcast
orchestration. Domain expansion stays in feature modules such as
`Web.RosterWeeks.SurfaceInvalidation`; the generic planner contains no feature
resource-name switch. Feature
mutation modules must not call or recreate legacy feature refresh helpers such as
`refreshRosterFragments`, `refreshProfileContent`, `refreshAdminXero`,
`refreshTimesheetFragments`, or removed `broadcastSurface*` pathways.

Authoring a passive live update now means:

1. declare a `Resource` in the relevant `FrontendSurface` spec;
2. add `Live` plus either `DependsOn Resource '[FromScope ..., FromFragment ...]`
   or `ResyncOnly` to each affected fragment;
3. emit the generated resource smart constructor from mutation/domain code;
4. if the mutation is broader than one concrete resource, expand it in the
   producer or a feature-owned helper to concrete generated resources before
   calling invalidation;
5. run frontend surface contract, guardrail, typecheck, and focused live tests.

The static `FrontendSurface` layer only models concrete resource-to-fragment
matching. It does not provide custom dependency hooks, legacy bridge conversion,
or a fragment fanout primitive. If many producers repeat the same broad
expansion, introduce a typed domain helper that projects the domain event to
concrete generated resources before the planner boundary.

Allowed direct live calls after migration are limited to the passive planner,
transport runtime, and actor-only response helpers:

- `Web.SurfaceInvalidation` orchestrates active passive subscriptions and turns
  shared planner targets into key-only transport invalidations
- `Application.Helper.LiveUpdate.Runtime` owns the transport bus and raw
  websocket invalidation primitives
- controllers use `setActorLiveResourcesRefresh` for successful mutations;
  cross-surface mutations pass every affected mounted fragment candidate (for
  example, staff profile changes invalidate both roster content and the roster
  staff panel), allowing the resource planner to select and normalize the actor
  refetches
- `setActorLocalFragmentsRefresh` is limited to requester-local, non-resource workflows
- background jobs should call the touched-resource invalidation boundary, such
  as `invalidateTouchedResourcesWithoutContext`, when passive viewers need updates
- controllers and mutation modules must not bypass touched resources with
  direct typed broadcast/mutation helpers for passive updates

When adding or migrating a mutation flow:

- keep exported functions semantic, e.g. `updateStaffMember` or
  `submitXeroDraftTimesheetsMutation`, rather than generic CRUD wrappers
- compute touches from business meaning, not table names, unless no narrower
  resource exists
- keep passive invalidation labels stable and descriptive, e.g.
  `"xero.timesheets.submit"`
- split helpers that mix passive broadcasts with actor refresh triggers so the
  passive part goes through touched resources, then delete the passive helper
- add mutation-boundary coverage in `Test/MutationBoundarySpec.hs` for direct DB
  writes in controllers and direct refresh/broadcast calls in migrated mutation
  modules

## Extension Rules

- Do not add feature-specific JavaScript adapters for normal subscribe, resync,
  request decoration, refetch, swap, dedupe, nested lifecycle reconciliation, or
  focused-field protection.
- Add a live surface only when another actor, another tab, or an async job can
  make the mounted DOM stale.
- New production fragment GET actions should render through the relevant
  `SurfaceImpl`/FrontendSurface fragment handler and return the authoritative
  target node. Do not retain a legacy fragment-helper compatibility path.
- Websocket subscription authorization must go through registered generated
  surface metadata and `Web.SurfaceInvalidation`. Checked `ScopeAuthIR` owns the
  closed policy constructor and exact required UUID fields; runtime code must not
  recover policy behavior from reflected text. Unregistered or malformed wire
  scopes are denied instead of falling back to default scope authorization.
- Mutating controllers should use actor-only refresh helpers only for
  requester-local refresh triggers; passive invalidation belongs behind touched
  resources.
- For broad fanout mutations, expand indirect resources only through active
  subscriptions before querying cold historical data.

## Profiling And Scalability Triage

Live-update profiling has three layers:

1. Request-scoped instrumentation in `Web.SurfaceInvalidation` records the
   `surface_resources.invalidate` span and emits `[live-invalidation]` diagnostics
   when `LIVE_INVALIDATION_PROFILING=1` is enabled.
2. `profile-live-invalidation` remains the synthetic benchmark for resource
   expansion, dependency planning over active subscriptions, and actual target
   coalescing without websocket clients. Its eventual retention/removal belongs
   to the profiling workstream rather than this runtime contract.
3. `profile-live-load` is a k6 websocket profile that starts an isolated profile
   server and DB by default, subscribes live clients, performs mutations, and
   records invalidation delivery latency.

Use `profile-live-load --scenario=mixed-live` for app-wide live-update triage.
It spreads subscribers across support, admin invites, timesheets, roster weeks,
and leave requests, then mutates those surfaces through normal touched-resource
invalidation. The report at `output/profile-live-load/latest/live-profile.md`
starts with an `Agent Snapshot` intended for future agents: checks, mutation
burst rate, invalidation delivery rate, own-invalidation coverage, slowest
server invalidation labels, and highest-fanout labels.

Interpret results by separating layers:

- high `plan_ms` or `expand_ms` means the dependency/resource planner needs
  attention
- high `broadcast_ms` with many subscribers means fanout/transport is the
  limiting path
- high mutation HTTP p95 with low `[live-invalidation] total_ms` means the
  business endpoint or setup/login load is slow, not the live invalidation
  architecture
- `profile_live_failed_mutations` means the endpoint/request failed before a
  successful invalidation can be expected
- `profile_live_missed_own_invalidations` means a successful mutation did not
  echo an invalidation to the actor; investigate source client ids, scope and
  resource dependencies, websocket lifetime, and transport fanout
- missing own invalidations after failed mutations are downstream symptoms, not
  proof that the live bus lost a message
- high fragment counts indicate a surface dependency may be too broad, or that
  sibling fragments could safely be decomposed while parent/child overlaps remain
  normalized at the typed-surface boundary

Recommended local commands:

```bash
bash ./bin/in-env profile-live-invalidation \
  --scopes=0,10,100,500,1000,2500,5000 \
  --iterations=100

bash ./bin/in-env profile-live-load \
  --scenario=mixed-live \
  --subscribers=100 \
  --mutators=10 \
  --venues=4 \
  --weeks=3 \
  --warmup-ms=3000 \
  --hold-ms=12000 \
  --max-duration=35s
```

A `100` subscriber / `10` mutator mixed run is the current practical baseline.
Use larger synchronized bursts, such as `200` subscribers / `25` mutators, as
stress probes to find failure thresholds rather than as routine verification.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-check
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Surface"
bash ./bin/in-env ./bin/style-audit
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

For UI region-only frontend changes, `frontend-check` covers the generated
contract drift, TypeScript unit/DOM tests for the HTMX adapter, lazy retry, and
transition profiles, plus checked-in JS drift.
