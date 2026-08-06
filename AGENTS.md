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

Delegation and work selection are explicit user decisions. In a checkout with
`.bepis-epic-worktree.json`, first run:

```bash
bash ./bin/in-env epic-worktree orient
```

Present the ready/active/blocked frontier and wait. Never select, start, move, or
close a sub-issue automatically. Implement and commit the chosen issue, present
verification, then wait for approval before closure. Synchronization,
integration, epic closure, and cleanup are separate approval boundaries.

Run commands through the current worktree's `bin/in-env`. Before runtime E2E in
a sibling checkout, confirm `dev-workspace-info --json` reports its expected
path and slot. For an unpushed completed epic, prefer
`epic-worktree-manage sync --strategy rebase --apply`, verify it, then
`integrate --mode ff-only --approve`; do not combine integration, issue closure,
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

Use the repo wrapper unless you are already inside the devenv shell. Run
`bin/in-env` commands serially: concurrent wrapper entries can race on generated
`.devenv` shell files and produce false setup failures. Use cheap/focused checks
before expensive full gates, and validate worktree identity before starting any
runtime-dependent E2E check. Stop and report infrastructure failures separately
from code failures instead of broadening an integration task into runtime repair.
On memory-constrained hosts, also stop dev hot reload and avoid triggering HLS
reloads while running compile-heavy typecheck, Hspec, generator, or `verify-full`
gates; independent GHC heaps can otherwise exhaust RAM and swap even when each
command passes alone.

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
