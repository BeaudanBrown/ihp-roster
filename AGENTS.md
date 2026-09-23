# IHP Roster Agent Guidelines

Keep this file project-wide. Read the nearest local `AGENTS.md` before changing
a subsystem; local files own editing patterns and focused verification.

## Sources Of Truth

When sources disagree, use this order:

1. Current code, `Application/Schema.sql`, generated types, migrations, and
   passing tests describe implemented behavior.
2. Subsystem-local `README.md`, `SPEC.md`, and `AGENTS.md` provide navigation
   and retained contracts beside the code they govern.
3. `specs/` holds cross-cutting product, domain, compliance, and acceptance
   intent.
4. `docs/workstreams/` holds unresolved future or partial design.
5. `docs/adr/` records durable decisions and supersessions.
6. GitHub Issues is the live implementation graph and status tracker.
7. `docs/archive/` is historical context only.

Start with the active GitHub issue and its native relationships, then read the
nearest local agent notes and subsystem README/SPEC. Read a workstream only for
future-facing work and an archive only when the issue or workstream links it.
Follow `docs/README.md` when retaining, moving, or removing prose; never create a
parallel Markdown task tracker.

## Epic Worktree Delegation

In a checkout with `.bepis-epic-worktree.json`, first run:

```bash
bash ./bin/in-env epic-worktree orient
```

Present the ready/active/blocked frontier, select the most appropriate ready
issue, and begin it without waiting for routine confirmation. Continue through
implementation, verification, commit, issue closure, refreshed orientation, and
the next most appropriate ready issue by default. Stop for user input when the
user has asked to retain control of selection or progression, when interrupted
work must be resolved, when the parent epic is closed, or when an important or
unexpected technical/product decision needs user judgment. Do not treat labels
or assignments as locks, but respect native blockers and avoid duplicating active
work. Prefer unassigned ready work; before starting an assigned issue, inspect its
activity and proceed only when another actor is not actively implementing it.
Synchronization, integration, epic closure, and cleanup remain separate approval
boundaries.

Run commands through the current worktree's `bin/in-env`. Before runtime E2E in
a sibling checkout, confirm `dev-workspace-info --json` reports its expected
path and slot. After explicit synchronization approval for an unpushed completed
epic, prefer `epic-worktree-manage sync --strategy rebase --apply`, verify it,
then obtain separate integration approval before
`integrate --mode ff-only --approve`; do not combine integration, epic closure,
or cleanup.

## Product And Framework

Customer-facing copy says **Bepis**. IHP remains correct for framework
references; `ihp-roster` remains correct for repository and internal operations
names.

Before controller, view, form, database, auth, validation, or HSX work, read the
relevant IHP guide. Prefer the sibling checkout:

- guide: `../ihp/Guide/*.markdown`
- source: `../ihp/ihp/IHP/`
- generated application types: `build/Generated/Types.hs`

If `../ihp` is absent, locate the read-only Nix source with
`bash ./bin/in-env env | rg '^(IHP|IHP_LIB|IHP_DEV_CHECKOUT)='` and
`readlink -f "$IHP"/*`. Never edit Nix store files.

## Cross-Cutting Safety

Venue business authority comes from `venue_memberships`, not `users`. Founder
support authority is platform-level `users.platform_role = 'super_admin'` and
must remain separate from venue roles. Ordinary access stays scoped through the
current venue membership; support mode has a real current venue and no current
venue membership.

Bepis is live. Preserve customer data. Every schema-affecting change needs both
`Application/Schema.sql` and a customer-data-preserving upgrade path under
`Application/Migration/`, unless the issue explicitly records why no deployed
change is needed. Dropping data, columns, tables, or enum values requires an
explicit issue, operator runbook, backup/restore plan, and rollback/recovery
notes. Local `make db` resets development data and is never a deployment
strategy. Read `Application/AGENTS.md` and `Application/Migration/README.md`
before schema work.

Generated files must be changed through their owners. App JavaScript is authored
under `frontend/ts/`; checked-in `static/app*.js` is generated. Backend-owned
contracts generate `frontend/ts/generated/`. Read `frontend/AGENTS.md` and
`static/AGENTS.md` before frontend or asset changes. Do not add external CDN
runtime assets.

Authenticated navigation is owned by `Web/View/Layout.hs`; its order is
`roster`, `profile`, `timesheets`, `unavailability`, `xero`, `billing`, `admin`,
`support`, `logout`. Detailed controller, view, interaction, live-update, CSS,
Hspec, and Playwright rules belong to their local docs.

## Verification

`weeder-check` compiles the complete application Haskell source inventory to fresh HIE
and rejects candidates against `Config/nix/weeder-baseline.tsv`. Keep runtime
roots category-narrow and reason-bearing; never blanket-root handwritten
application modules or retain stale baseline entries.

Use the repo wrapper unless you are already inside the devenv shell. Do not
start multiple outer `bin/in-env` entries concurrently: their direnv/devenv
materialization can race on generated `.devenv` files. A single `bin/in-env`
entry may run independent checks concurrently only when they are read-only and
use isolated outputs. Current safe candidates include `lint`,
`typed-contract-authority-check`, and `./bin/doc-drift-check`. Keep `typecheck`,
Hspec, frontend composite checks, E2E, generators, formatters, database checks,
and `verify-*` composites serial unless their owning script provides internal
sharding or explicitly isolated build/runtime directories. Prefer that built-in
parallelism (`hspec-test` and `e2e` already shard) over competing top-level
commands. When uncertain, run serially. Use cheap/focused checks before expensive
full gates, and validate worktree identity before starting any runtime-dependent
E2E check. Stop and report infrastructure failures separately from code failures
instead of broadening an integration task into runtime repair.

```bash
bash ./bin/in-env verify-fast
bash ./bin/in-env verify-full
bash ./bin/in-env typecheck
bash ./bin/in-env hspec-test
bash ./bin/in-env hspec-coverage
bash ./bin/in-env frontend-check
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env typed-contract-authority-check
bash ./bin/in-env ./bin/doc-drift-check
```

After schema changes, run `regen-types`, typecheck, migration/schema checks, and
local parser/startup verification. After controller changes, run focused Hspec;
after UI/integration changes, run focused E2E or screenshots as appropriate.

When reporting, be extremely concise; sacrifice grammar for concision.
