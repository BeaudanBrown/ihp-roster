# IHP Project — Agent Guidelines

## Framework Reference (in priority order)
1. **IHP Guide** — `IHP/Guide/*.markdown` covers controllers, views, routing, forms, database, auth, HSX, validation, and more. Read the relevant guide first.
2. **IHP Source** — `IHP/ihp/IHP/` contains the framework source. Use it to confirm type signatures, available helpers, and implementation details.
3. **Generated Types** — `build/Generated/Types.hs` contains types generated from `Application/Schema.sql`.

## Project Structure
- `Web/Types.hs` — Controller action types and app-level types
- `Web/Routes.hs` — `AutoRoute` instances
- `Web/FrontController.hs` — Controller mounting and request context initialization
- `Web/Controller/` — Controllers (import `Web.Controller.Prelude`)
- `Web/View/` — Views (import `Web.View.Prelude`, use `[hsx|...|]`)
- `Config/Config.hs` — App configuration
- `Application/Schema.sql` — Database schema source of truth
- `Application/Helper/` — Shared controller and view helpers

## Styling
- Bootstrap is included via vendored files under `static/vendor/`
- Custom CSS lives in `static/app.css`
- Custom JS lives in `static/app.js`
- The layout shell lives in `Web/View/Layout.hs`
- Use `assetPath` for static assets so production cache-busting works

## Client Runtime
- `static/app.js` owns the shared frontend lifecycle. Feature code should initialize from `app:page-ready`, not `turbolinks:load`
- `app:page-ready` fires for full page loads and after HTMX swaps or out-of-band swaps
- Live-update shells opt in with `data-live-update-owner="true"`, `data-live-update-scope`, and `data-live-updates-path`
- Server-owned fragments can opt into blur-delayed refetch by adding `data-live-fragment-defer-until-blur="true"`

## Key Conventions
- Every new controller needs: a type in `Web/Types.hs`, an `AutoRoute` instance in `Web/Routes.hs`, an import plus `parseRoute` in `Web/FrontController.hs`, and an implementation file under `Web/Controller/`
- Use `Web.Controller.Prelude` in controllers and `Web.View.Prelude` in views
- HSX uses `[hsx|...|]` quasi-quotes and is type-checked at compile time
- Database access should use IHP's QueryBuilder rather than raw SQL
- Form handling should use IHP's form helpers

## Overlay Architecture
- Treat overlays as three lanes:
  - `dialog` for workflow forms and confirmations
  - `picker` for short-lived utility selection flows
  - `toast` for transient notifications
- Multiple overlay triggers may exist on a page, but only one workflow dialog should be active at a time in the shared dialog mount
- Avoid nested workflow dialogs. A picker may appear above a workflow dialog, but dialogs should replace each other rather than stack
- Prefer declarative overlay config in `Application/Helper/View.hs` over ad-hoc per-view footer buttons
- For HTMX flows, return the smallest updated fragment plus any out-of-band overlay updates instead of redirecting whole pages when the current screen can update in place

## Overlay Implementation Plan
- Shared overlay helpers live in `Application/Helper/View.hs` and define mount ids, config records, footer rendering, and toast rendering
- `Web/View/Layout.hs` owns the top-level overlay hosts:
  - one shared dialog mount for workflow dialogs
  - one shared toast mount for transient notifications
  - picker markup rendered separately when a project uses picker overlays
- Toast placement should be controlled declaratively in the helper layer
- Controllers should prefer HTMX-driven in-place overlay workflows and keep `setModal` as a fallback
- When migrating older modal code, move save/cancel controls into shared overlay/footer helpers before changing response shapes

## Verification Tools

These scripts are defined in `flake.nix` as devenv shell scripts. They are available on `PATH` only inside the activated direnv environment.

Use the repo wrapper `bash ./bin/in-env` as the default entrypoint for automation, agents, CI, and worktrees. It prefers `direnv exec` when `.envrc` exists and otherwise falls back to `nix develop` with the local `devenv-root` override this repo needs.

Agents and CI running outside an interactive direnv shell should prefer:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env test
bash ./bin/in-env hspec-test
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env e2e
bash ./bin/in-env screenshot http://localhost:8000/MyPage output.png
bash ./bin/in-env e2e-report
bash ./bin/in-env dev-start
bash ./bin/in-env dev-stop
bash ./bin/in-env dev-status
bash ./bin/in-env dev-wait
```

Never use bare names like `typecheck` or `lint` in non-devenv shells.

If you hit `attempt to write a readonly database` or other nix fetcher cache errors, ensure `XDG_CACHE_HOME` points to a writable path. This repo defaults to `/tmp/nix-cache`.

Available scripts:
- `typecheck` — Fast typecheck without a full build
- `regen-types` — Regenerate `build/Generated/Types.hs` after schema edits
- `test` — Compile and run the test suite
- `hspec-test` — Alias for the Hspec test suite, useful when a repo also has browser e2e tests
- `lint` — Run hlint on app sources
- `format` — Format app sources with stylish-haskell
- `ghci-app` — Launch GHCi with the app loaded
- `new-controller NAME` — Scaffold a new IHP controller
- `test-db-reset` — Rebuild the isolated `app_test` automation database
- `e2e` — Run Playwright end-to-end tests against isolated `app_test` plus a compiled temporary app server on a fresh port unless `BASE_URL` is already set
- `screenshot` — Take a screenshot of a page
- `e2e-report` — Open the Playwright HTML report
- `dev-start` — Start the app in background for automation
- `dev-stop` — Stop the background server started by `dev-start`
- `dev-status` — Check background server health
- `dev-wait [seconds]` — Wait for the background server to become healthy
- `dev-app-port` — Print the app port used by the managed dev server

For reliable non-interactive automation, prefer:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
# run commands that need server + DB
bash ./bin/in-env dev-stop
```

## Adding a New Feature
1. Update `Application/Schema.sql` if the feature needs new tables or columns
2. Run `bash ./bin/in-env regen-types` after schema changes
3. Run `make db` while the dev server is available so the schema is applied to the dev database
4. Add controller types, routes, controller implementation, and views
5. Run `bash ./bin/in-env typecheck`
6. Run `bash ./bin/in-env test` when controller logic changes
7. Run `bash ./bin/in-env lint` and `bash ./bin/in-env format` before finishing

For simple CRUD, prefer `new-controller NAME` and then customize the generated files.

## Verification Workflow
- After every code change: `bash ./bin/in-env typecheck`
- After schema changes: `bash ./bin/in-env regen-types`, then `bash ./bin/in-env typecheck`, then `make db`
- After adding or changing controllers: `bash ./bin/in-env test`
- After UI or integration changes: `bash ./bin/in-env e2e`
- Before committing: `bash ./bin/in-env lint`, then `bash ./bin/in-env format`
- To confirm DB sync: `psql -h "$PWD/build/db" app -c "\dt"`

## E2E Testing
- Playwright tests live in `e2e/`
- The config is `playwright.config.ts`
- Seeded test data lives in `e2e/fixtures/seed.sql`
- `global-setup.ts` and `global-teardown.ts` target `TEST_DATABASE_NAME` / `TEST_DB_SOCKET`, defaulting to the isolated `app_test` db on the local socket
- `bash ./bin/in-env e2e` builds `build/bin/RunUnoptimizedProdServer` and launches it on a temporary port before invoking Playwright when `BASE_URL` is unset
- Browser versions come from Nix, so no manual browser install should be necessary

## Maintaining Agent Documentation
- Subdirectory `AGENTS.md` files exist in `Application/`, `Web/Controller/`, `Web/View/`, and `e2e/`
- When you discover a reusable IHP pattern, add it to the relevant `AGENTS.md`
- Keep entries concise and actionable
- Verify patterns against the guide or framework source before documenting them
