# Frontend TypeScript Agent Notes

## Ownership

Author app JavaScript in `frontend/ts/`. Generated bundles are checked in under
`static/app*.js`; generated backend-owned contracts live in
`frontend/ts/generated/`. Do not hand-edit either generated output.

Every top-level `frontend/ts/app*.ts` entrypoint is global unless an accountable,
reasoned exception exists in `scripts/architecture/wiring-policy.mjs`; its
bundle must be loaded exactly once by `Web/View/Layout.hs`.

Generated contracts cover browser boundaries only. Parse/encode backend JSON,
DOM configuration, Surface mounts, roles, intents, and transport values with
the generated exact helpers. Do not recreate canonical strings, broad database
models, validators, fallback values/copy, server-only action inventories, or
omnibus registries in TypeScript. Closed-union switches require an `assertNever`
default.

Haskell owns business meaning, routes, authorization, displayed workflow/error
copy, Surface descriptors, intent forms, and server DOM. TypeScript owns generic
browser mechanics and disposable state, kept in `WeakMap`/`WeakSet` where
possible. Malformed generated boundaries are diagnosed and skipped before DOM,
network, credential, or redirect effects.

## Interaction And Live Runtime

Read `Application/Helper/Interaction.SPEC.md` and
`Application/Helper/FrontendContract/Surface/README.md` first. Generic
interaction code may mutate only declared disposable layers and must submit
committed intents through Haskell-rendered forms.

Keep `app-live-updates.ts` orchestration-only. Focused modules under
`frontend/ts/live-updates/` own mount parsing, subscriptions, connection,
invalidation, refresh, request decoration, and focus protection. Transport
carries generated semantic fragment keys; resolve URL/target/protection from the
validated local mount. Keep nested mount reconciliation generic and do not add
feature adapters, alternate mount protocols, browser mount state, duplicated
resync lists, or another DOM-diff/focus owner.

Keep browser APIs and presentation mechanics adapter-local. Haskell-rendered
values/copy remain authoritative; adapters must not infer business semantics
from text, CSS classes, or DOM position.

## Commands And Verification

Use Nix/devenv commands, not developer-facing npm/npx workflows. Do not add a
Vite dev server, true-HMR requirement, or runtime Node dependency.

```bash
bash ./bin/in-env frontend-build
bash ./bin/in-env frontend-test
bash ./bin/in-env frontend-check
bash ./bin/in-env frontend-contracts
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-generated-ensure
bash ./bin/in-env frontend-generated-sync
bash ./bin/in-env frontend-generated-watch
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-watch
```

Use unit/DOM tests for pure decisions and parser/DOM seams. Use focused
Playwright for HTMX, websocket/live updates, layout, mobile behavior, and real
browser APIs. Do not add frontend or E2E suites to pre-commit hooks; pre-commit
owns generated-JS drift only. Production serves checked-in assets without Node.
