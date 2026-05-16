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

The untyped transport boundary is internal to `Application.Helper.LiveUpdate.Internal`
and `Application.Helper.LiveSurface.Internal`. Feature modules should keep
fragment enums feature-local and cross the typed-to-wire boundary only through
strict helpers such as `mkSurfaceFragmentRef`, `mkTypedDefinedLiveSurface`,
`typedLiveSurfaceFragmentRef(s)`, typed broadcast helpers, and projection
helpers.

Feature-facing code must not use compatibility/manual authoring helpers such as
`mkLiveSurface`, `mkDefinedLiveSurface`, `mkLiveFragmentRef`, raw
`LiveFragmentRef` constructors, raw live broadcasts, raw actor-refresh payloads,
or fallback `authorizeLiveUpdateScope` checks. The `LiveSurfaceGuard` Hspec
coverage enforces this across `Web/` and feature `Application/` modules.

## Refetch And Protection

- Clients refetch only mounted invalidated fragments.
- Same-scope surface declarations should merge rather than clobber each other.
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
`LiveFragmentRef` invalidations, monotonically increasing versions per
`LiveUpdateScope`, and server-side authorization before websocket
subscription.

## Extension Rules

- Do not add feature-specific JavaScript adapters for normal subscribe, resync,
  request decoration, refetch, swap, dedupe, or focused-field protection.
- Add a live surface only when another actor, another tab, or an async job can
  make the mounted DOM stale.
- Fragment GET actions for typed surfaces should call
  `ensureTypedLiveSurfaceAuthorized` with the same surface key that produced the
  fragment ref.
- Websocket subscription authorization must go through the registered typed
  surface definitions in `Web.LiveSurfaceRegistry`; unregistered wire scopes are
  denied instead of falling back to default scope authorization.
- Mutating controllers should prefer typed helpers such as
  `broadcastSurfaceFragments` or `performTypedLiveSurfaceMutation` so actor refs
  and passive invalidations are declared in surface fragments, not ad hoc wire
  refs.
- For broad fanout mutations, intersect candidate scopes with active
  subscriptions before querying cold historical data.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Surface"
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
