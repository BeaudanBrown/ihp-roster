# Bepis

Bepis is an IHP roster, leave, timesheet, export, and venue operations app.

The repository is tuned for agent-assisted work. Start with `AGENTS.md`, then read
the nearest subdirectory `AGENTS.md` before changing controllers, views, tests, or
application helpers.

## Repository Map

- `Application/Schema.sql` - source of truth for generated model types.
- `Application/Helper/` - shared domain, controller, and view helpers.
- `Web/Types.hs` - controller action types and app-level web types.
- `Web/Routes.hs` - `AutoRoute` instances.
- `Web/FrontController.hs` - mounted controllers and request context setup.
- `Web/Controller/` - controller implementations.
- `Web/View/` - HSX views and layout shell.
- `Test/` - Hspec coverage.
- `e2e/` - Playwright coverage.
- `docs/` - documentation system, workstreams, ADRs, and archived plans.
- `specs/` - product, domain, compliance, and acceptance specs.

## Local Workflow

Run project commands through the wrapper unless you are already inside the
activated devenv shell:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
```

For browser or integration work, use the managed dev server helpers:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env dev-stop
```

After schema edits, run:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

Apply the schema to the local dev database with `make db` while the dev server is
running. This resets the local dev schema and is only for local verification.
Bepis is live; existing staging/production databases are upgraded through IHP
migrations in `Application/Migration/`. Schema-changing work should update both
`Application/Schema.sql` and the matching migration SQL.

## Static Assets

Runtime assets are local and loaded through `assetPath` from
`Web/View/Layout.hs`. App-owned JavaScript is authored in TypeScript under
`frontend/ts/` and compiled to checked-in generated `static/app*.js` files.
Do not hand-edit generated app JS.

- Bootstrap `5.3.8`
- Bootstrap Icons `1.11.3`
- HTMX `1.9.12`
- IHP-provided Flatpickr and Morphdom assets
- App CSS files: split under `static/css/` and linked directly from
  `Web/View/Layout.hs` with `assetPath`
- Do not recreate a catch-all `static/app.css` unless a compatibility ticket
  explicitly requires it; app-owned CSS should stay split under `static/css/`
- App JS entrypoints: generated `static/app-bootstrap.js`,
  `static/app-date-pickers.js`, `static/app-dialog-overlays.js`,
  `static/app-horizontal-scroll.js`, `static/app-live-updates.js`,
  `static/app-passkeys.js`, `static/app-preferences.js`,
  `static/app-roster.js`, `static/app-scrollbars.js`,
  `static/app-time-picker.js`, `static/app-timesheets.js`,
  `static/app-toasts.js`, `static/app-toggle-buttons.js`,
  `static/app-xero.js`, and `static/app.js`
- Frontend contracts: Haskell-owned DTOs/enums generate TypeScript under
  `frontend/ts/generated/`; use them for backend-emitted JSON/data boundaries
  instead of duplicating broad backend or database models in browser code.
  Planned typed interaction-surface work should also derive surface, disposable
  layer, intent, intent-field, and conflict-policy browser contracts from
  Haskell instead of hand-defining canonical strings in TypeScript.

Feature CSS is split under `static/css/`; update the narrowest matching file
and keep linked stylesheet paths mirrored in `Web/View/Layout.hs` and
`Makefile` (`CSS_FILES`) so style-audit can keep the direct `assetPath` links in
sync. IHP's optional `prod.js`/`prod.css` concatenation is disabled; production
serves the checked-in split static assets directly.

Frontend tooling is exposed through Nix/devenv commands, not developer-facing
`npm`/`npx` workflows:

```bash
bash ./bin/in-env frontend-build
bash ./bin/in-env frontend-check
bash ./bin/in-env frontend-test
bash ./bin/in-env frontend-contracts
bash ./bin/in-env frontend-contracts-check
bash ./bin/in-env frontend-watch
```

`frontend-check` runs contract drift, TypeScript validation, frontend unit/DOM
tests, and generated JS drift. `dev-start` and `just dev` run the frontend
watcher; `dev-stop` cleans it up. There is no Vite dev server or true HMR
requirement. Frontend unit tests and Playwright E2E are not pre-commit hooks;
the tracked pre-commit hook only guards generated JS drift. Production/live
NixOS runtime serves checked-in generated static JS and does not require
Node/esbuild/TypeScript/frontend test tooling.

## CI

`.github/workflows/test.yml` runs the same wrapper commands agents use locally:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
```

Deployment is managed outside this workflow. Production NixOS configuration lives
under `Config/nix/`.

## Generated And Local Artifacts

Generated screenshots, profiles, reports, local databases, Nix build outputs, and
dev shell state are ignored. Keep durable visual references in documentation
assets, not under `output/`.

## Documentation

Start with `docs/README.md` for the documentation operating model.

- Implemented subsystem behavior belongs in local `SPEC.md` files beside code.
- Future feature streams belong in `docs/workstreams/` and must link to `tk`.
- Durable decisions belong in `docs/adr/`.
- Historical numbered plans live in `docs/archive/plans/`.

## License

Bepis is licensed under the Apache License 2.0. See [LICENSE](./LICENSE).

Third-party notices are listed in
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
