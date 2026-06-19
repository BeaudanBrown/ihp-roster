# Database Migrations

This directory contains IHP migrations for upgrading existing deployed databases.
Bepis is live and production data must be preserved.

`Application/Schema.sql` remains the canonical full schema for fresh databases and
for generated Haskell types. Migration files are the upgrade path for databases
that already contain user/customer data. A schema-affecting change is not complete
until both the full schema and the migration path are clear.

## Requirements

- Pair every `Application/Schema.sql` change with one or more migration files in
  this directory, unless the ticket explicitly records why no deployed database
  change is required.
- Keep migrations data-preserving by default. Do not drop tables, columns, enum
  values, or customer records without an explicit ticket, operator-approved
  runbook, backup/restore plan, and rollback/recovery notes.
- Prefer additive rollout order: add nullable/defaulted structures, backfill,
  verify data shape, then tighten constraints or remove old compatibility paths
  in a later migration when needed.
- Use parser- and runner-safe SQL. Prefer `IF EXISTS` / `IF NOT EXISTS` where it
  is safe, and account for IHP's transactional migration runner before using
  PostgreSQL features such as `CREATE INDEX CONCURRENTLY`.
- For constraints, triggers, indexes, enum changes, and backfills, document the
  intended data transition in the ticket or commit notes.

## Verification

For schema changes, run the normal local checks:

```bash
bash ./bin/in-env regen-types
bash ./bin/in-env typecheck
```

Apply the schema to the local dev database with `make db` only for local parser
and startup verification. `make db` resets local dev data and does not replace a
migration for live/staging/production databases.

When enum, constraint, trigger, or parser-sensitive SQL changes are involved,
restart/wait for the dev server after applying locally so IHP sees the final
`pg_dump` shape.
