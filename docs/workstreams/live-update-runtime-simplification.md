# Live Update Runtime Simplification

Status: implemented; compact-protocol decision superseded by GitHub #145;
focused-field cleanup completed by GitHub #56

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
- `ir-f2p4` / GitHub #56 - focused-field protection cleanup (completed)

Living docs to update as slices land:

- `Application/Helper/LiveUpdate.SPEC.md`
- `Web/Controller/AGENTS.md`
- `Web/View/AGENTS.md`
- `static/AGENTS.md`
- `Test/SurfaceGuardSpec.hs`

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
`TypedLiveSurfaceDefinition`. `Web.SurfaceInvalidation` authorizes websocket
subscriptions through registered typed definitions, and `Test.SurfaceGuard`
rejects old feature-facing API names under `Web/` and feature `Application/`.

The remaining old names are internal compatibility/runtime details:

| Primitive | Current callers from inventory | Feature-facing? | Target |
| --- | --- | --- | --- |
| old untyped surface bridge | Removed during cleanup. | No. | Keep deleted. |
| `mkLiveSurface` | Removed from the live-surface facade/internal runtime; retained only as a forbidden identifier in `Test.SurfaceGuard`. | No. | Keep deleted; use typed definitions for config construction. |
| `mkDefinedLiveSurface` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used only by `mkTypedDefinedLiveSurface`. | No. | Delete; construct `LiveSurfaceConfig` directly in `mkTypedDefinedLiveSurface`. |
| `liveSurfaceFragmentRef(s)` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used by untyped broadcasts. | No. | Delete; use `typedLiveSurfaceFragmentRef(s)` and stored typed projection fragment builder fields. |
| `typedLiveSurfaceDefinition` | Defined/exported by `Application.Helper.LiveSurface.Internal`; used only by `mkTypedDefinedLiveSurface`. | No. | Delete; reimplement config construction from `TypedLiveSurfaceDefinition`. |
| typed/direct broadcast helpers (`broadcastSurface*`, `broadcastTypedSurface*`, `broadcastProjectionSurface*`) | Previously exposed by the typed facade/internal live-surface layer; feature callers have been removed. | No. | Public aliases and internal exports are removed; passive broadcast emission is owned by `Web.SurfaceInvalidation` and raw transport stays in `Application.Helper.LiveUpdate.Runtime`. |
| old typed projection bridge | Removed during cleanup. | No. | Keep deleted. |
| `LiveFragmentRef` | Transport payload type in `Application.Helper.LiveUpdate.Internal`, `LiveSurfaceConfig`, controller/support tests, and contract helpers. | Not feature-facing by guard; tests/runtime only. | Rename to `SurfaceWireFragment` while preserving JSON keys and field names. |
| `mkLiveFragmentRef` | Constructor helper used by `mkSurfaceFragmentRef`. | Not feature-facing. | Rename to `mkSurfaceWireFragment`; keep typed `mkSurfaceFragmentRef` as feature entrypoint. |
| `liveFragmentsRefreshTriggerPayload` | Used by `setLiveSurfaceActorRefresh` and `setTypedLiveSurfaceActorRefresh`; guard rejects feature use. | No current feature use, but the exported name reads API-shaped. | Replace with typed-only actor refresh helpers and a private/local transport encoder name. |
| `authorizeSurfaceScope` and default authorization | `authorizeSurfaceScope` only backs `liveSurfaceAuthorizationByScope`; default requirement used by tests. Registry already authorizes via typed definitions. | Guard rejects direct feature use. | Delete fallback function; keep explicit `LiveScopeAuthorizationRequirement` helpers for typed definitions/tests. |
| raw bus broadcasts | `Application.Helper.LiveUpdate.Runtime` re-exports broadcast functions for registry/websocket/runtime tests; `Application.Helper.LiveUpdate.Internal` owns implementation details. | Guard rejects feature use of raw invalidation/resync helpers and runtime-module imports. | Keep quarantined in the runtime facade; signatures use `SurfaceWireFragment`. |

Inventory result: browser JSON stays stable through `ir-myld`, `ir-wqa4`, and `ir-r27i`; only Haskell type/helper names and the untyped projection bridge change before the compact-protocol decision.

## Target Layering

After cleanup, the layers should be explicit:

1. Feature authoring: feature-local surface key and fragment enum plus
   `TypedLiveSurfaceDefinition`.
2. Typed facade: `Application.Helper.LiveSurface` exports typed config,
   authorization, projection, and actor-refresh helpers; it does not expose
   passive broadcast or typed mutation entrypoints.
3. Passive planner: `Web.SurfaceInvalidation` matches touched/expanded
   resources against registered `liveFragmentDependsOn` declarations from each
   `FragmentContract` and emits transport invalidations.
4. Transport runtime: internal bus, websocket JSON, versions, subscriptions, and
   transport fragment metadata.
5. Browser adapter: generic `static/app-live-updates.js` consumes mounted typed
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
   - Remove untyped surface config/ref/broadcast helpers.
   - Keep tests on typed config construction; `mkLiveSurface` compatibility has
     been removed.
3. `ir-wqa4`: rename or quarantine internal wire fragment primitives.
   - Prefer names such as `SurfaceWireFragment` and
     `mkSurfaceWireFragment` if the rename is tractable.
   - Preserve JSON object fields unless `ir-mxsn` changes the protocol.
   - Update projection and contract-test helpers.
4. `ir-r27i`: make actor refresh payload construction typed-only.
   - Keep `setTypedLiveSurfaceActorRefresh` as the only feature-facing actor
     refresh entrypoint.
   - Delete or private-rename `liveFragmentsRefreshTriggerPayload`.
   - Route passive updates through touched resources rather than typed mutation
     helpers.
5. `ir-mxsn`: decide compact protocol separately.
   - Option A: keep self-describing transport payloads and record an ADR note.
   - Option B: send compact fragment keys and resolve target/url/protection from
     mounted surface config, with browser migration tests.
6. `ir-cavr`: update docs, guards, and final checks.

## Compact Protocol Decision

GitHub #145 superseded the earlier deferral after canonical server scope binding
and local-mount resolution were proven. The implemented protocol now carries
only canonical `SurfaceScope` identity and `SurfaceFragmentKey` values through
subscriptions, websocket invalidations, and actor event details. URL, target,
selector, defer, and protection metadata exists once in each browser's local
mount descriptor and never crosses the invalidation boundary.

Canonical generated fragment-key identity/equality handles property order.
Unknown or unmounted keys are ignored, duplicate mounts resolve to their own
local URLs and targets, and source-client echo, version-gap, and resync behavior
is unchanged.

## Focus Protection Decision

GitHub #56 confirmed `app-live-updates` as the only focused-field protection
owner and removed the remaining IHP Auto Refresh/Morphdom runtime compatibility.
The browser consumes the exact generated protection policy, with no legacy
field-key or selector defaults. Protected invalidations retain only the latest
fragment while a matching field is focused, then refetch on blur and restore the
captured value by configured field key/name and optional container. The
`replace` policy never defers for arbitrary focused controls, so roster shift
launchers remain immediately refreshable.

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
- Public typed broadcast/mutation helpers are removed; passive invalidation is
  registry-derived from touched resources.
- The compact protocol decision is recorded; browser JSON remains unchanged.
- Guard tests enforce the new boundary.
- Durable docs reflect the simplified runtime.
