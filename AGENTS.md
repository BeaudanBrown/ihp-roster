# IHP Roster Agent Guidelines

This repository is tuned for agent-assisted IHP development. Keep the root file
short and project-wide; put subsystem-specific rules in the nearest local
`AGENTS.md`.

## Source Of Truth

Use this order when documents disagree:

1. Current code, `Application/Schema.sql`, generated types, migrations, and
   passing tests describe implemented behavior.
2. Subsystem-local `README.md`, `SPEC.md`, and `AGENTS.md` describe the living
   contract for the code beside them.
3. `specs/` describes product, domain, compliance, and acceptance intent that
   spans more than one subsystem.
4. `docs/workstreams/` describes future or in-progress feature streams.
5. `docs/adr/` records durable decisions and supersessions.
6. `.tickets/` is the live implementation graph and status tracker.
7. `docs/archive/` is historical context only.

## Read Order

Before changing a subsystem:

1. Read this file.
2. Read the nearest local `AGENTS.md`.
3. Read the subsystem `README.md` and `SPEC.md` if present.
4. Check `tk show <id>` for the active ticket.
5. If the work is future-facing, read the relevant file in
   `docs/workstreams/`.
6. Read archived plans only when a ticket or workstream explicitly links them.

## Branding Copy

Customer-facing product/app copy says "Bepis". "IHP" remains valid for
framework and technical references. `ihp-roster` remains valid for repo,
service, and internal ops names unless an ops migration explicitly renames them.

## Framework Reference

Prefer the sibling IHP checkout when present. Paths are relative to this
`ihp-roster` repository so they work across hosts with different parent paths:

- IHP guide: `../ihp/Guide/*.markdown`
- IHP source: `../ihp/ihp/IHP/`
- Generated types: `build/Generated/Types.hs`

If `../ihp` is missing, use the active Nix-provided IHP source as a read-only
fallback: run `bash ./bin/in-env env | rg '^(IHP|IHP_LIB|IHP_DEV_CHECKOUT)='`,
then inspect symlink targets with `readlink -f "$IHP"/*` and search the
resolved `*-source` tree. Do not edit Nix store files.

Read the relevant IHP guide before implementing controller, view, form,
database, auth, validation, or HSX changes.

## Project Map

- `Application/Schema.sql` - source of truth for database models.
- `Application/Helper/` - shared helpers and application services.
- `Web/Types.hs` - controller action types.
- `Web/Routes.hs` - `AutoRoute` instances.
- `Web/FrontController.hs` - mounted controllers and request context setup.
- `Web/Controller/` - controller implementations.
- `Web/View/` - HSX views and layout shell.
- `Test/` - Hspec coverage.
- `e2e/` - Playwright coverage.
- `static/` - app-owned CSS and JavaScript.
- `docs/` - documentation operating model, workstreams, ADRs, and archive.
- `specs/` - product/domain/compliance specs.

## Documentation Workflow

`tk` is the live tracker. Do not create parallel markdown checklists for work
already represented by tickets.

Use `docs/workstreams/` for feature streams that are not fully implemented yet.
A workstream must list its tickets, affected living docs, intended contract, and
exit criteria. As implementation lands, move durable facts into local
`README.md`, `SPEC.md`, or `AGENTS.md`; then close or archive the workstream.

Use `docs/adr/` when the reason for a decision matters after implementation.
Use `docs/archive/` for old plans and audits that should not guide new work by
default.

See `docs/README.md` and `docs/workstreams/README.md` before adding or moving
documentation.

## tk

Use repo-local `tk`:

```bash
tk ready
tk blocked
tk show <id>
tk dep tree <id>
```

Keep `.tickets/` checked in. Coordinator tickets are routing references; use
the linked repo-local `ir-*` ticket for implementation details.

## Core IHP Conventions

- New controllers require `Web/Types.hs`, `Web/Routes.hs`,
  `Web/FrontController.hs`, and `Web/Controller/*`.
- Controllers import `Web.Controller.Prelude`.
- Views import `Web.View.Prelude`.
- HSX uses `[hsx|...|]` quasi-quotes.
- Database queries use IHP QueryBuilder, not raw SQL in controllers.
- Form handling uses IHP form helpers.
- `fill` records parse errors but ignores missing params. Required
  server-side fields need explicit controller checks such as `requireParam`
  plus normal validation.
- Parse request-derived ids with total helpers, then validate venue/tenant
  scope before mutating.
- Build query strings with `appendQueryParams`; do not concatenate raw request
  text into URLs.
- Render CSV through `Application.Helper.Export.Render.csvCell` or higher-level
  export renderers.

## Auth And Venue Scope

- Venue business authority comes from `venue_memberships`, not `users`.
- Founder support access is platform-level (`users.platform_role =
  'super_admin'`) and must stay distinct from venue roles.
- A support-mode request has a real `currentVenue`, no
  `currentVenueMembership`, and `currentUserIsSuperAdmin = True`.
- Ordinary access must remain venue-scoped through current venue membership.

## Navigation And UI

- Global authenticated navigation lives in `Web/View/Layout.hs`.
- Header order is `roster`, `profile`, `timesheets`, `unavailability`, `xero`,
  `admin`, `support`, `logout`.
- `xero` is owner/super-admin only. `admin` is admin-gated. `support` is
  founder-only.
- Auth pages must not render the authenticated header.
- Use Bootstrap 5.3.8 vendor assets and `assetPath` for static references.
- App CSS is split under `static/css/` and linked from `Web/View/Layout.hs` via
  `assetPath`; keep new stylesheet links mirrored in `Makefile` `CSS_FILES` for
  style-audit/Layout sync. IHP `prod.js`/`prod.css` bundling is disabled.
- Do not use production CSS `@import` for app-owned files, because imports
  bypass IHP's `assetPath` cache busting.
- App JavaScript source lives under `frontend/ts/`; generated checked-in output
  is split by concern under `static/app*.js` and must not be hand-edited.
- Haskell-owned frontend contracts generate TypeScript under
  `frontend/ts/generated/`; use them for backend-emitted JSON/data boundaries.
  For typed interaction-surface work, Haskell must also own canonical surface,
  disposable-layer, intent, intent-field, and conflict-policy contracts consumed
  by TypeScript.
- Static and frontend runtime rules live in `static/AGENTS.md` and
  `frontend/AGENTS.md`; read
  `Application/Helper/FrontendContract/Surface/README.md` and
  `Application/Helper/Interaction.SPEC.md` before adding interaction runtime or
  `data-bepis-*` markup.

## Roster Week Navigation

- `weekOffset` in the URL is the source of truth for the viewed roster week.
- Use `ShowRosterWeekAction { weekOffset = ... }` for explicit navigation.
- `RosterWeeksAction` is the canonical this-week reset entrypoint.
- Do not persist a last-viewed week unless a future ticket explicitly requests
  it.

## Overlays And Live Updates

- Overlay lanes are separate: `dialog`, `picker`, and `toast`.
- Workflow dialogs should replace each other rather than stack.
- Prefer declarative overlay helpers in `Application/Helper/View/Overlay.hs`.
- For live surfaces, server-rendered HTML remains the source of truth. Actor
  responses use HTMX fragments/OOB swaps; passive viewers receive websocket
  invalidations and authorized fragment refetches.
- Live-update subsystem details live in `Application/Helper/LiveUpdate.SPEC.md`
  and local feature docs.

## Live Database And Migrations

Bepis is live and production data must be preserved. `Application/Schema.sql`
remains the canonical full schema for fresh databases and generated types, but
it is not by itself an upgrade path for deployed databases.

Every schema-affecting change must include a clear migration path using the IHP
migration system under `Application/Migration/`, unless the ticket explicitly
records why no deployed database change is required. Keep migrations
customer-data-preserving by default. Destructive changes such as dropping columns,
tables, enum values, or customer records require an explicit ticket, operator
runbook, backup/restore plan, and rollback/recovery notes.

Local `make db` is only for development/parser/startup verification and resets
local dev data. Do not treat `make db` as a production or staging migration
strategy.

For schema changes, update `Application/Schema.sql`, add the migration file(s),
regenerate generated types, run focused schema/code checks, and verify parser
compatibility with the dev DB/startup flow when enums, constraints, triggers, or
advanced SQL are involved.

## Verification

Use the repo wrapper unless you are already inside the devenv shell:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env hspec-coverage
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env e2e
bash ./bin/in-env ./bin/doc-drift-check
```

After schema changes:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

Also add the matching `Application/Migration/*.sql` upgrade path for deployed
databases. Then apply the schema to the local dev DB with `make db` while the
dev server is running, and restart/wait when enums or constraints changed.
Remember that `make db` resets local dev data and is not a live-data migration.

After controller changes, run focused or full `hspec-test`. After UI or
integration changes, run focused `e2e` or screenshots as appropriate.

For dev server automation:

```bash
bash ./bin/in-env dev-start
bash ./bin/in-env dev-wait
bash ./bin/in-env dev-stop
```

For DB access, prefer:

```bash
bash ./bin/in-env psql -d app -c "\dt"
```

## Maintaining Agent Docs

When you discover a reusable pattern or gotcha, update the nearest local
`AGENTS.md` or subsystem `SPEC.md`. Keep root `AGENTS.md` project-wide and
under control; do not let it become a second implementation plan.
