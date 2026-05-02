# Live Update And Live Surface Specification

This file describes the shared live-fragment architecture implemented by
`Application/Helper/LiveUpdate.hs`, `Application/Helper/LiveSurface.hs`,
`Web/Controller/LiveUpdates.hs`, and `static/app-live-updates.js`.

## Current Contract

- Server-rendered HTML remains the source of truth.
- Actor-local mutations return HTMX fragments or OOB swaps.
- Passive viewers receive websocket invalidation messages and refetch
  authorized fragments over HTTP.
- A browser tab should use one websocket connection with many scope
  subscriptions.
- A scope is an authorized logical data slice, not a page.
- Invalidation payloads are structural fragment refs, not rendered HTML.
- Fragment GET endpoints must enforce the same authorization and visibility as
  full-page routes.
- Scope keys are server-owned and carried through surface config/messages.

## Surface Declaration

Ordinary live surfaces should be declared in Haskell with
`Application.Helper.LiveSurface.LiveSurfaceConfig` and rendered on a stable
owner element as `data-live-update-surface`.

A surface owns:

- feature name
- websocket path
- scope and scope key
- default resync fragments
- request-decoration selectors
- optional focused-field protection policies

## Refetch And Protection

- Clients refetch only mounted invalidated fragments.
- Same-scope surface declarations should merge rather than clobber each other.
- Focused-field protection is policy-driven. Do not hard-code feature selectors
  in the shared runtime.
- Reconnect/version gaps should trigger configured resync fragments.

## Extension Rules

- Do not add feature-specific JavaScript adapters for normal subscribe, resync,
  request decoration, refetch, swap, dedupe, or focused-field protection.
- Add a live surface only when another actor, another tab, or an async job can
  make the mounted DOM stale.
- For broad fanout mutations, intersect candidate scopes with active
  subscriptions before querying cold historical data.

## Verification

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```
