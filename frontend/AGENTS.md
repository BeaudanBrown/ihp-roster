# Frontend TypeScript Agent Notes

Read this before editing `frontend/ts/`.

## Source And Generated Files

- App-owned JavaScript source lives in `frontend/ts/`.
- Generated browser assets live in `static/app*.js` and are still loaded by IHP through `assetPath`.
- Generated TypeScript contracts live in `frontend/ts/generated/` and are
  backend-owned. Do not hand-edit generated files. `frontend-contracts`, its
  drift check, and its watcher all render the same checked typeclass-reflected
  Haskell registry used by server runtime metadata.
- Contracts are for browser boundary data only: JSON/data-* payloads, live-update config/messages, exact FrontendSurface mounts, minimal fragment/interaction registries, shared DOM vocabulary, roster UI config, and overlay lanes. Do not generate broad database models, server-only Surface action/DTO/topology data, or omnibus registries for frontend use.
- Each reflected root declares browser reachability. Server-only roots emit nothing; type-only roots emit only a type/constant; inbound roots add guards/parsers; outbound roots add encoders; bidirectional roots add both. Unknown JSON boundaries should use generated `parseX`; outbound JSON-shaped DTOs should use generated `encodeX`; runtime code must not recreate generated validators/parsers/encoders by hand.
- Use Nix/devenv entrypoints, not developer-facing `npm`/`npx` commands.
- Supported commands:
  - `bash ./bin/in-env frontend-build` regenerates checked-in `static/app*.js`.
  - `bash ./bin/in-env frontend-check` runs contract drift, TypeScript validation, the no-`@ts-nocheck` guard, frontend tests, and JS drift.
  - `bash ./bin/in-env frontend-test` runs fast TypeScript unit/DOM tests.
  - `bash ./bin/in-env frontend-contracts` regenerates generated contracts.
  - `bash ./bin/in-env frontend-contracts-check` checks generated contract drift.
  - `bash ./bin/in-env frontend-contracts-watch` watches Haskell contract sources and atomically regenerates generated contracts.
  - `bash ./bin/in-env frontend-watch` watches TS entrypoints and rebuilds generated JS.
- `dev-start` and `just dev` start `frontend-contracts-watch` plus `frontend-watch`; `dev-stop` cleans up both managed watchers.
- There is no Vite dev server or true HMR requirement. Existing browser reload/live-update behavior sees checked-in generated JS changes; contract-source edits regenerate `frontend/ts/generated/contracts.ts`, then `frontend-watch` rebundles dependent JS.
- Production/live NixOS runtime serves generated static assets and must not require Node/esbuild/TypeScript/frontend test tooling.

## Testing

- Use `bash ./bin/in-env frontend-test` for fast TypeScript unit/DOM tests.
- `bash ./bin/in-env frontend-check` runs contract drift, TypeScript validation, the no-`@ts-nocheck` guard, frontend unit/DOM tests, and generated JS drift.
- Put importable logic tests under `frontend/ts/tests/` and prefer small modules under `frontend/ts/shared/` or feature-local modules.
- Unit/DOM tests should cover pure decisions, parser/contract boundaries, and DOM helpers that can be exercised without the IHP server.
- Converted runtimes should use generated contracts for backend-emitted JSON/data boundaries where applicable and add unit/DOM or focused E2E coverage at the appropriate level.
- Use Playwright via `bash ./bin/in-env e2e ...` for browser/server integration: HTMX, Bootstrap behavior, websockets/live updates, layout, roster interactions, mobile behavior, and anything requiring real browser APIs.
- Do not add frontend unit tests or Playwright E2E to pre-commit hooks. The hook is for generated asset drift only.

## Typed Interaction Work

- Start with `Application/Helper/Interaction.SPEC.md` before implementing
  interaction-layer work. Use `docs/workstreams/typed-interaction-surfaces.md`
  only for remaining ticket history while it is still active.
- Author new interaction-layer browser code in TypeScript under `frontend/ts/`.
- It may use esbuild-resolved imports, but keep project commands Nix/devenv-owned
  and avoid introducing developer-facing npm/npx workflows.
- Keep Bepis browser contracts stable and narrow. Backend-emitted JSON/data
  boundaries must use Haskell-owned generated contracts rather than duplicated
  TypeScript domain models.
- TypeScript must consume Haskell-generated live-update, registered-surface,
  FrontendSurface, UI-region, disposable-layer, intent, intent-field,
  live-fragment, and conflict-policy contracts; do not define canonical
  `data-bepis-*`, surface, region capability, fragment, layer, or intent string
  names by hand in runtime code.
- If app-owned TypeScript switches on a generated closed union, include a
  `default` branch that calls `assertNever`; `frontend-check` rejects broad
  switch defaults that can swallow new generated variants.
- Generic interaction code may create, move, and clear disposable UI inside
  Haskell-declared disposable layers, but must not mutate server-owned business
  DOM or construct persistence URLs. Committed intents submit through
  Haskell-rendered HTMX forms. For production surfaces, closest-mount discovery
  is based on `data-bepis-surface`/`data-bepis-surface-config` only. Do not add
  browser support for `data-live-update-surface`.
- Generic UI region runtime may adapt HTMX lifecycle events, lazy retry UI, and
  transition classes only for `data-bepis-fragment="true"` roots rendered by
  Haskell helpers/contracts. Do not make ordinary HTMX, dialogs, validation
  responses, partial navigation, or autosave controls participate without a
  future server-owned region contract.
- Live subscriptions, websocket invalidations, and actor event details carry
  generated `SurfaceFragmentKey` values only. Resolve keys through local mount
  descriptors; never accept a transport URL, target id, selector, defer flag, or
  protection policy as refetch authority.
- Parse `data-bepis-surface-config` only with the generated exact
  `parseFrontendSurfaceMountConfig` boundary. The generated per-surface union
  must reject unknown properties, wrong-surface scope/fragment values, malformed
  protection, and disagreement with the owner element's generated surface attr;
  report the mount error and skip it instead of casting or falling back.
- Actor `HX-Trigger` details also use the generated exact parser. HTMX adds an
  `elt` carrier property at dispatch time; remove only a verified `elt ===
  event.target` before parsing, and preserve every other property so unknown
  server fields still fail exact validation.
- Mount JSON contains only `surface`, `scopeKey`, `mountKey`, `fragments`, and
  `subscription`; descriptors contain only `fragmentKey`, `targetId`, `url`, and
  `protection`, and subscriptions contain only `scope`. Derive resync keys from
  mounted descriptors plus the generated live-fragment set. Do not add browser
  mount state, load policy, duplicate fragment lists, or compatibility aliases.
- Import the generated websocket path, client-id header, Surface/interaction
  DOM vocabulary, and semantic Surface DOM tokens. Do not duplicate these
  backend-owned strings in runtime code. Live code imports only
  `FrontendSurfaceFragmentRegistry`; interaction code imports only
  `FrontendSurfaceInteractionRegistry`.
- Keep `app-live-updates.ts` orchestration-only. `live-updates/mount.ts` owns
  mount parsing/reconciliation, `subscription.ts` owns merge and request scope,
  `connection.ts` owns websocket lifecycle/reconnect, `invalidation.ts` owns
  actor/passive routing and versions, `refresh.ts` owns authorized fragment
  fetch/swap, `request-decoration.ts` owns the HTMX client header, and `focus.ts`
  is the sole focused-field protection owner. Do not collapse these concerns
  back into the entrypoint or restore a DOM client-id readiness attribute.
- Focused-field protection belongs to the live-update runtime. Consume the exact
  generated policy fields without `data-live-field-key` or selector fallbacks;
  do not add Morphdom/auto-refresh compatibility or feature-specific focus/blur
  queues. The `replace` protection variant always remains immediately
  replaceable.
- Nested/composable FrontendSurface behavior must stay generic. If a parent
  fragment/region contains child surface mounts, TypeScript should reconcile
  lifecycle from current DOM mounts after swaps: initialize new child mounts,
  dispose removed child/grandchild mounts, and keep subscriptions equal to the
  currently mounted surface scopes. Do not add feature-specific cleanup or
  subscription code for nested surfaces.
- Production/live packaging serves checked-in generated static assets and must
  stay Node-free.
