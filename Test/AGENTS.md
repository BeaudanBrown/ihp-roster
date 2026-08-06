# Hspec Agent Guide

Read the IHP testing guide referenced by root `AGENTS.md`.

## Commands And Gate Semantics

```bash
bash ./bin/in-env hspec-pure
bash ./bin/in-env hspec-db
bash ./bin/in-env hspec-test
bash ./bin/in-env hspec-test --match "SuiteLabel"
bash ./bin/in-env hspec-coverage
bash ./bin/in-env hspec-pure --suite-metadata
```

`hspec-test` is the complete canonical gate and auto-shards full runs. Pure, DB,
feedback-lane, focused, skipped, and rerun selections are additive diagnostics,
never complete evidence. Repeated `--match` values are OR filters; combine them
in one command. Run compiler/test commands serially because normal checks share
a fingerprinted verification cache. Coverage remains isolated.

Use `TEST_SHARDS=N` only for measured diagnostics; focused and pure runs default
to serial. Use `TEST_KEEP_DATABASES=1` for DB diagnosis and inspect
`.devenv/test/latest/` or `test-postgres status`. External PostgreSQL requires
both explicit external mode and socket; managed commands must never target a
development/production server.

## Suite Registration And Seams

Register every spec in `Test/Suite.hs` as pure or database-backed with explicit
cleanup, committed-visibility, feedback, invariant, fixture-cost, external-mock,
and runtime metadata. A pure suite must work without PostgreSQL or an IHP model
context. Run suite-metadata validation plus the focused suite after registration.
Do not reintroduce a linear suite list or tune shard balance by source order.

Test the narrowest authoritative seam: pure domain decisions in pure tests;
persistence and constraints in DB tests; controller tests for parsing, auth,
venue scope, response wiring, and orchestration; Playwright only for browser
behavior. Keep byte-level export/generator authority in goldens and schema/
migration/deployment protections at their real boundaries. Source-text checks
are only for narrow ownership or retired-vocabulary guards.

## Database Context And Isolation

Use `aroundAll withDatabaseTestContext` for DB suites. Do not use `beforeAll`,
unbracketed contexts, or deprecated `mockContextNoDatabase`; they leak real
model pools/listeners. Use `withCleanDb` within examples. It delegates to the
closed `Application.Fixture.Reset` manifest; never duplicate reset SQL or weaken
cleanup to preserve manual/bootstrap data.

Each shard owns an isolated disposable database, and examples must not depend on
other examples/files/shards. Keep fixtures deterministic with fixed IDs and
clocks. Use shared builders from `Test/Support.hs` and `Application.Fixture`
rather than inline setup or per-user password hashing.

For request boundaries, cover missing required values, malformed typed values,
oversized/blank text, suspicious payloads, and well-formed cross-venue/group
IDs. Parsing and authorization are separate assertions; failures must be
controlled, never 500s. Export tests retain formula-neutralization and CSV
quoting cases; URL helpers retain encoding edge cases.

Approved timesheet fixtures must use approval builders that populate all sealed
facts. Leave request `end_date` is exclusive. Fixed payroll output belongs in
`FixedExportGoldenSpec` with committed fixtures, exact CSV/ZIP comparisons, and
repeat determinism.

## Verification

Run the focused suite while iterating, then `bash ./bin/in-env hspec-test` once
for changed Haskell behavior. Use `hspec-coverage` when adding or materially
changing coverage; inspect outputs under `output/coverage/hspec/latest/`. Schema
or fixture-reset work also requires `regen-types`, typecheck, and
`fixture-reset-manifest-test`.
