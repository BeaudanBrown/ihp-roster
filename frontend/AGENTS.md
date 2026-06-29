# Frontend TypeScript Agent Notes

Read this before editing `frontend/ts/`.

## Source And Generated Files

- App-owned JavaScript source lives in `frontend/ts/`.
- Generated browser assets live in `static/app*.js` and are still loaded by IHP through `assetPath`.
- Generated TypeScript contracts live in `frontend/ts/generated/` and are backend-owned. Do not hand-edit generated files.
- Contracts are for browser boundary data only: JSON/data-* payloads, live-update config/messages, roster UI config, overlay lanes, and capability/config objects. Do not generate broad database models for frontend use.
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
  UI-region, disposable-layer, intent, intent-field, live-fragment, and
  conflict-policy contracts; do not define canonical `data-bepis-*`, surface,
  region capability, fragment, layer, or intent string names by hand in runtime
  code.
- Generic interaction code may create, move, and clear disposable UI inside
  Haskell-declared disposable layers, but must not mutate server-owned business
  DOM or construct persistence URLs. Committed intents submit through
  Haskell-rendered HTMX forms.
- Generic UI region runtime may adapt HTMX lifecycle events, lazy retry UI, and
  transition classes only for `data-bepis-fragment="true"` roots rendered by
  Haskell helpers/contracts. Do not make ordinary HTMX, dialogs, validation
  responses, partial navigation, or autosave controls participate without a
  future server-owned region contract.
- Production/live packaging serves checked-in generated static assets and must
  stay Node-free.
