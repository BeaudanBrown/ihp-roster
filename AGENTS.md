# IHP Project — Agent Guidelines

## Framework Reference (in priority order)
1. **IHP Guide** — `/home/beau/documents/projects/ihp/Guide/*.markdown` covers controllers, views, routing, forms, database, auth, HSX, validation, etc. Read the relevant guide FIRST before implementing any feature.
2. **IHP Source** — `/home/beau/documents/projects/ihp/ihp/IHP/` contains the full framework source. Use grep/find there to understand type signatures, available functions, and implementation details.
3. **Generated Types** — `build/Generated/Types.hs` contains types generated from `Application/Schema.sql`. Regenerated automatically.

## Project Structure
- `Web/Types.hs` — All controller action types and app-level types
- `Web/Routes.hs` — AutoRoute instances
- `Web/FrontController.hs` — Controller mounting and context initialization
- `Web/Controller/` — Controller implementations (import `Web.Controller.Prelude`)
- `Web/View/` — Views (import `Web.View.Prelude`, use HSX quasi-quoter `[hsx|...|]`)
- `Config/Config.hs` — App configuration
- `Application/Schema.sql` — Database schema (source of truth for models)
- `Application/Helper/` — Shared helpers for controllers and views

## Styling
- **Bootstrap 5.3.8** is included via vendor files — use Bootstrap classes in HSX
- `static/app.css` is the CSS entrypoint; feature styles live under `static/css/`
- App JavaScript is split by concern across `static/app-bootstrap.js`, `static/app-date-pickers.js`, `static/app-passkeys.js`, `static/app-live-updates.js`, `static/app-dialog-overlays.js`, `static/app-toasts.js`, `static/app-time-picker.js`, `static/app-roster.js`, `static/app-timesheets.js`, and `static/app.js`
- The layout shell is defined in `Web/View/Layout.hs` — edit `defaultLayout` to change page structure
- Use `assetPath` for all static asset references (enables cache-busting in production)

## App Navigation Conventions
- Global authenticated navigation lives in `Web/View/Layout.hs` and is rendered on every authenticated page
- Header button order is: `roster`, `profile`, `timesheets`, `leave`, `xero`, `admin`, `support`, `logout`
- `xero` is visible to venue owners and super admins in the header; `admin` is role-gated (admin-only visibility); `timesheets` and `admin` may route to placeholder pages until fully implemented
- `support` is founder-only and should be rendered only for `currentUserIsSupportAdmin`
- Auth pages (sign in/sign up/welcome) should not show the authenticated header

## Roster Week Navigation Conventions
- `weekOffset` in the URL is the source of truth for the viewed roster week
- Use `ShowRosterWeekAction { weekOffset = ... }` for explicit week navigation
- `RosterWeeksAction` is the canonical "this week" reset entrypoint; normal requests redirect to the current week offset and HTMX requests should return the current week shell plus a pushed canonical URL
- Do not persist "last viewed week" in DB unless explicitly requested in a future change

## Key Conventions
- Every new controller needs: type in `Web/Types.hs`, AutoRoute in `Web/Routes.hs`, import+mount in `Web/FrontController.hs`, implementation in `Web/Controller/`
- Use `Web.Controller.Prelude` in controllers, `Web.View.Prelude` in views — these re-export everything needed
- HSX uses `[hsx|...|]` quasi-quotes — it's like JSX but type-checked at compile time
- Database queries use IHP's QueryBuilder, not raw SQL — see `/home/beau/documents/projects/ihp/Guide/querybuilder.markdown`
- Form handling uses IHP's form helpers — see `/home/beau/documents/projects/ihp/Guide/form.markdown`

## Planning Files
- Repo-local `tk` tickets in `.tickets/` are the live implementation tracker for active work, next actions, blockers, and task status.
- `IMPLEMENTATION_PLAN.md` is the roadmap for global ordering and cross-pipeline dependencies; do not use it as a live checklist.
- Detailed execution plans live under `plans/` as durable design references; read only the relevant pipeline file after reading the root roadmap and repo-local ticket.
- `plans/90-historical-completed-slices.md` holds completed or superseded detail that may still matter for migration work.

## Issue Tracking With tk
- Use repo-local `tk` from this repository for project implementation work:
  - `tk ready`
  - `tk blocked`
  - `tk show <id>`
  - `tk dep tree <id>`
- Keep `.tickets/` checked in; it is the project-local source of truth for implementation status.
- Coordinator tickets such as `coordinator-xga` are routing and portfolio references. When both layers exist, start from the coordinator ticket only to identify the project/workstream, then use the linked repo-local `ir-*` ticket for implementation details.
- Do not create new markdown TODO lists or parallel ad-hoc trackers for work already represented in repo-local `tk`.
- Keep plans/specs as design context. If status changes, update or create the relevant ticket rather than editing old checklist text as the only record.

## Learning Capture

- If a command, workaround, or constraint is likely to matter again across this repo, add it here or to the most relevant spec.
- Keep durable project-wide learnings in this `AGENTS.md` or the repo's own plans/specs.
- Keep long debug trails out of tracked source unless they become a reusable plan, spec, or troubleshooting note.

## Overlay Architecture
- Treat overlays as three separate lanes:
  - `dialog` for workflow forms and confirmations
  - `picker` for short-lived utility selection flows such as the quarter-hour time picker
  - `toast` for transient notifications
- Multiple overlay triggers may exist on a page, but only one workflow dialog should be active at a time in the shared dialog mount.
- Do not build arbitrary nested workflow dialogs. A picker may appear above a workflow dialog, but dialogs should replace each other rather than stack.
- Prefer declarative overlay config in `Application/Helper/View/Overlay.hs` over ad-hoc per-view footer buttons. Shared forms should usually render fields only; overlay wrappers own primary and secondary actions.
- For responsive HTMX flows, return the smallest updated fragment plus any out-of-band overlay updates. Avoid whole-page redirects when the current screen can be updated in place.

## Overlay Implementation Plan
- Shared view helpers are split by concern under `Application/Helper/View/`:
  - `Chrome.hs` for page/panel/partial-navigation wrappers
  - `Overlay.hs` for workflow dialog mount ids, config records, and footer buttons
  - `Toast.hs` for toast config and rendering
  - keep `Application/Helper/View.hs` as the compatibility wrapper, not the default place for new helper implementations
- New shared view helpers should go into the narrowest matching `Application/Helper/View/*` module first. Only keep `Application/Helper/View.hs` as a re-export boundary unless a helper truly spans multiple view helper areas.
- `Web/View/Layout.hs` owns the top-level overlay hosts:
  - one shared dialog mount for workflow dialogs
  - one shared toast mount for transient notifications
  - picker markup rendered once at layout level
- Toast host placement should be set declaratively in the helper layer. Default to bottom-center unless a workflow explicitly needs left or right alignment.
- Controllers should treat HTMX as the primary transport for in-place overlay workflows and keep `setModal` only as an explicit fallback when needed.
- When migrating older modal code, remove duplicated form-level action rows first, then move save/cancel buttons into the shared overlay/footer helpers before changing controller response shape.

## Verification Tools

These scripts are defined in `flake.nix` as devenv shell scripts. They are placed on `PATH` automatically when the project environment is active.

Use the repo wrapper `bash ./bin/in-env` as the default entrypoint for automation, agents, CI, and weavers. It prefers `direnv exec` when `.envrc` is available and falls back to `nix develop` when needed.

**Agent/automation note:** Run project commands through `bash ./bin/in-env` unless you are already inside the activated devenv shell:

```bash
# Correct — works from any shell when direnv or nix is available
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env hspec-coverage
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env e2e
bash ./bin/in-env screenshot http://localhost:8000/MyPage output.png
bash ./bin/in-env e2e-report
```

Never use bare names like `regen-types` or `typecheck` in non-interactive automation unless you already know the devenv shell is active.

If you hit `attempt to write a readonly database` for nix fetcher cache, ensure `XDG_CACHE_HOME` points to a writable path (this repo defaults to `/tmp/nix-cache` in `.envrc`, `bin/in-env`, and `dev-start`).

Available scripts:

- **`typecheck`** — Fast (~2-3s) typecheck without full build. **Run after every code change** to catch errors immediately. Exit 0 = success.
- **`regen-types`** — Regenerate `build/Generated/Types.hs` after editing `Application/Schema.sql`. Always run this before `typecheck` when schema has changed.
- **`hspec-test`** — Compile and run the Hspec suite. The full run now auto-shards across local cores when called without Hspec filter args; each shard gets its own ephemeral database and log directory under `.devenv/test/`. Use `TEST_SHARDS=1` to force serial execution. Hspec supports repeated `--match` flags as OR filters, so use one invocation like `bash ./bin/in-env hspec-test --match "PasskeysController" --match "LiveUpdate"` for multiple focused areas instead of running several focused `hspec-test` processes in parallel; separate invocations can race on the shared `build/Test` compile directory and default test database. Use `TEST_SHARDS=N` with focused matches only when they span multiple suites, because sharding is by suite. **Add tests for every new controller** (see `Test/AGENTS.md`).
- **`hspec-coverage [hspec-args...]`** — Compile and run the Hspec suite with GHC HPC coverage instrumentation. This runs serially against an isolated `app_test_coverage` database, prints the app-source per-module report, and writes reports under `output/coverage/hspec/latest/` (`report.txt`, `report.xml`, `html/hpc_index.html`, and `raw-report.txt` for all instrumented modules). Use it when adding or materially changing Hspec coverage; keep `hspec-test` as the normal fast correctness check.
- **`lint`** — Run hlint on app sources. Provides suggestions for idiomatic Haskell. Do not rely on `hlint --refactor` in this repo until `apply-refact` is available in the active Nix package set; fix lint findings manually in small, reviewable chunks. Prefer behavior-preserving rewrites such as removing redundant `. id`, simple eta-reduction, `unless`, `maybe`, `<$>`/`<&>` simplifications, and unused pragma removal. Skip suggestions that require new language extensions, materially change laziness/strictness, or make code less readable unless the user explicitly approves them.
- **`format`** — Format app sources with stylish-haskell (config in `.stylish-haskell.yaml`).
- **`ghci-app`** — Launch GHCi with the full app loaded for testing expressions interactively.
- **`seed-dev [app|app_test] [--force]`** — Seed a broader current-week development dataset for manual inspection, including a busy multi-group roster venue, support/bootstrap scenarios, and the richer payroll parity venue. The command now always resets the target DB first; `--force` is accepted as an explicit no-op compatibility flag. It also loads hard-coded award/public-holiday reference data from `Application/Support/Seed/DevReferenceData.sql` after the deterministic seed. If adding dev passkey preservation, do not generate fake passkeys in the seed; replay a local ignored SQL file after deterministic users are recreated, mapping passkeys back to `users.email`. Resident passkeys also bind to the WebAuthn user handle, so any seeded account with a preserved passkey must keep a stable `users.id` in `Application.Support.DevFixtures.seededUserIdsForPasskeys`. The command also replays a local ignored Xero connection SQL file when present at `build/dev-xero-connection.sql` or `$DEV_XERO_SEED_FILE`; keep raw Xero token material out of tracked source.
- **`just seed-dev`** — Human-friendly default for manual dev exploration. This always wipes and reseeds `app` so the running dev app reflects the seeded venues immediately.
- **`seed-profile [app_profile|app_profile_*] [seed-options...]`** — Seed a large deterministic profiling database using generated CSV files plus `psql \copy`. It writes seed artifacts, `manifest.json`, `load.sql`, and a reusable DB dump under `build/profile-seed/latest` by default.
- **`profile-app [--seed|--reuse-db] [--db=app_profile_*] [--scenario=full|roster|timesheets|leave|xero] [--runs=N]`** — Run the isolated Playwright profiling harness. It starts its own app server against an `app_profile_*` database, sets `IHP_ROSTER_PROFILING=1`, captures `Server-Timing` headers, and writes `profile.json` plus `profile.md` under `output/profile/<run-id>/`. The default database name is unique per run so this can run alongside normal dev and E2E servers.
- **`profile-load [--seed|--reuse-db] [--db=app_profile_*] [--scenario=roster-hot|roster-wide|roster-overview|roster-projections|fragments|timesheets|leave|mixed-app] [--rate=N] [--duration=30s] [--vus=N]`** — Run the isolated k6 request-volume profiling harness. It reuses the large deterministic profile seed and dedicated profiling app server, then writes raw k6 metrics plus `load-profile.json` and `load-profile.md` under `output/profile-load/<run-id>/`.
- **`profile-load-suite [--db=app_profile_*] [--scenario=name ...] [--rate=N] [--duration=30s] [--vus=N]`** — Run the standard k6 load profiling matrix against one seeded profile database. It writes per-scenario reports and a combined `suite-summary.json`/`suite-summary.md` under `output/profile-load-suite/<run-id>/`.
- **`profile-compare <before-profile.json> <after-profile.json> [output.md]`** — Compare two profile JSON artifacts and report the largest request/span deltas for before/after performance checks.
- **`new-controller NAME`** — IHP code generator that scaffolds controller, views, types, and routes. Prefer this for new CRUD controllers, then customize.
- **`e2e`** — Run Playwright end-to-end tests against isolated shard-local `app_e2e_*` databases and temporary app servers on the next free local IHP dev ports. The full suite now auto-shards to at most two app-server shards by default when called without focused or interactive args; sharded runs build one compiled app executable for the run and launch each shard from it to avoid live-reload GHCi/file-watcher conflicts against the shared working tree. Use `E2E_SHARDS=1` to force serial execution, `E2E_SERVER_MODE=dev` to debug the old dev-server path, `PLAYWRIGHT_RETRIES=0` to fail on the first attempt during local iteration, or set a larger explicit shard count when you really want it. Accepts Playwright args (e.g. `e2e --headed`, `e2e e2e/auth.spec.ts`). The local Postgres socket still needs to be available, but this wrapper no longer reuses the normal dev app/database.
- **`screenshot`** — Take a screenshot of a page. Usage: `screenshot http://localhost:8000/Dashboard dash.png`. Requires `devenv up` running.
- **`screenshot-page`** — Authenticated Playwright screenshot helper for arbitrary app pages. Preferred over ad hoc browser scripts when the page requires login/profile completion or a shell-specific wait selector. For the normal dev app it assumes the `seed-dev app` dataset and defaults to `dev-manager@example.com` / `password123`. Supports `--selector`, `--clip-selector`, `--device`, `--viewport`, `--base-url`, `--email`, `--password`, `--login-path`, `--login-selector`, `--post-login-url-pattern`, `--navigation-timeout-ms`, `--selector-timeout-ms`, `--wait-ms`, `--no-login`, and `--no-full-page`.
- **`screenshot-roster-mobile`** — Capture a standard roster mobile screenshot set against the running dev app. Run `bash ./bin/in-env seed-dev app` first when you want deterministic dev-role data. Saves full-page and clipped roster shell/table captures for Pixel 7, iPhone 13, iPad Mini, and a 360px Galaxy-style viewport.
- **`e2e-roster-mobile-screenshots`** — Run the opt-in roster mobile visual diagnostic suite against the isolated E2E app. It attaches full-page screenshots, roster shell screenshots, editable-row screenshots, and layout metrics JSON to the Playwright report for mobile/tablet projects.
- **`e2e-report`** — Open the Playwright HTML test report from the last run.
- **`dev-start`** — Start the IHP `start` script in background for automation (no PTY dependency). Writes pid/log to `.devenv/agent/` and fails fast if startup exits early.
- **`dev-stop`** — Stop background server started by `dev-start`. If the app is healthy but was started outside `dev-start`, it reports `healthy but unmanaged` and does not kill it.
- **`dev-status`** — Health check for background dev server (process/socket + DB + HTTP). In restricted sandboxes it may report `*_blocked=true` and still succeed when the process is running. Permission-denied detection uses the Nix-provided `ripgrep` binary from the dev shell, so run it through `bash ./bin/in-env` unless you are already inside the shell.
- **`dev-wait [seconds]`** — Wait until `dev-status` is healthy (default timeout: 90s). On timeout it prints `dev-status` plus recent `.devenv/agent/devenv.log` lines for debugging.
- The background wrapper state for `dev-start`/`dev-stop`/`dev-status` now prefers `$XDG_RUNTIME_DIR/ihp-roster-dev` (or `DEVENV_AGENT_STATE_DIR` if set) instead of the repo tree. This avoids Syncthing or shared-working-tree conflicts on volatile pid/socket files. The old repo-local `.devenv/agent` path is only a fallback when no runtime dir is available.
- The app runs via `devenv up` — it auto-reloads on file changes, so you can check the browser for runtime behavior.
- A thin human-facing `justfile` exists for interactive use inside the already-activated dev shell. Treat it as aliases only (`just dev`, `just db`, `just test`, `just e2e`, etc.); keep the real command logic in the flake/devenv scripts instead of duplicating it in `justfile`.
- Production repeating operational tasks should use a NixOS `systemd.timer` in `Config/nix/modules/ihp-roster.nix` that invokes an app script and lets the existing `app_jobs` worker perform the business work. Keep the clock in deployment config and the domain logic in Haskell; see the Xero keepalive sweep/timer for the current pattern.

For reliable non-interactive automation, prefer:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
# run commands that need server + DB
bash ./bin/in-env dev-stop
```

For reliable local database access, run `psql` through the project shell and let the active devenv set `PGHOST`/`DATABASE_URL`; do not hard-code `-h "$PWD/build/db"` unless you have first confirmed that is the active socket:

```bash
bash ./bin/in-env psql -d app -c "\dt"
bash ./bin/in-env psql -d app_test -c "\dt"
```

When a human has started the app with `just dev`, the live Postgres socket may be under `/tmp/devenv-.../postgres`. `bash ./bin/in-env env | rg '^(PGHOST|DATABASE_URL)='` shows the connection target agents should use.

## Adding a New Feature (e.g. a new page with database table)

1. **Schema** — Add table to `Application/Schema.sql`, then:
   - Run `bash ./bin/in-env regen-types` to regenerate Haskell types
   - Run `make db` (requires `devenv up` running) to apply the schema to the dev database — **this drops/recreates the dev schema and wipes local dev rows, including local Xero connections; skipping this causes "relation does not exist" crashes at runtime even when typecheck passes**
   - Keep `Application/Fixtures.sql` usable after every `make db`; dev resets should leave a deterministic founder login (`beaudan.brown@gmail.com`) with a venue-scoped admin membership in the default dev venue
   - For finite roles/statuses/event-kind columns, prefer Postgres enums over `TEXT` + `CHECK (... IN (...))`; IHP startup reparses `pg_dump`, and Postgres rewrites `IN` checks to `= ANY (ARRAY [...])`, which the vendored IHP parser does not understand
   - Avoid enum type names starting with built-in SQL type tokens such as `time`/`timestamp`; the IHP parser may parse the prefix as a built-in type instead of a custom enum name
   - Watch for generated enum constructor collisions with model constructors (for example enum value `staff` versus the `Staff` model); in those cases keep the column as `TEXT` and use an explicit `(a = 'x') OR (a = 'y') ...` check instead of `IN (...)`
2. **Types** — Add controller type to `Web/Types.hs` (see `Web/Controller/AGENTS.md` for pattern)
3. **Routes** — Add `instance AutoRoute MyController` to `Web/Routes.hs`
4. **Controller** — Create `Web/Controller/My.hs` with action implementations
5. **Views** — Create `Web/View/My/Index.hs`, `Show.hs`, etc. (see `Web/View/AGENTS.md`)
6. **Mount** — Add `import Web.Controller.My` and `parseRoute @MyController` to `Web/FrontController.hs`
7. **Verify** — Run `bash ./bin/in-env typecheck` (must pass before moving on)
8. **DB check** — Confirm the table exists: `bash ./bin/in-env psql -d app -c "\dt"`
9. **Polish** — Run `bash ./bin/in-env lint`, then `bash ./bin/in-env format`

For simple CRUD, prefer running `new-controller NAME` to scaffold all files, then customize.

## Verification Workflow
- **After every code change**: `bash ./bin/in-env typecheck` (fast, ~2-3s)
- **After schema changes**: `bash ./bin/in-env regen-types` first, then `bash ./bin/in-env typecheck`, then `make db` (requires `devenv up`)
- **After schema changes involving enums or constraints**: after `make db`, restart and wait for the dev server (`bash ./bin/in-env dev-stop`, `bash ./bin/in-env dev-start`, `bash ./bin/in-env dev-wait`) to catch startup-only schema-parser failures; this is why the earlier QC pass missed the `pg_dump`-roundtrip issue
- The IHP schema-designer toast about `Unmigrated Changes` is not an authoritative sync check in this repo; it is driven by the IDE migration workflow state and can stay stale even after `make db`. Treat `make db` plus explicit DB/startup verification as the real source of truth.
- **After adding/changing controllers**: `bash ./bin/in-env hspec-test` to run the test suite
- **When adding/changing meaningful Hspec coverage**: `bash ./bin/in-env hspec-coverage` to inspect the GHC HPC report, especially for new controllers, helpers, and domain logic with non-trivial branches
- **After UI/integration changes**: `bash ./bin/in-env e2e` to run end-to-end tests against the isolated test DB/server
- `bash ./bin/in-env hspec-test` and `bash ./bin/in-env e2e` now both shard across isolated ephemeral databases by default for full-suite runs. Hspec shard selection is defined in `Test/Suite.hs`; Playwright shard reports are merged back into `.devenv/e2e/latest-report`.
- **Before committing**: `bash ./bin/in-env lint` then `bash ./bin/in-env format`
- **To confirm DB is in sync**: `bash ./bin/in-env psql -d app -c "\dt"` — all tables in `Schema.sql` should be present

## E2E Testing

Playwright-based end-to-end tests live in `e2e/` and run against isolated temporary app servers on the next free local IHP dev ports, each backed by its own `app_e2e_*` shard database. See `e2e/AGENTS.md` for the full guide.

- **Config**: `playwright.config.ts` — multi-project desktop/mobile config, with the wrapper controlling shard count and report mode through environment variables. E2E timeout values live in `e2e/timeouts.ts`; specs and `e2e/test-helpers.ts` should import `E2E_TIMEOUT` instead of using numeric timeout literals.
- **Test data**: Seeded via `e2e/fixtures/seed.sql` (manager: `e2e-test@example.com`, worker: `e2e-worker@example.com`, both with password `test-password-123`)
- **Cleanup**: `global-teardown.ts` deletes all rows with `e2e-` prefixed emails and removes worker-owned leave/timesheet rows before deleting dependent snapshots
- **Browsers**: Provided by Nix via `playwright-web-flake` — no manual browser install needed
- **CLI invocation**: In automation, prefer `bash ./bin/in-env e2e` / `screenshot` / `e2e-report` instead of bare `npx playwright ...`; the wrapper resolves the repo-local Playwright CLI inside the dev shell so the runner matches the imported test package
- **Authenticated/manual captures**: Prefer `bash ./bin/in-env screenshot-page ... --selector '<real-shell-selector>'` for arbitrary screenshots. If you need the richer manual-inspection dataset or role accounts, run `bash ./bin/in-env seed-dev app` first. On cold IHP boots, increase both `--navigation-timeout-ms` and `--selector-timeout-ms` instead of cloning the helper or writing one-off screenshot scripts.
- **Exploratory browser work**: Use `bash ./bin/in-env pwcli ...` for ad hoc Playwright CLI sessions, targeted screenshots, and live selector discovery. `pwcli-auth-save <manager|worker|admin|support>` depends on the `seed-dev app` role accounts; manager/worker use `password123`, the seeded venue-admin alias uses `venue2@bepis.lol` / `venue2`, and the seeded support super-admin uses `admin@bepis.lol` / `admin`. The isolated `e2e` suite still uses `test-password-123` against `app_e2e`. After saving state, open a pre-authenticated session with `bash ./bin/in-env pwcli-auth-open <role> <path>`.
- **npm deps**: `@playwright/test` version in `package.json` must match the `playwright-web-flake` tag in `flake.nix`

## Maintaining Agent Documentation
- Subdirectory `AGENTS.md` files exist in `Web/Controller/`, `Web/View/`, and `Application/` with detailed patterns
- When you discover a new IHP pattern, convention, or gotcha while implementing a feature, **add it to the relevant `AGENTS.md`** so future agents benefit
- Keep entries concise and actionable — show the code pattern, not lengthy explanations
- Always verify patterns against `/home/beau/documents/projects/ihp/Guide/` or `/home/beau/documents/projects/ihp/ihp/IHP/` source before documenting

## Current UI Patterns
- Roster and timesheet week pagers use HTMX shell swaps with pushed canonical URLs instead of full-page week navigations
- The roster staff sidebar uses CSS-only desktop behavior: sticky positioning, viewport-capped height, and internal list scrolling
- Live-update collaboration uses a split path:
  - actor browser gets immediate HTMX fragments/OOB swaps from the mutation response
  - concurrent viewers get websocket invalidation payloads plus authorized fragment refetch
- Roster week pages now subscribe even on empty/hidden-week shells so create/copy/publish transitions can update passive viewers without IHP Auto Refresh
- The app no longer loads `ihp-auto-refresh.js`, emits Auto Refresh meta, or calls `initAutoRefresh`; page freshness is expected to come from explicit HTMX/live-fragment flows instead of framework-wide polling.
- Auto Refresh audit result as of `2026-03-15`: there are no remaining app-runtime `autoRefresh` consumers under `Web/Controller/`, `Application/`, `Web/FrontController.hs`, or `Web/View/Layout.hs`.
- Keep live invalidation payloads structural (`scope`, `fragmentKey`, `targetId`, `url`, `protectionPolicy`) rather than broadcasting rendered HTML across viewers
- When a mutation should not clobber focused inputs remotely, set a `FocusedFieldProtection` policy on the `LiveFragmentRef`; keep `deferUntilBlur` only as compatibility metadata, not as the primary extension point.
- The app-wide live-update direction is:
  - one websocket connection per browser tab/client
  - many scope subscriptions per connection
  - scopes represent authorized logical data slices, not pages
  - invalidations are routed by scope and carry explicit fragment refs
  - clients refetch only the invalidated fragments they currently have mounted
  - one mutation may invalidate multiple scopes, and only a subset of fragments within each scope
- The transport/client pattern is reusable across collaborative pages. Keep websocket/refetch, request decoration, resync, queueing, swapping, and focus-protection policy handling in the generic declarative runtime; do not add feature-specific JavaScript adapters for ordinary live surfaces.
- Direct mutations that know the affected scope should broadcast that scope directly. Fan-out mutations that could touch many historical/cold scopes should first intersect with active subscriptions using `Application.Helper.LiveUpdate.activeLiveUpdateScopes` or `activeRosterWeekScopes`, then build fragment refs only for those currently mounted scopes. Closed pages can fresh-render when opened unless durable missed-update semantics are an explicit requirement.
- The leave/timesheet live-fragment rollout is verified with manager/worker Playwright coverage:
  - leave approvals update the worker leave page live
  - leave approvals update an already-open manager roster page live
  - timesheet approvals update the worker timesheet page live
- Product decision recorded on `2026-03-21`: only approved-state leave changes invalidate roster scopes. Pending leave create/delete does not fan out to roster viewers.
- The retained date/datetime picker enhancement now belongs to `static/app.js`, not `helpers.js`. Keep it wired for full-page loads and HTMX-inserted fragments so overlay forms get the same picker behavior as first-load pages.
- Keep scope shapes simple and explicit:
  - venue-only surfaces such as leave lists should use a venue scope kind carrying `venueId`
  - week-based surfaces such as roster and timesheets should use a scope kind carrying `venueId` plus `weekOffset`
  - client scope keys must be derived by scope kind, not by assuming every feature has a week offset
- New live-update surfaces should be declared from Haskell with `Application.Helper.LiveSurface.LiveSurfaceConfig` and rendered as `data-live-update-surface` on the stable owner shell. Avoid adding feature-specific JavaScript adapters for ordinary subscribe/resync/request-decoration behavior.
- Standard live-fragment adoption pattern: add a fragment action that returns the section HTML, give the section a stable `id`, define a `LiveFragmentRef`, include it in a `LiveSurfaceConfig`, render `data-live-update-surface`, broadcast `broadcastLiveInvalidation scope sourceClientId [fragmentRef]` after mutations, and cover both the fragment response and surface metadata in Hspec.
- For admin/config interactions that can mutate server-side data and leave an open page stale, the declarative live-fragment flow is the primary interface: render the section as a stable fragment, submit actor-local changes with HTMX into that fragment when the page should stay in place, and broadcast the matching live scope so other open tabs/users resync. Keep native full-page submits only for low-frequency session/security flows such as Xero OAuth connect/reconnect/callback and disconnect.
- Use the live-fragment pattern when another open tab, another user, or an async job can make the current DOM stale while the viewer remains on the page. Use plain HTMX for actor-local in-place updates, and use native full-page requests for low-frequency session/auth/security flows unless the surrounding screen genuinely needs to stay in place.
- Candidate audit as of `2026-04-29`:
  - Exports live inside Admin > Exports, not on a standalone exports page. The UI uses fixed export cards and date-range inputs defaulting to the current roster week; report-definition management is intentionally not exposed. Keep the current native request/download workflow unless export job progress or recent export history needs to refresh across tabs/users.
  - `Web/View/Admin/Index.hs` has live surfaces for invites, slot names, shift types, and roster groups. Keep adding admin config surfaces only when concurrent admin edits should appear without reload.
  - The profile page uses HTMX for local profile edits and a live surface for self-service leave content. Profile-driven roster invalidations should use active roster week scopes so profile changes do not scan or bump closed historical roster weeks.
  - Support award-rate and public-holiday job sections already use declarative live fragments. Support venue switching, venue creation, owner invitations, and passkey management intentionally remain full-page/session/security workflows unless a future product requirement needs in-place collaboration.
- Post-`helpers.js` migration policy:
  - use HTMX for partial and in-place workflows
  - keep low-frequency full-page forms such as admin/config, exports, profile, login, and invitation/bootstrap as native browser submits by default
  - do not recreate IHP's document-wide AJAX form transport in app code
  - replace destructive `.js-delete` links with explicit app-owned forms using `POST` plus hidden `_method=DELETE`
  - keep only the still-useful UI helpers in app-local JS, currently the date/datetime picker enhancement
  - keep TurboLinks separate from form transport; if retained, it is for navigation lifecycle only
  - if TurboLinks is retained with `turbolinksMorphdom.js`, `static/app.js` must still provide the body-swap runtime (`transitionToNewPage`, `ihp:load`/`ihp:unload`, and timer cleanup); removing `helpers.js` without rehoming that hook breaks link-driven navigation by changing the URL without updating the DOM
  - roster create/copy/publish stays on HTMX because those controls live inside the interactive roster surface and should keep updating in place
- App lifecycle contract for TurboLinks retirement:
  - feature code should initialize from one app-local `app:page-ready` event, not from `turbolinks:load`
  - `app:page-ready` fires for full-page loads (`DOMContentLoaded`) and after HTMX swaps/OOB swaps
  - the event detail shape is `{ target, source, isFullPage }`
  - `target` is the swapped subtree for HTMX events and `document.body` for full-page events
  - feature init must be idempotent and scoped to `target` when possible so the same code works for first render and partial refreshes
  - do not reintroduce a TurboLinks-style body-transition bridge; ordinary full-page navigation should rely on the browser and partial updates should stay on HTMX
  - keep tracked timer cleanup (`clearAllIntervals` / `clearAllTimeouts`) app-local because dev live reload still depends on it even after TurboLinks is gone

## Venue Bootstrap And Roster Defaults
- Current roster creation depends on active `slot_names`. If a venue has none, `createEmptyRosterWeek` and `AddRosterRowAction` can leave the roster effectively unusable.
- Treat that as a bootstrap invariant problem, not as an invitation to keep venue creation ad hoc. Venue creation, fixture seeding, and repair scripts should converge on one idempotent minimum-setup function.
- Future roster architecture should move toward roster groups as the scheduling boundary inside a venue. The long-term invariant is: every active venue has at least one active roster group, and every active roster group has at least one active slot definition.
- Staff applicability to roster groups should stay separate from venue membership/auth authority. Some staff may be eligible for one group, several groups, or all groups.

## Auth Model Notes
- Current business authority is venue-scoped. `venue_memberships.venue_role` is what grants manager/admin access; `users.user_role = 'admin'` is not a cross-venue superuser.
- `users.email` is the canonical case-insensitive login identity. Alternate sign-in methods must link to an existing invited account and must not create a public self-registration bypass.
- Passkeys live in `passkeys` as user-owned WebAuthn credentials. Registration is only available to an authenticated existing account; authentication resolves the credential to that existing user.
- For local development passkey preservation across `seed-dev app` resets, the viable approach is to dump real dev passkey rows once into a gitignored runtime artifact, for example `build/dev-passkeys.sql`, then have `seed-dev` execute that file after the normal reset and deterministic user seed. The SQL should insert by joining on `users.email`, not by hard-coding `user_id`, and every seeded account with a preserved passkey must have its original WebAuthn user handle recorded in `Application.Support.DevFixtures.seededUserIdsForPasskeys`. If a restored passkey fails with `AuthenticationCredentialUserHandleMismatch`, update that map to the first UUID in the error; the second UUID is the current database user id. Do not commit raw credential IDs/public keys into tracked source unless explicitly directed.
- To inspect or dump current dev passkeys, run `psql` through the project shell so it uses the active `PGHOST`, e.g. `bash ./bin/in-env sh -c 'psql -d app -c "select u.email, encode(p.credential_id, ''hex'') from passkeys p join users u on u.id = p.user_id;"'`. Avoid forcing `-h build/db`; devenv may expose Postgres through a socket under `/tmp/devenv-.../postgres`.
- To preserve a real local Xero demo connection across `seed-dev app`, dump a local-only SQL replay file to `build/dev-xero-connection.sql` (or set `$DEV_XERO_SEED_FILE`). The replay SQL should insert by joining the deterministic seeded venue owner, not by hard-coding volatile `venue_id` or `connected_by_user_id`; never commit encrypted Xero token rows, refresh tokens, access tokens, client secrets, or token encryption keys.
- Xero refresh tokens rotate on refresh. A saved `build/dev-xero-connection.sql` is only valid until that connection is refreshed/reconnected; replaying a stale file after `seed-dev app` can restore an already-used refresh token and force OAuth reauthorization. After reconnecting or successfully syncing Xero in dev, either regenerate the local replay file from the current DB row or move it aside before the next `seed-dev app`.
- Xero Payroll AU `POST /PayItems` is replacement-like for nested pay item lists. When creating a managed earnings rate, first pull `GET /PayItems`, then post the full current `EarningsRates` list plus the new/cumulative rates; posting only the new rate can make Xero try to delete omitted built-in rates and return a 200 response with `Type: ValidationException`. Treat top-level Xero `Type` error payloads as failures even when HTTP status is 2xx, and always verify creates with a follow-up `GET /PayItems` before marking local mappings created.
- For raw Xero pay item debugging without exposing tokens, use `bash ./bin/in-env xero-pay-item-probe app --connections`, then `--connection-id=<uuid> --list`, `--requirement-key=<key>` to print the exact payload, and add `--confirm-post` only when intentionally hitting Xero. The probe builds the same full `EarningsRates` payload as the app and never prints auth headers or token material.
- Xero connection management is restricted to the current venue owner or a super admin. The top-level Xero header button is visible to current venue owners and super admins; venue admins must not see Xero controls in Admin.
- WebAuthn credentials are origin/RP scoped. Dev passkeys restored into the DB will only keep working when the browser uses the same host that created them, so prefer `http://localhost:8000` consistently instead of switching between `localhost` and `127.0.0.1`.
- Password login success/failure/locked-account attempts for known venue-linked users are recorded in `audit_events`; keep future auth methods on the same event shape with an `authMethod` payload.
- Founder/sysadmin support access is now modelled separately on `users.platform_role = 'super_admin'`. Do not overload venue roles or create synthetic `venue_memberships` for cross-venue support access.
- Request-scoped support mode is represented by a real `currentVenue` plus `currentVenueMembershipOrNothing = Nothing` and `currentUserIsSuperAdmin = True`. Keep that shape intact so audit/UI layers can distinguish support access from ordinary venue membership access.
- The support switch surface lives on a dedicated `SupportController`. Keep venue switching there instead of stretching venue admin/export pages into cross-venue tooling.
