# Live Update Runtime Simplification

Status: implemented

Parent ticket:

- `ir-y166` - simplify live-update internal runtime protocol

Child tickets:

- `ir-rp8v` - inventory live-update runtime compatibility seams
- `ir-myld` - delete untyped live-surface compatibility layer
- `ir-wqa4` - rename internal live fragment wire primitives
- `ir-r27i` - make actor refresh payloads typed-only
- `ir-mxsn` - decide compact live-update wire protocol
- `ir-cavr` - update live runtime docs and guards after simplification

Related tickets/workstreams:

- `ir-3pnb` - strict typed live-surface overhaul, implemented in `2ed1918`
- `docs/workstreams/strict-live-surface-overhaul.md`
- `ir-f2p4` - focused-field protection cleanup
- `ir-jooi` - surface projection cache work

Living docs to update as slices land:

- `Application/Helper/LiveUpdate.SPEC.md`
- `Web/Controller/AGENTS.md`
- `Web/View/AGENTS.md`
- `static/AGENTS.md`
- `Test/LiveSurfaceGuardSpec.hs`

## Goal

The strict typed live-surface overhaul removed old/manual APIs from feature
code, but some compatibility primitives still exist inside the runtime so the
browser wire JSON and projection bridge stayed stable during migration.

This workstream removes those remaining compatibility abstractions where they
no longer carry their weight, then separately decides whether to simplify the
browser protocol itself.

## Non-Goals

- Do not reintroduce feature-facing manual live-surface authoring.
- Do not weaken HTTP fragment or websocket subscription authorization.
- Do not change browser JSON shape in the first cleanup slice.
- Do not replace HTMX/server-rendered fragments with client-rendered state.
- Do not remove structural refetch metadata unless `ir-mxsn` explicitly proves
  the compact protocol path and updates browser coverage.

## Current State

Feature modules now use strict typed contracts through
`TypedLiveSurfaceDefinition`. `Web.LiveSurfaceRegistry` authorizes websocket
subscriptions through registered typed definitions, and `Test.LiveSurfaceGuard`
rejects old feature-facing API names under `Web/` and feature `Application/`.

The remaining old names are internal compatibility/runtime details:

| Primitive | Current callers from inventory | Feature-facing? | Target |
| --- | --- | --- | --- |
| `LiveSurfaceDefinition` | Defined/exported only by `Application.Helper.LiveSurface.Internal`; direct use in `Test.SurfaceProjectionSpec`; projection wrapper stores it in `ProjectionLiveSurfaceDefinition.liveSurfaceDefinition`; public `Application.Helper.LiveSurface.mkTypedSurfaceProjectionDefinition` adapts typed definitions through it. | No live feature module uses it; only test/runtime bridge. | Delete the type and projection field; compute config/projection refs directly from `TypedLiveSurfaceDefinition`. |
| `mkLiveSurface` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used only by `Test.LiveUpdateSpec` for JSON fixture construction. | No. | Delete and update tests to build config via typed definitions or record literals. |
| `mkDefinedLiveSurface` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used only by `mkTypedDefinedLiveSurface`. | No. | Delete; construct `LiveSurfaceConfig` directly in `mkTypedDefinedLiveSurface`. |
| `liveSurfaceFragmentRef(s)` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used by untyped broadcasts and projection helpers. | No. | Delete; use `typedLiveSurfaceFragmentRef(s)` and stored typed projection fragment builder fields. |
| `typedLiveSurfaceDefinition` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used by `mkTypedDefinedLiveSurface` and public `mkTypedSurfaceProjectionDefinition`. | No. | Delete; reimplement those helpers from `TypedLiveSurfaceDefinition`. |
| untyped `broadcastSurfaceFragments` | Defined/exported only by `Application.Helper.LiveSurface.Internal`; public `Application.Helper.LiveSurface.broadcastSurfaceFragments` is already typed and aliases `broadcastTypedSurfaceFragments`. | No. | Delete the internal untyped helper; keep typed public aliases. |
| `ProjectionLiveSurfaceDefinition.liveSurfaceDefinition` | Used in projection broadcasts, `mkSurfaceProjectionDefinition`, and `liveSurfaceProjectionFragmentRef`. | No. | Replace with `projectionSurfaceScope :: scope -> SurfaceScope surface` and `projectionSurfaceFragmentRef :: scope -> fragment -> SurfaceFragmentRef surface`, making `ProjectionLiveSurfaceDefinition` typed by `surface`. |
| `LiveFragmentRef` | Transport payload type in `Application.Helper.LiveUpdate.Internal`, `LiveSurfaceConfig`, `SurfaceProjectionDefinition`, controller/support tests, and contract helpers. | Not feature-facing by guard; tests/runtime only. | Rename to `LiveUpdateWireFragment` while preserving JSON keys and field names. |
| `mkLiveFragmentRef` | Constructor helper used by `mkSurfaceFragmentRef` and projection tests. | Not feature-facing. | Rename to `mkLiveUpdateWireFragment`; keep typed `mkSurfaceFragmentRef` as feature entrypoint. |
| `liveFragmentsRefreshTriggerPayload` | Used by `setLiveSurfaceActorRefresh` and `setTypedLiveSurfaceActorRefresh`; guard rejects feature use. | No current feature use, but the exported name reads API-shaped. | Replace with typed-only actor refresh helpers and a private/local transport encoder name. |
| `authorizeLiveUpdateScope` and default authorization | `authorizeLiveUpdateScope` only backs `liveSurfaceAuthorizationByScope`; default requirement used by tests. Registry already authorizes via typed definitions. | Guard rejects direct feature use. | Delete fallback function; keep explicit `LiveScopeAuthorizationRequirement` helpers for typed definitions/tests. |
| raw bus broadcasts | `Application.Helper.LiveUpdate.Internal` broadcast functions are used by typed runtime wrappers and runtime tests. | Guard rejects feature use of raw invalidation/resync helpers. | Keep as internal transport runtime; after wire fragment rename their signatures use `LiveUpdateWireFragment`. |

Inventory result: browser JSON stays stable through `ir-myld`, `ir-wqa4`, and `ir-r27i`; only Haskell type/helper names and the untyped projection bridge change before the compact-protocol decision.

## Target Layering

After cleanup, the layers should be explicit:

1. Feature authoring: feature-local surface key and fragment enum plus
   `TypedLiveSurfaceDefinition`.
2. Typed facade: `Application.Helper.LiveSurface` exports typed config,
   authorization, broadcast, mutation, projection, and actor-refresh helpers.
3. Transport runtime: internal bus, websocket JSON, versions, subscriptions, and
   transport fragment metadata.
4. Browser adapter: generic `static/app-live-updates.js` consumes mounted typed
   surface config and websocket invalidations.

The transport layer may still carry structural fragment metadata, but it should
not expose names that read like supported authoring primitives.

## Implementation Order

1. `ir-rp8v`: inventory all remaining runtime compatibility seams.
   - Run `rg` for old names across `Application/`, `Web/`, and `Test/`.
   - Update this workstream table with exact callers and final decisions.
   - Confirm whether browser JSON remains stable for the first implementation
     tickets.
2. `ir-myld`: delete the untyped surface compatibility layer.
   - Reimplement `mkTypedDefinedLiveSurface` directly.
   - Reimplement `mkTypedSurfaceProjectionDefinition` without
     `typedLiveSurfaceDefinition`.
   - Remove untyped surface config/ref/broadcast helpers.
   - Update tests that currently assert `mkLiveSurface` compatibility.
3. `ir-wqa4`: rename or quarantine internal wire fragment primitives.
   - Prefer names such as `LiveUpdateWireFragment` and
     `mkLiveUpdateWireFragment` if the rename is tractable.
   - Preserve JSON object fields unless `ir-mxsn` changes the protocol.
   - Update projection and contract-test helpers.
4. `ir-r27i`: make actor refresh payload construction typed-only.
   - Keep `setTypedLiveSurfaceActorRefresh` and mutation helpers as the entry
     points.
   - Delete or private-rename `liveFragmentsRefreshTriggerPayload`.
   - Add tests that actor and passive refs derive from the same typed fragment
     declaration.
5. `ir-mxsn`: decide compact protocol separately.
   - Option A: keep self-describing transport payloads and record an ADR note.
   - Option B: send compact fragment keys and resolve target/url/protection from
     mounted surface config, with browser migration tests.
6. `ir-cavr`: update docs, guards, and final checks.

## Compact Protocol Decision Notes

Decision for `ir-mxsn`: defer compact browser payloads and keep the current
self-describing JSON protocol. The Haskell runtime cleanup now names structural
fragment refs as internal wire fragments, but the browser still receives the
same `fragments[].fragmentKey`, `targetId`, `url`, `deferUntilBlur`, and
`protectionPolicy` fields. A compact protocol should only be revisited with a
separate migration ticket after proving stale-config, multi-surface,
actor-refresh, reconnect-resync, and focused-field behavior in browser tests.

The current protocol is self-describing: an invalidation contains fragment key,
target id, URL, focus/defer protection, and source client id. This keeps passive
refetches robust even when multiple surfaces share a scope or fragment URLs
carry query/viewer context.

A compact protocol could send only scope key plus fragment identifiers, then
resolve target/URL/protection from currently mounted surface config. That would
reduce payload size but must handle:

- multiple mounted surfaces for the same scope with different fragment sets
- dynamic URLs with query params and viewer filters
- actor refresh events where the actor may not have the passive surface mounted
- stale or invalid surface config after deploy/reconnect
- focused-field protection and deferred refresh semantics
- resync after missed versions

Changing the browser JSON shape should be treated as a protocol migration, not
part of the internal cleanup.

## Verification

Run focused checks after each slice where possible:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test --match "LiveUpdate"
bash ./bin/in-env hspec-test --match "Surface"
bash ./bin/in-env hspec-test --match "TimesheetsController"
bash ./bin/in-env hspec-test --match "SupportController"
bash ./bin/in-env hspec-test --match "live scope"
```

Run browser checks after any protocol, actor refresh, focus-protection, or
surface-config behavior change:

```bash
bash ./bin/in-env e2e e2e/live-update-declarative-adapter.spec.ts
bash ./bin/in-env e2e e2e/live-fragment-multiview.spec.ts
```

## Exit Criteria

- The untyped live-surface compatibility layer is deleted.
- Remaining internal transport types have transport-oriented names.
- Actor refresh payload encoding is private to typed actor-refresh helpers.
- The compact protocol decision is recorded; browser JSON remains unchanged.
- Guard tests enforce the new boundary.
- Durable docs reflect the simplified runtime.
