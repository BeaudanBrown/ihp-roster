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
- **Bootstrap 5.2.1** is included via vendor files — use Bootstrap classes in HSX
- Custom CSS goes in `static/app.css` (loaded by `Web/View/Layout.hs`)
- Custom JS goes in `static/app.js`
- The layout shell is defined in `Web/View/Layout.hs` — edit `defaultLayout` to change page structure
- Use `assetPath` for all static asset references (enables cache-busting in production)

## App Navigation Conventions
- Global authenticated navigation lives in `Web/View/Layout.hs` and is rendered on every authenticated page
- Header button order is: `roster`, `profile`, `timesheets`, `leave`, `admin`, `support`, `logout`
- `admin` is role-gated (admin-only visibility); `timesheets` and `admin` may route to placeholder pages until fully implemented
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
- `IMPLEMENTATION_PLAN.md` is the canonical roadmap for global ordering and cross-pipeline dependencies.
- Detailed execution plans live under `plans/` and are scoped by workstream; read only the relevant pipeline file after reading the root roadmap.
- `plans/90-historical-completed-slices.md` holds completed or superseded detail that may still matter for migration work.

## Coordinator Workstreams

- Active coordinator-managed workstreams live under `.loom/workstreams/<workstream>/`.
- Read `.loom/AGENTS.md` before editing files there.
- Use `.loom/workstreams/<workstream>/context.md` and `handoff.md` as the repo-local execution memory for a tracked workstream.
- When a workstream needs repeated unattended Codex passes inside one Loom session, use `.loom/bin/codex-workstream-loop.sh` plus that workstream's `loop-launch.md`.
- Keep durable project-wide learnings in this `AGENTS.md` or the repo's own plans/specs rather than leaving them only in a workstream handoff.
- Reusable one-shot coordinator runs live under `.loom/runs/<category>/<run>.md` and should not create persistent workstream state unless explicitly promoted.

## Learning Capture

- If a command, workaround, or constraint is likely to matter again across this repo, add it here or to the most relevant spec.
- Keep workstream-specific resume notes in `.loom/workstreams/<workstream>/handoff.md`.
- Keep long debug trails in `.loom/workstreams/<workstream>/history.md` only while the workstream is active.
- For reusable one-shot runs, keep the durable run instructions in `.loom/runs/` and promote any stable repo-wide findings back into this file or the relevant specs.

## Overlay Architecture
- Treat overlays as three separate lanes:
  - `dialog` for workflow forms and confirmations
  - `picker` for short-lived utility selection flows such as the quarter-hour time picker
  - `toast` for transient notifications
- Multiple overlay triggers may exist on a page, but only one workflow dialog should be active at a time in the shared dialog mount.
- Do not build arbitrary nested workflow dialogs. A picker may appear above a workflow dialog, but dialogs should replace each other rather than stack.
- Prefer declarative overlay config in `Application/Helper/View.hs` over ad-hoc per-view footer buttons. Shared forms should usually render fields only; overlay wrappers own primary and secondary actions.
- For responsive HTMX flows, return the smallest updated fragment plus any out-of-band overlay updates. Avoid whole-page redirects when the current screen can be updated in place.

## Overlay Implementation Plan
- Shared overlay helpers live in `Application/Helper/View.hs` and define the canonical mount ids, config records, footer button rendering, and toast rendering.
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
bash ./bin/in-env test
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
- **`test`** — Compile and run the hspec test suite. **Add tests for every new controller** (see `Test/AGENTS.md`).
- **`lint`** — Run hlint on app sources. Provides suggestions for idiomatic Haskell.
- **`format`** — Format app sources with stylish-haskell (config in `.stylish-haskell.yaml`).
- **`ghci-app`** — Launch GHCi with the full app loaded for testing expressions interactively.
- **`seed-dev [app|app_test] [--force]`** — Seed a broader current-week development dataset for manual inspection, including a busy multi-group roster venue, support/bootstrap scenarios, and the richer payroll parity venue. The command now always resets the target DB first; `--force` is accepted as an explicit no-op compatibility flag.
- **`just seed-dev`** — Human-friendly default for manual dev exploration. This always wipes and reseeds `app` so the running dev app reflects the seeded venues immediately.
- **`new-controller NAME`** — IHP code generator that scaffolds controller, views, types, and routes. Prefer this for new CRUD controllers, then customize.
- **`e2e`** — Run Playwright end-to-end tests against an isolated `app_e2e` database and a temporary app server on the next free local IHP dev port. Accepts playwright args (e.g. `e2e --headed`, `e2e e2e/auth.spec.ts`). The local Postgres socket still needs to be available, but this wrapper no longer reuses the normal dev app/database.
- **`screenshot`** — Take a screenshot of a page. Usage: `screenshot http://localhost:8000/Dashboard dash.png`. Requires `devenv up` running.
- **`screenshot-page`** — Authenticated Playwright screenshot helper for arbitrary app pages. Preferred over ad hoc browser scripts when the page requires seeded login/profile completion or a shell-specific wait selector. Supports `--selector`, `--base-url`, `--email`, `--password`, `--login-path`, `--login-selector`, `--post-login-url-pattern`, `--navigation-timeout-ms`, `--selector-timeout-ms`, `--wait-ms`, and `--no-login`.
- **`e2e-report`** — Open the Playwright HTML test report from the last run.
- **`dev-start`** — Start the IHP `start` script in background for automation (no PTY dependency). Writes pid/log to `.devenv/agent/` and fails fast if startup exits early.
- **`dev-stop`** — Stop background server started by `dev-start`. If the app is healthy but was started outside `dev-start`, it reports `healthy but unmanaged` and does not kill it.
- **`dev-status`** — Health check for background dev server (process/socket + DB + HTTP). In restricted sandboxes it may report `*_blocked=true` and still succeed when the process is running. Permission-denied detection uses the Nix-provided `ripgrep` binary from the dev shell, so run it through `bash ./bin/in-env` unless you are already inside the shell.
- **`dev-wait [seconds]`** — Wait until `dev-status` is healthy (default timeout: 90s). On timeout it prints `dev-status` plus recent `.devenv/agent/devenv.log` lines for debugging.
- The background wrapper state for `dev-start`/`dev-stop`/`dev-status` now prefers `$XDG_RUNTIME_DIR/ihp-roster-dev` (or `DEVENV_AGENT_STATE_DIR` if set) instead of the repo tree. This avoids Syncthing or shared-working-tree conflicts on volatile pid/socket files. The old repo-local `.devenv/agent` path is only a fallback when no runtime dir is available.
- The app runs via `devenv up` — it auto-reloads on file changes, so you can check the browser for runtime behavior.
- A thin human-facing `justfile` exists for interactive use inside the already-activated dev shell. Treat it as aliases only (`just dev`, `just db`, `just test`, `just e2e`, etc.); keep the real command logic in the flake/devenv scripts instead of duplicating it in `justfile`.

For reliable non-interactive automation, prefer:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
# run commands that need server + DB
bash ./bin/in-env dev-stop
```

## Adding a New Feature (e.g. a new page with database table)

1. **Schema** — Add table to `Application/Schema.sql`, then:
   - Run `bash ./bin/in-env regen-types` to regenerate Haskell types
   - Run `make db` (requires `devenv up` running) to apply the schema to the dev database — **skipping this causes "relation does not exist" crashes at runtime even when typecheck passes**
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
8. **DB check** — Confirm the table exists: `psql -h "$PWD/build/db" app -c "\dt"`
9. **Polish** — Run `bash ./bin/in-env lint`, then `bash ./bin/in-env format`

For simple CRUD, prefer running `new-controller NAME` to scaffold all files, then customize.

## Verification Workflow
- **After every code change**: `bash ./bin/in-env typecheck` (fast, ~2-3s)
- **After schema changes**: `bash ./bin/in-env regen-types` first, then `bash ./bin/in-env typecheck`, then `make db` (requires `devenv up`)
- **After schema changes involving enums or constraints**: after `make db`, restart and wait for the dev server (`bash ./bin/in-env dev-stop`, `bash ./bin/in-env dev-start`, `bash ./bin/in-env dev-wait`) to catch startup-only schema-parser failures; this is why the earlier QC pass missed the `pg_dump`-roundtrip issue
- The IHP schema-designer toast about `Unmigrated Changes` is not an authoritative sync check in this repo; it is driven by the IDE migration workflow state and can stay stale even after `make db`. Treat `make db` plus explicit DB/startup verification as the real source of truth.
- **After adding/changing controllers**: `bash ./bin/in-env test` to run the test suite
- **After UI/integration changes**: `bash ./bin/in-env e2e` to run end-to-end tests against the isolated test DB/server
- `bash ./bin/in-env test` rebuilds `app_test`, while `bash ./bin/in-env e2e` rebuilds `app_e2e`. They no longer share a database, so parallel Hspec and Playwright runs are safe as long as both use the local Postgres socket under `build/db`.
- **Before committing**: `bash ./bin/in-env lint` then `bash ./bin/in-env format`
- **To confirm DB is in sync**: `psql -h "$PWD/build/db" app -c "\dt"` — all tables in `Schema.sql` should be present

## E2E Testing

Playwright-based end-to-end tests live in `e2e/` and run against an isolated temporary app server on the next free local IHP dev port, backed by `app_e2e`. See `e2e/AGENTS.md` for the full guide.

- **Config**: `playwright.config.ts` — single chromium project, serial execution
- **Test data**: Seeded via `e2e/fixtures/seed.sql` (manager: `e2e-test@example.com`, worker: `e2e-worker@example.com`, both with password `test-password-123`)
- **Cleanup**: `global-teardown.ts` deletes all rows with `e2e-` prefixed emails and removes worker-owned leave/timesheet rows before deleting dependent snapshots
- **Browsers**: Provided by Nix via `playwright-web-flake` — no manual browser install needed
- **CLI invocation**: In automation and Loom runs, prefer `bash ./bin/in-env e2e` / `screenshot` / `e2e-report` instead of bare `npx playwright ...`; the wrapper resolves the repo-local Playwright CLI inside the dev shell so the runner matches the imported test package
- **Authenticated/manual captures**: Prefer `bash ./bin/in-env screenshot-page ... --selector '<real-shell-selector>'` for arbitrary screenshots. On cold IHP boots, increase both `--navigation-timeout-ms` and `--selector-timeout-ms` instead of cloning the helper or writing one-off screenshot scripts.
- **Exploratory browser work**: Use `bash ./bin/in-env pwcli ...` for ad hoc Playwright CLI sessions, targeted screenshots, and live selector discovery. For authenticated exploration, create role state explicitly with `bash ./bin/in-env pwcli-auth-save <manager|worker|admin|support>` and then open a pre-authenticated session with `bash ./bin/in-env pwcli-auth-open <role> <path>`.
- **npm deps**: `@playwright/test` version in `package.json` must match the `playwright-web-flake` tag in `flake.nix`

## Maintaining Agent Documentation
- Subdirectory `AGENTS.md` files exist in `Web/Controller/`, `Web/View/`, and `Application/` with detailed patterns
- When you discover a new IHP pattern, convention, or gotcha while implementing a feature, **add it to the relevant `AGENTS.md`** so future agents benefit
- Keep entries concise and actionable — show the code pattern, not lengthy explanations
- Always verify patterns against `/home/beau/documents/projects/ihp/Guide/` or `/home/beau/documents/projects/ihp/ihp/IHP/` source before documenting

## Current UI Patterns
- Roster and timesheet week pagers use HTMX shell swaps with pushed canonical URLs instead of full-page week navigations
- The roster staff sidebar uses CSS-only desktop behavior: sticky positioning, viewport-capped height, and internal list scrolling
- Roster collaboration uses a split live-update path:
  - actor browser gets immediate HTMX fragments/OOB swaps from the mutation response
  - concurrent viewers get websocket invalidation payloads plus authorized fragment refetch
- Roster week pages now subscribe even on empty/hidden-week shells so create/copy/publish transitions can update passive viewers without IHP Auto Refresh
- The app no longer loads `ihp-auto-refresh.js`, emits Auto Refresh meta, or calls `initAutoRefresh`; page freshness is expected to come from explicit HTMX/live-fragment flows instead of framework-wide polling.
- Auto Refresh audit result as of `2026-03-15`: there are no remaining app-runtime `autoRefresh` consumers under `Web/Controller/`, `Application/`, `Web/FrontController.hs`, or `Web/View/Layout.hs`.
- Keep live invalidation payloads structural (`scope`, `fragmentKey`, `targetId`, `url`, `deferUntilBlur`) rather than broadcasting rendered HTML across viewers
- When a roster mutation should not clobber focused inputs remotely, mark that fragment `deferUntilBlur = true` and let the client replay it after row blur
- The app-wide live-update direction is:
  - one websocket connection per browser tab/client
  - many scope subscriptions per connection
  - scopes represent authorized logical data slices, not pages
  - invalidations are routed by scope and carry explicit fragment refs
  - clients refetch only the invalidated fragments they currently have mounted
  - one mutation may invalidate multiple scopes, and only a subset of fragments within each scope
- The transport/client pattern is reusable across other collaborative pages. Keep the websocket/refetch core shared, and add small per-feature adapters for DOM discovery, swap rules, and focus deferral where needed.
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
- Founder/sysadmin support access is now modelled separately on `users.platform_role = 'super_admin'`. Do not overload venue roles or create synthetic `venue_memberships` for cross-venue support access.
- Request-scoped support mode is represented by a real `currentVenue` plus `currentVenueMembershipOrNothing = Nothing` and `currentUserIsSuperAdmin = True`. Keep that shape intact so audit/UI layers can distinguish support access from ordinary venue membership access.
- The support switch surface lives on a dedicated `SupportController`. Keep venue switching there instead of stretching venue admin/export pages into cross-venue tooling.
