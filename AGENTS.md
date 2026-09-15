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

A user may delegate one issue, an ordered set of issues, or an entire epic. For
a delegated epic, repeatedly select the next open, unblocked sub-issue from the
native GitHub dependency graph, implement it, commit it, and continue without
requesting confirmation between issues. Pause only when progress requires an
unexpected user decision, including material product ambiguity, conflicting
contracts, destructive or customer-data-risking work, a consequential
architectural choice, unavailable credentials, or a blocking infrastructure
failure. Do not silently broaden scope to repair unrelated failures.

Run commands through the current worktree's `bin/in-env`. Before runtime E2E in
a sibling checkout, confirm `dev-workspace-info --json` reports its expected
path and slot. For an unpushed completed epic, prefer
`epic-worktree-manage sync --strategy rebase --apply`, verify it, then
`integrate --mode ff-only --approve`. GitHub mutations, synchronization,
integration, epic closure, and cleanup must continue to respect approval
boundaries imposed by the agent harness.

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
`.devenv` shell files and produce false setup failures. Stop and report
infrastructure failures separately from code failures instead of broadening an
implementation task into runtime repair.

During delegated epic implementation, keep each intermediate commit mechanically
sound. After code edits, inspect language-server diagnostics and run:

```bash
bash ./bin/in-env typecheck
```

Run additional per-commit checks only when required to keep generated artifacts,
schema contracts, migrations, or other hard build boundaries valid, or when a
change is unusually risky. Schema changes must still include their
customer-data-preserving migration in the same commit; run `regen-types` and the
minimum migration/schema checks needed to establish that hard boundary.

Defer broad Hspec, frontend, E2E, lint, formatting, coverage, weeder,
documentation-drift, and full verification gates until the epic implementation
phase is complete. Then run affected focused checks, the appropriate
repository-wide gates, and final Standards and Spec review. Available gates
include:

```bash
bash ./bin/in-env verify-fast
bash ./bin/in-env verify-full
bash ./bin/in-env hspec-test
bash ./bin/in-env hspec-coverage
bash ./bin/in-env frontend-check
bash ./bin/in-env e2e
bash ./bin/in-env lint
bash ./bin/in-env format
bash ./bin/in-env typed-contract-authority-check
bash ./bin/in-env ./bin/doc-drift-check
```

Before runtime E2E, validate worktree identity. Do not defer safety-critical
migration correctness merely to reduce verification time.

When reporting, be extremely concise; sacrifice grammar for concision.
