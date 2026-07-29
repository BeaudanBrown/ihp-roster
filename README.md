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

## Retained Feature Reachability

Epic #136's initial inventory grouped four features as disabled-but-retained.
The closeout state is more precise:

- the roster month-overview read model/fragment is intentionally dormant: its
  controller and behavior coverage remain, but the week header has no trigger;
- the single-day timeline remains a supported URL-scoped roster view with
  server rendering and direct behavior coverage, but the week-grid layout menu
  does not advertise it;
- trial-staff invitation create/resend routes and modal rendering are active
  through the staff-edit invitation flow; and
- the four fixed exports are active. Only the configurable report-definition
  engine was retired.

These are intentional application roots, not evidence for broad generated
browser reachability. Their server-only facts stay out of generated TypeScript
unless a production browser consumer requires them.

## Local Workflow

Run project commands through the wrapper unless you are already inside the
activated devenv shell:

```bash
# Additive fast feedback: typecheck, pure Hspec, desktop + canonical Pixel browser tier
bash ./bin/in-env verify-fast

# Complete local verification: Haskell/reachability, generated frontend, CSS/docs/architecture, and full browser tier
bash ./bin/in-env verify-full

# Individual canonical gates remain available
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
```

Within a checkout, named devenv commands execute their current source under
`Config/nix/scripts/` rather than a materialized Nix-store snapshot. Editing a
script body therefore does not require reloading the shell; changing command
registration or package dependencies under `Config/nix/flake/` still invalidates
direnv normally. Outside a checkout, packaged commands emit a warning before
using their embedded snapshot fallback. `verify-fast` and `verify-full` include
the deterministic `devenv-script-freshness-check` regression gate.

`e2e-fast` runs every browser source behavior once across desktop Chromium and
the canonical Pixel 7 profile. `e2e` remains the complete gate and repeats
profile-sensitive mobile behaviors on Galaxy S9+ and iPad Mini. Normal
typecheck, Hspec, and compiled E2E commands reuse a compatible fingerprinted
GHC cache; HPC remains isolated. DB-backed Hspec uses a private disposable
PostgreSQL instance on native temporary storage and prints its effective path
and durability settings at startup; use `bash ./bin/in-env test-postgres status`
or `stop` to inspect or remove it. The normal development database is separate.

For browser or integration work, use the managed dev server helpers:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env dev-stop
```

For foreground local development, `just dev` starts the app, frontend contract
watcher, frontend asset watcher, PostgreSQL, and MailHog. Observability remains
opt-in: use `IHP_ROSTER_DEV_OBSERVABILITY=1 just dev`, then use
`dev-workspace-info --json` to find the slot-derived Grafana port (3300 in the
primary checkout). Search Tempo for service `ihp-roster-dev` in the primary
checkout or `ihp-roster-dev-epic-N` in an epic worktree.

Managed development commands derive workspace-local process state, PostgreSQL
socket, app port, SMTP port, and MailHog port from the registered epic slot;
the primary checkout remains slot zero on ports 8000/1025/8025. Run
`bash ./bin/in-env dev-workspace-info` in any checkout to report its URLs and
state paths. `just start`, `dev-start`, `dev-status`, `dev-wait`, and `dev-stop`
apply workspace-derived environment and affect only that checkout. Explicit
`DEVENV_AGENT_STATE_DIR` roots are namespaced per worktree.

### Android PWA emulator

The opt-in Android emulator is separate from the default development shell and
normal verification gates. Its first launch currently downloads about 2.4 GiB
for the pinned Android API 35 Google Play image and emulator closure; later
launches reuse the AVD under `.devenv/android/`.

Start Bepis before launching the emulator:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
just android-start
```

The launcher uses `adb reverse` to expose the host app as
`http://localhost:8000`, then opens `/InstallApp` in Android Chrome. Complete
Chrome's first-run screen on a new AVD, then use **Install Bepis** or Chrome's
**Install app** menu action.

```bash
just android-status
just android-open
just android-stop
```

The host must provide writable `/dev/kvm`; on NixOS this normally means KVM is
enabled and the user belongs to the `kvm` group. The flake keeps Android's
unfree-package and SDK-license acceptance isolated to this emulator package
set.

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
- IHP-provided Flatpickr asset
- App CSS files: split under `static/css/` and linked directly from
  `Web/View/Layout.hs` with `assetPath`
- Do not recreate a catch-all `static/app.css` unless a compatibility ticket
  explicitly requires it; app-owned CSS should stay split under `static/css/`
- PWA manifest icons use content-versioned filenames because manifest JSON
  cannot call `assetPath`; update their manifest paths whenever icon bytes change
- App JS entrypoints: generated `static/app-bootstrap.js`,
  `static/app-date-pickers.js`, `static/app-dialog-overlays.js`,
  `static/app-horizontal-scroll.js`, `static/app-interactions.js`,
  `static/app-live-updates.js`,
  `static/app-passkeys.js`, `static/app-preferences.js`,
  `static/app-pwa.js`, `static/app-roster.js`, `static/app-scrollbars.js`,
  `static/app-time-picker.js`, `static/app-timesheets.js`,
  `static/app-toasts.js`, `static/app-toggle-buttons.js`, and
  `static/app-xero.js`
- Frontend contracts: Haskell-owned DTOs/enums and registered Surface specs are
  evaluated through the single checked reflection path and generate TypeScript
  under `frontend/ts/generated/`; use them for backend-emitted JSON/data
  boundaries instead of duplicating broad backend or database models in browser
  code. Surface, mount-target, disposable-layer, intent, intent-field, and
  conflict-policy contracts are derived from Haskell rather than hand-defined
  as canonical browser strings. Private mechanical Haskell Surface adapters use
  the same checked IR and typed ownership registry; they are written and checked
  by the `frontend-surface-adapters` commands.

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
bash ./bin/in-env frontend-generated-ensure
bash ./bin/in-env frontend-generated-sync
bash ./bin/in-env frontend-generated-watch
bash ./bin/in-env frontend-surface-adapters
bash ./bin/in-env frontend-surface-adapters-check
bash ./bin/in-env frontend-watch
bash ./bin/in-env generated-code-sync
```

`frontend-check` runs contract drift, strict TypeScript validation including
unused-code checks, frontend unit/DOM tests, and generated JS drift. The full
verification gate additionally runs curated FrontendContract GHC warnings and
Weeder reachability, CSS stale-selector ownership, architecture freshness, and
documentation drift. `dev-start` and `just dev` first use content fingerprints
to generate only stale frontend contracts, Haskell Surface adapters, and
JavaScript, then run the coordinated frontend-generated watcher plus the
frontend asset watcher. IHP's `RunDevServer` remains the sole live owner of
schema-derived `build/Generated/` Haskell types. Foreground observability is
opt-in via `IHP_ROSTER_DEV_OBSERVABILITY=1`; `dev-stop` cleans up detached dev
processes. There is no Vite dev server or true HMR requirement. Contract-source
edits regenerate both Haskell adapters and `frontend/ts/generated/contracts.ts`;
the asset watcher then rebundles dependent JS. `generated-code-sync` (or
`just regen-all`) unconditionally regenerates all code. Frontend unit tests and
Playwright E2E are not pre-commit hooks; the tracked pre-commit hook only guards
generated JS drift. Production/live
NixOS runtime serves checked-in generated static JS and does not require
Node/esbuild/TypeScript/frontend test tooling.

## CI

`.github/workflows/test.yml` runs the same wrapper commands agents use locally:

```bash
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
```

The required CI scope remains typecheck plus complete Hspec. Those sequential
steps reuse the fingerprinted verification compilation cache; browser tiers are
local/release commands and are not a newly mandatory CI gate.

Deployment is managed outside this workflow. Production NixOS configuration lives
under `Config/nix/`.

## Generated And Local Artifacts

Generated screenshots, profiles, reports, local databases, Nix build outputs, and
dev shell state are ignored. Keep durable visual references in documentation
assets, not under `output/`.

## Documentation

Start with `docs/README.md` for the documentation operating model.

- Implemented subsystem behavior belongs in local `SPEC.md` files beside code.
- Future feature streams belong in `docs/workstreams/` and must link to GitHub Issues.
- Durable decisions belong in `docs/adr/`.
- Historical numbered plans live in `docs/archive/plans/`.

## License

Bepis is licensed under the Apache License 2.0. See [LICENSE](./LICENSE).

Third-party notices are listed in
[THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md).
