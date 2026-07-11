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
  live-fragment path by default: commit data, report touched resources, broadcast
  structural invalidations with the actor `sourceClientId`, then return an
  actor-local semantic invalidation for the requester. The browser resolves both
  actor-local and websocket invalidations through mounted surface metadata.
- A browser tab should use one websocket connection with many scope
  subscriptions.
- A scope is an authorized logical data slice, not a page.
- Invalidation payloads are structural fragment refs, not rendered HTML.
- Fragment GET endpoints must enforce the same authorization and visibility as
  full-page routes.
- Scope keys are server-owned and carried through surface config/messages. The
  websocket boundary derives the canonical key from the registered typed Surface
  scope fields and rejects a browser-supplied key or fragment descriptor whose
  Surface identity disagrees; browser keys are assertions, not authority.
- Bepis live facts are emitted by `invalidateTouchedResources*` after actual
  touched-resource expansion/planning/broadcast. This does not replace
  `SurfaceResourceValue` or FrontendSurface dependency planning; it records that the
  same invalidation helper consumed the touched-resource set used by passive
  invalidation.

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
`data-bepis-surface-config`. The old typed-live-surface compatibility layer and
legacy `data-live-update-surface` mount format have been removed.

A surface owns:

- feature/surface name
- websocket path or generated live-update transport family
- scope and scope key
- wire-scope conversion
- authorization rule
- default resync fragments
- feature-local fragment enum to structural fragment refs
- mount-local target ids and refetch URLs
- request decoration from the closest mount
- optional focused-field protection policies
- a fragment contract for each feature-local fragment
- semantic dependency intent for each rendered fragment
- server-side fragment containment paths used to avoid overlapping DOM swaps
- optional contained child-surface topology declared on fragments/regions
- optional mount state, interaction sessions/layers/effects, intents, and
  conflict policies

A fragment/region may contain child surface mounts. Containment is static
surface topology; it does not make the child part of the parent subscription.
The browser runtime treats current DOM mounts as the source of truth and must
recursively reconcile child/grandchild lifecycles after page loads and swaps:
new mounts initialize, removed mounts dispose, and websocket subscriptions remain
the union of currently mounted surface scopes.

Each live fragment declares invalidation intent in the type-level
`FrontendSurface` spec with `DependsOn` or `ResyncOnly`. `SurfaceImpl` handlers
materialize the mounted fragment target id, URL, and protection policy for the
current request. Fragments are eager by default; lazy fragments derive their load
policy, trigger, and placeholder kind from the existing `Lazy`, `Trigger`, and
`Placeholder` primitive options. Initial lazy placeholders are rendered through
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
ownership among already-selected fragments; structural fragment refs still
describe how the browser refetches and swaps HTML.

The wire-fragment transport boundary is isolated behind
`Application.Helper.LiveUpdate.Runtime`, `Application.Helper.LiveUpdate.Internal`,
and `Application.Helper.FrontendContract.Surface.Runtime`. Browser-visible live-update
contracts are owned by `Application.Helper.FrontendContract.LiveUpdate` and the
registered surface contracts: generated TypeScript exposes closed `SurfaceScope`
and `SurfaceFragmentKey` unions derived from the registered surface scope and
fragment payloads, plus generated live command/message guards, `parseX`, and
`encodeX` helpers consumed by the runtime. The Haskell carrier types live in
`Application.Helper.FrontendContract.Wire.LiveUpdate`; their Aeson parse/render
validates against `registeredFrontendContractIR` through
`Application.Helper.FrontendContract.Wire.Json`, so the DSL/IR remains the only
browser-visible wire authority.
Feature modules should keep fragment enums feature-local and cross the
typed-to-wire boundary only through strict helpers. Feature modules cross the
surface-to-wire boundary through `SurfaceImpl`/`renderFrontendSurfaceMount` and
mount-local fragment/action/intent handlers. The runtime no longer keeps
feature-facing broadcast, typed-live compatibility, or typed mutation helpers.

Actor responses and passive live updates should use one semantic fragment model
with multiple delivery triggers. A feature-local fragment enum and `SurfaceImpl`
name the fragments once. For migrated `FrontendSurface` successful mutations,
the actor response emits selected semantic fragment refs as an actor-local
invalidation instruction; prefer `setActorLiveResourcesRefresh` when the mutation
already reports touched `SurfaceResourceValue`s so actor-local refresh and
passive websocket invalidation use the same dependency planner. The browser
resolves those refs against every matching mounted surface instance in the
current tab and refetches each mount's own plain fragment GET URL. Passive
viewers receive the same structural invalidations over websocket and refetch
through their mounted GET endpoints. Actor responses may append extras such as
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
`LiveFragmentRef` constructors, internal `SurfaceWireFragment` constructors,
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
the generated UI-region DOM attribute constants, event constants, and `UiRegionTransitionProfile` contract, but
it must not invent attribute names, fragment names, routes, target ids, or
business semantics. After that, the generic adapter may
emit `bepis:region-request-start`, `bepis:region-before-swap`,
`bepis:region-after-swap`, `bepis:region-settle`, and `bepis:region-error` for
that region only.

## Refetch And Protection

- Clients refetch only mounted invalidated fragments. An invalidation descriptor
  is resolved by exact scope key and structural fragment key to each matching
  local mount descriptor; its incoming URL, target id, and protection policy are
  never executed and there is no fallback when the fragment is not locally
  mounted.
- Same-scope surface declarations should merge rather than clobber each other.
- Fragment renderers should return exactly the DOM target owned by the fragment,
  not sibling live fragments. If a broad parent and a child are both selected,
  the typed surface should rely on containment normalization instead of emitting
  overlapping swaps.
- Focused-field protection is policy-driven. Do not hard-code feature selectors
  in the shared runtime.
- Reconnect/version gaps should trigger configured resync fragments.
- Lazy placeholders use the same target id and GET URL as the loaded fragment
  and carry any feature-owned root slot classes needed to match final layout
  geometry, so live invalidations before the lazy trigger may safely replace the
  placeholder with authorized server-rendered HTML.

## LiveBus Boundary

`Application.Helper.LiveUpdate.Runtime.LiveBus` is the boundary around live
subscriptions, scope versions, active-scope discovery, and invalidation
broadcasts. The default implementation is the single-process in-memory bus.

Feature callers should use the safe `Application.Helper.LiveUpdate` facade for
scope/key/protection types and version reads. Runtime, registry, websocket, and
transport tests use `Application.Helper.LiveUpdate.Runtime` for raw wire
fragments, broadcasts, subscriptions, and isolated `LiveBus` helpers.

Future distributed implementations, such as Postgres `LISTEN`/`NOTIFY` or
Redis pub/sub, must preserve the public `LiveBus` contract: structural
`SurfaceWireFragment` invalidations, monotonically increasing versions per
`SurfaceScope`, and server-side authorization before websocket
subscription.

## Mutation Invalidation Boundary

`Application.Helper.SurfaceResource` is the business-mutation boundary for passive
live invalidation. A mutation returns `LiveMutationResult a`, where
`liveMutationValue` is the domain result and `liveMutationTouchedResources` is
the set of semantic `SurfaceResourceValue` values changed by the write.

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

`Web.SurfaceInvalidation` is the planner/orchestration layer. It receives
concrete generated `SurfaceResourceValue`s, applies the small set of approved
active-scope-bounded domain expansions, then matches those resources against
generated `FrontendSurface` dependency metadata. The planner derives affected
fragments from active mounted fragments plus each fragment's declared
`DependsOn` fields; it owns passive broadcast emission for matched
scope/fragment targets. Feature
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

- `Web.SurfaceInvalidation` is the passive planner that turns matched mounted
  fragments into raw transport invalidations
- `Application.Helper.LiveUpdate.Runtime` owns the transport bus and raw
  websocket invalidation primitives
- controllers may call FrontendSurface actor-local invalidation helpers that
  only set semantic refresh instructions for the requester
- background jobs should call the touched-resource invalidation boundary, such
  as `invalidateTouchedResourcesWithoutContext`, when passive viewers need updates
- controllers and mutation modules must not call typed broadcast/mutation
  helpers for passive updates; those compatibility pathways have been removed

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
  target node. Legacy typed helpers remain compatibility-only.
- Websocket subscription authorization must go through registered generated
  surface metadata and `Web.SurfaceInvalidation`; unregistered wire scopes are
  denied instead of falling back to default scope authorization.
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
2. `profile-live-invalidation` is a synthetic benchmark for resource expansion,
   candidate-scope derivation, dependency planning, and target coalescing without
   websocket clients.
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
