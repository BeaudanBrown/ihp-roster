# Application Agent Guidelines

Read this before editing `Application/`.

## Schema

`Application/Schema.sql` is the source of truth for database models. Read
`/home/beau/documents/projects/ihp/Guide/database.markdown` before schema work.

Conventions:

- Use `snake_case` for table/column names; IHP converts to camelCase in
  Haskell.
- Table names are plural.
- Put `id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL` first.
- Use `created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL` and
  `updated_at` where appropriate.
- Prefer PostgreSQL enums for finite states when generated constructor names
  will not collide.
- Avoid enum type names starting with built-in SQL type tokens such as `time`,
  `timestamp`, or `interval`.
- If enum values would collide with model constructors, keep the column as
  `TEXT` and use parser-safe explicit `OR` checks instead of `IN (...)`.
- Prefer simple parser-safe `CHECK` constraints using `char_length`, `btrim`,
  and explicit `OR` expressions.

After schema edits:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

During development, IHP's `RunDevServer` is the sole live owner of schema-derived
`build/Generated/` regeneration. Do not add a competing project schema watcher;
the cache-aware frontend generation watcher owns only Haskell Surface adapters
and TypeScript contracts.

Bepis is live and production data must be preserved. Pair every schema-affecting
change with a migration path in `Application/Migration/`; see
`Application/Migration/README.md`. `Application/Schema.sql` is the canonical full
schema for fresh databases and generated types, while migrations upgrade existing
live/staging/production databases.

Apply the schema to the local dev database with `make db` while the dev server is
running. This resets local dev data and does not replace a migration. For
enum/constraint changes, restart and wait for the dev server to catch
startup-only schema-parser failures.

Prefer additive live-safe migration order: add nullable/defaulted structures,
backfill existing rows, verify shape, then tighten constraints or remove old
compatibility paths later when needed. Do not drop columns, tables, enum values,
or customer data without an explicit ticket, operator-approved runbook,
backup/restore plan, and rollback/recovery notes. If a schema edit intentionally
needs no deployed database migration, record the rationale in the ticket or
commit notes.

`Application/Fixtures.sql` must keep a deterministic founder/bootstrap account
usable after `make db`. Venue business authority still comes from
`venue_memberships`; do not rely on `users.user_role = 'admin'`.

## Current Data Direction

- Venue is the current customer/data boundary.
- `users` is global identity.
- `venue_memberships` owns venue business roles.
- Founder support access is platform-level `users.platform_role =
  'super_admin'`, not synthetic venue membership.
- Venue-linked operational accounts should have one linked `staff` row per
  `(venue_id, user_id)` pair.
- Payroll-adjacent records must preserve provenance.
- Pay/config reproducibility is moving to append-only relational version ids;
  see `docs/workstreams/pay-config-versioning.md`.

## Development Fixtures

- `Application.Support.DevFixtures` keeps linked generated users backed by active
  venue memberships.
- The realistic dev roster must retain all 12 supported staff/shift pay-mode
  pairings (`award_rate`, `xero_rate`, `roster_only` × `staff_default`,
  `award_rate`, `xero_rate`, `roster_only`) on actual slots. Trials remain
  roster-only, and one unassigned linked profile remains `legacy_unresolved` for
  remediation testing.

## Helper Ownership

- Generic controller helper notes: `Application/Helper/Controller/AGENTS.md`.
- Shared view helper notes: `Application/Helper/View/AGENTS.md`.
- Export helper contract: `Application/Helper/Export/README.md`,
  `Application/Helper/Export/SPEC.md`, and
  `Application/Helper/Export/AGENTS.md`.
- Xero application contract: `Application/Xero/README.md`,
  `Application/Xero/SPEC.md`, and `Application/Xero/AGENTS.md`.
- Live-update contract: `Application/Helper/LiveUpdate.SPEC.md`.

Top-level compatibility modules such as `Application/Helper/View.hs` and
`Application/Helper/Export.hs` should stay re-export facades. Add new
implementation to focused submodules first.

## Queries

Read `/home/beau/documents/projects/ihp/Guide/querybuilder.markdown`.

Use IHP QueryBuilder for application/database queries. Avoid raw SQL in
controllers. Validate venue/tenant scope before mutating user-requested ids.

## Verification

Run `bash ./bin/in-env typecheck` after code changes. Add focused Hspec when
changing helper behavior or schema constraints. Schema changes also need
`regen-types`, matching `Application/Migration/*.sql` files for deployed
databases, and local dev DB/startup verification.
