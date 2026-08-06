# Application Agent Guidelines

Read the relevant IHP database/query guide referenced by root `AGENTS.md` before
schema or query work.

## Schema And Migrations

`Application/Schema.sql` is the canonical fresh-database schema and generated
model source. Follow IHP naming conventions and keep constraints parser-safe.
Generated PostgreSQL enum constructors are the application identity for
schema-backed states: use constructors for trusted values, total parsers for
external text, and exhaustive centralized projections. Avoid enum names that
start with SQL type tokens and constructor collisions with models.

Apply the live-data safety requirements in root `AGENTS.md`. For Application
work, pair every schema-affecting change with a customer-data-preserving
migration under `Application/Migration/`; read its README. Prefer additive
changes, backfill, verify, then tighten. When no deployed migration is needed,
record the rationale in the ticket or commit notes.

`make db` resets local development data and never replaces a migration. For
enum/constraint changes, verify dev-server startup because some parser failures
appear only there. IHP `RunDevServer` alone owns live schema-derived
`build/Generated/` regeneration.

## Authority And Queries

Apply the root venue/support authority model. Validate venue scope before using
request-derived IDs; global user identity never substitutes for membership in
an Application query.

Use IHP QueryBuilder for application queries. Isolate only an unavoidable,
minimal locking/serialization primitive in a focused mutation module; keep
business reads/writes in QueryBuilder and advisory-lock keys bounded and
normalized.

Payroll-adjacent data must preserve provenance. Audit event names/source
channels are the closed typed contract in
`Application.Helper.Audit.Vocabulary`; effect helpers emit typed facts and only
boundary renderers produce persisted/telemetry text.

## Fixtures And Module Ownership

`Application.Fixture.Reset` is the closed application-table reset manifest; do
not discover tables dynamically or duplicate reset SQL. Keep founder bootstrap
fixtures deterministic and venue-membership-authorized. Run
`fixture-reset-manifest-test` after schema/reset changes.

Use focused modules; top-level `Application/Helper/View.hs` and
`Application/Helper/Export.hs` remain compatibility re-export facades. Follow
nearby README/SPEC/AGENTS files, especially:

- `Application/Helper/Controller/AGENTS.md`
- `Application/Helper/View/AGENTS.md`
- `Application/Helper/Export/README.md`
- `Application/Xero/README.md`
- `Application/Helper/LiveUpdate.SPEC.md`

## Verification

After code changes, run focused Hspec and `bash ./bin/in-env typecheck`. Schema
changes also require `regen-types`, migration/schema checks,
`fixture-reset-manifest-test` when applicable, and local dev DB/startup
verification.
