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
- Bepis live facts are emitted by `invalidateTouchedResources*` after actual
  touched-resource expansion/planning/broadcast. This does not replace
  `LiveResource` or registry planning; it records that the same invalidation
  helper consumed the touched-resource set used by passive invalidation.

## Surface Declaration

For the step-by-step checklist and glossary used when adding a fragment, see
`Application/Helper/LiveSurface.COOKBOOK.md`. For new type-level surface
authoring, see `Application/Helper/FrontendSurface/README.md`. For typed
disposable layers, intent forms, generated browser contracts, and live-fragment
conflict policy, see `Application/Helper/Interaction.SPEC.md`.

Declarative UI region capabilities are a browser-facing layer on top of
server-owned fragments. Haskell owns the allowed `data-bepis-*` names,
transition profile vocabulary, and lifecycle event names in
`Application.Helper.UiRegion`; `frontend/ts/generated/contracts.ts` exposes
matching unions, guards, and constants. The frontend HTMX adapter is deliberately
thin: it translates raw HTMX events into Bepis region events only for
`data-bepis-fragment="true"` roots, and downstream lazy/retry/transition code is
parameterized by those server-rendered attrs.

New or migrated live surfaces should be declared with a type-level
`FrontendSurface` spec in `Application.Helper.FrontendSurface.Registry` and
rendered with `SurfaceImpl` helpers as `data-bepis-surface` plus
`data-bepis-surface-config`. Existing non-migrated legacy surfaces may continue
to use `Application.Helper.LiveSurface.TypedLiveSurfaceDefinition` and
`data-live-update-surface` until their own migration ticket replaces them.

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
- optional mount state, interaction sessions/layers/effects, intents, and
  conflict policies

Each fragment is declared through `typedSurfaceFragmentContract`, usually by
building a `FragmentContract` with `mkSurfaceFragmentContract`. The contract is
the single source for the fragment ref (`targetId`, URL, protection policy, and
containment path), dependency intent, and load policy. Fragments are eager by
default. Use `liveFragmentDescriptorWithLazyLoad` on descriptor-based surfaces or
`fragmentContractWithLazyLoad` on hand-written typed definitions when a
secondary expensive fragment should render a shared lazy placeholder first and
fetch the same authoritative GET URL on demand. Use `liveFragmentDependsOn` when
a fragment is passively invalidated by semantic `LiveResource` changes, and use
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

The wire-fragment transport boundary is isolated behind
`Application.Helper.LiveUpdate.Runtime`, `Application.Helper.LiveUpdate.Internal`,
`Application.Helper.LiveSurface.Internal`, and the migrated
`Application.Helper.FrontendSurface.Runtime` bridge. Browser wire DTOs live in
`Application.Helper.Frontend.Dto.LiveUpdate` plus generated FrontendSurface
contracts and provide TypeScript types, guards, `parseX`, and `encodeX` helpers
consumed by the runtime. Feature modules should keep fragment enums
feature-local and cross the typed-to-wire boundary only through strict helpers.
For migrated surfaces that means `SurfaceImpl`/`renderFrontendSurfaceMount` and
mount-local fragment/action/intent handlers. For still-legacy surfaces that means
helpers such as `mkSurfaceFragmentRef`, `mkSurfaceFragmentContract`,
`mkTypedDefinedLiveSurface`, `typedLiveSurfaceFragmentRef(s)`,
`serveTypedLiveFragment`, `respondWithTypedLiveSurfaceFragments`, and typed
fragment normalization helpers. The runtime no longer keeps feature-facing
broadcast or typed mutation helpers.

Actor responses and passive live updates should use one fragment model with
multiple triggers. A feature-local fragment enum and either a migrated
`SurfaceImpl` or a legacy `TypedLiveSurfaceDefinition` names the fragments once;
successful actor HTMX responses render selected fragments immediately as OOB
swaps, while passive viewers receive structural invalidations and refetch the
same fragments through their GET endpoints. Actor responses may append extras
such as toasts or dialog clears after the normalized OOB fragments.

Prefer a simple, non-cached feature-local fragment model for new migrations:
fetch the model once, normalize requested fragments with the typed surface
helpers, render those fragments in `FragmentPlain` or `FragmentOob` mode, and
append extras. If a future ticket intentionally opts into cache behavior, add it
behind the feature read-model or `SurfaceImpl` seam rather than adding a shared
author-facing cache helper. Feature code should not recreate local
`renderXxxOob` actor helpers when a shared typed fragment model can render the
same fragments.

Validation failures are the main exception: return the submitted form or dialog
fragment directly to the request target so field errors stay localized. Do not
force validation failures through the unified actor-success helper, and do not
turn fragment GET endpoints into OOB responses; GET endpoints return the plain
target node and the browser/live runtime performs the swap.

Feature-facing fragment selectors should be closed ADTs. Route/query strings may
be parsed into those constructors, but the typed surface contract should not be
backed by open `Text` values because that bypasses exhaustiveness checks. Unknown
JSON at browser boundaries should be accepted only through generated `parseX`
helpers, and outbound browser commands should use generated `encodeX` helpers.

Feature-facing code must not use compatibility/manual authoring helpers such as
`mkLiveSurface`, `mkDefinedLiveSurface`, `mkLiveFragmentRef`, raw
`LiveFragmentRef` constructors, internal `LiveUpdateWireFragment` constructors,
raw live broadcasts, raw actor-refresh payloads, or fallback
`authorizeLiveUpdateScope` checks. The `LiveSurfaceGuard` Hspec coverage
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
`UiRegionDom`, `UiRegionEvents`, and `UiRegionTransitionProfile` contracts, but
it must not invent attribute names, fragment names, routes, target ids, or
business semantics. After that, the generic adapter may
emit `bepis:region-request-start`, `bepis:region-before-swap`,
`bepis:region-after-swap`, `bepis:region-settle`, and `bepis:region-error` for
that region only.

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
- Lazy placeholders use the same target id and GET URL as the loaded fragment,
  so live invalidations before the lazy trigger may safely replace the
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
- `Application.Helper.LiveUpdate.Runtime` owns the transport bus and raw
  websocket invalidation primitives
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
