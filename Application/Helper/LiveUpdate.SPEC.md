# Live Update And Live Surface Specification

This file describes the shared live-fragment architecture implemented by
`Application/Helper/LiveUpdate.hs`, `Application/Helper/LiveSurface.hs`,
`Web/Controller/LiveUpdates.hs`, and `static/app-live-updates.js`.

## Current Contract

- Server-rendered HTML remains the source of truth.
- Actor-local mutations return HTMX fragments or OOB swaps.
- Passive viewers receive websocket invalidation messages and refetch
  authorized fragments over HTTP.
- Server-mutating UI that can leave another mounted copy stale should use this
  live-fragment path by default: keep the actor response immediate with HTMX,
  then broadcast structural invalidations for other tabs/viewers.
- A browser tab should use one websocket connection with many scope
  subscriptions.
- A scope is an authorized logical data slice, not a page.
- Invalidation payloads are structural fragment refs, not rendered HTML.
- Fragment GET endpoints must enforce the same authorization and visibility as
  full-page routes.
- Scope keys are server-owned and carried through surface config/messages.

## Surface Declaration

For the step-by-step checklist and glossary used when adding a fragment, see
`Application/Helper/LiveSurface.COOKBOOK.md`.

Ordinary live surfaces should be declared in Haskell with
`Application.Helper.LiveSurface.TypedLiveSurfaceDefinition` and rendered on a
stable owner element as `data-live-update-surface` via
`mkTypedDefinedLiveSurface` and `liveSurfaceConfigJson`.

A surface owns:

- feature name
- websocket path
- scope and scope key
- wire-scope conversion
- authorization rule
- default resync fragments
- feature-local fragment enum to structural fragment refs
- request-decoration selectors
- optional focused-field protection policies
- a `FragmentContract` for each feature-local fragment
- semantic dependency intent for each rendered fragment
- server-side fragment containment paths used to avoid overlapping DOM swaps

Each fragment is declared through `typedSurfaceFragmentContract`, usually by
building a `FragmentContract` with `mkSurfaceFragmentContract`. The contract is
the single source for the fragment ref (`targetId`, URL, protection policy, and
containment path) and dependency intent. Use `liveFragmentDependsOn` when a
fragment is passively invalidated by semantic `LiveResource` changes, and use
`liveFragmentResyncOnly` only for fragments that have no passive resource
subscription and are refreshed by resync or actor paths.

`LiveResource` declares what business data changed. Contract dependencies declare
which fragments read those resources. The registry planner matches
changed/expanded resources against these declarations to decide which subscribed
scope fragments are stale. Fragment containment paths then normalize the selected
refs before transport: exact duplicates collapse, a child ref is dropped when an
ancestor ref is present, and sibling refs are preserved.

Containment metadata is server-only. It complements, but does not replace,
`LiveResource`: resources describe data semantics; containment paths describe DOM
ownership among already-selected fragments; structural fragment refs still
describe how the browser refetches and swaps HTML.

The wire-fragment transport boundary is internal to `Application.Helper.LiveUpdate.Internal`
and `Application.Helper.LiveSurface.Internal`. Feature modules should keep
fragment enums feature-local and cross the typed-to-wire boundary only through
strict helpers such as `mkSurfaceFragmentRef`, `mkSurfaceFragmentContract`,
`mkTypedDefinedLiveSurface`, `typedLiveSurfaceFragmentRef(s)`,
`serveTypedLiveFragment`, and projection helpers. The runtime no longer keeps
feature-facing broadcast or typed mutation helpers; typed config, projection,
dependency matching, authorization, and actor-refresh helpers derive directly
from `TypedLiveSurfaceDefinition`.

Feature-facing fragment selectors should be closed ADTs. Route/query strings may
be parsed into those constructors, but the typed surface contract should not be
backed by open `Text` values because that bypasses exhaustiveness checks.

Feature-facing code must not use compatibility/manual authoring helpers such as
`mkLiveSurface`, `mkDefinedLiveSurface`, `mkLiveFragmentRef`, raw
`LiveFragmentRef` constructors, internal `LiveUpdateWireFragment` constructors,
raw live broadcasts, raw actor-refresh payloads, or fallback
`authorizeLiveUpdateScope` checks. The `LiveSurfaceGuard` Hspec coverage
enforces this across `Web/` and feature `Application/` modules.

## Refetch And Protection

- Clients refetch only mounted invalidated fragments.
- Same-scope surface declarations should merge rather than clobber each other.
- Fragment renderers should return exactly the DOM target owned by the fragment,
  not sibling live fragments. If a broad parent and a child are both selected,
  the typed surface should rely on containment normalization instead of emitting
  overlapping swaps.
- Focused-field protection is policy-driven. Do not hard-code feature selectors
  in the shared runtime.
- Reconnect/version gaps should trigger configured resync fragments.

## LiveBus Boundary

`Application.Helper.LiveUpdate.LiveBus` is the boundary around live
subscriptions, scope versions, active-scope discovery, and invalidation
broadcasts. The default implementation is the single-process in-memory bus.

Callers should use the existing top-level live-update helpers unless a test or a
future runtime explicitly needs a different bus. Tests that need isolated
version/subscription state should create a bus with `newInMemoryLiveBus` and use
the `WithBus` helpers instead of touching global process state.

Future distributed implementations, such as Postgres `LISTEN`/`NOTIFY` or
Redis pub/sub, must preserve the public `LiveBus` contract: structural
`LiveUpdateWireFragment` invalidations, monotonically increasing versions per
`LiveUpdateScope`, and server-side authorization before websocket
subscription.

## Mutation Invalidation Boundary

`Application.Helper.LiveResource` is the business-mutation boundary for passive
live invalidation. A mutation returns `LiveMutationResult a`, where
`liveMutationValue` is the domain result and `liveMutationTouchedResources` is
the set of semantic `LiveResource` values changed by the write.

Mutation modules own three things together:

- business database writes and their audit/version side effects
- semantic touched-resource calculation, including old/new scope comparisons
- passive invalidation via `Web.LiveResourceInvalidation.invalidateTouchedResources`

Controllers should parse, authorize, choose actor response shape, and inspect
`liveMutationValue`. They should not perform passive refresh/broadcast calls
after a migrated write path. Actor-specific HTMX responses, toasts, redirects,
dialog updates, and OOB fragments may remain in controllers when they only serve
the requester.

`Web.LiveResourceInvalidation` is the planner/adapter layer. It expands indirect
semantic resources only through active-scope-bounded rules, then asks
`Web.LiveSurfaceRegistry` to match the touched/expanded `LiveResource` set
against each surface's fragment-contract dependency declarations. The registry
owns passive broadcast emission for matched scope/fragment targets. Feature
mutation modules must not call or recreate legacy feature refresh helpers such as
`refreshRosterFragments`, `refreshProfileContent`, `refreshAdminXero`,
`refreshTimesheetFragments`, or removed `broadcastSurface*` pathways.

Allowed direct live calls after migration are limited to the passive planner,
transport runtime, and actor-only response helpers:

- `Web.LiveSurfaceRegistry` is the passive adapter that turns planned targets
  into raw transport invalidations
- `Application.Helper.LiveUpdate` owns the transport bus and raw websocket
  invalidation primitives
- controllers may call `setTypedLiveSurfaceActorRefresh` or helpers that only
  set actor refresh headers for the requester
- background jobs should call a touched-resource invalidation adapter, such as
  `invalidateTouchedResourcesWithoutContext`, when passive viewers need updates
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
  request decoration, refetch, swap, dedupe, or focused-field protection.
- Add a live surface only when another actor, another tab, or an async job can
  make the mounted DOM stale.
- Fragment GET actions for typed surfaces should use `serveTypedLiveFragment`
  with the same surface key and definition that produced the fragment contract.
- Websocket subscription authorization must go through the registered typed
  surface definitions in `Web.LiveSurfaceRegistry`; unregistered wire scopes are
  denied instead of falling back to default scope authorization.
- Mutating controllers should use typed actor-only helpers, such as
  `setTypedLiveSurfaceActorRefresh`, only for requester-local refresh triggers;
  passive invalidation belongs behind touched resources.
- For broad fanout mutations, expand indirect resources only through active
  subscriptions before querying cold historical data.

## Profiling And Scalability Triage

Live-update profiling has three layers:

1. Request-scoped instrumentation in `Web.LiveResourceInvalidation` records the
   `live_resources.invalidate` span and emits `[live-invalidation]` diagnostics
   when `LIVE_INVALIDATION_PROFILING=1` is enabled.
2. `profile-live-invalidation` is a synthetic benchmark for resource expansion,
   candidate-scope derivation, registry planning, and target coalescing without
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
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Surface"
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
