# Migration Rehearsal Fixtures

`migration-rehearsal --from-ref <commit>` always verifies that every candidate
migration revision is recorded and that the upgraded schema converges with a
fresh candidate database.

## Schema convergence policy

The harness builds the comparison database from the candidate-pinned IHP
`IHPSchema.sql` and candidate `Application/Schema.sql`. Both schemas are dumped
with the pinned PostgreSQL `pg_dump` using schema-only, no-owner, and
no-privilege output. `schema_migrations` is excluded because it is upgrade-path
bookkeeping, not application schema. Generated dump-version headers and
PostgreSQL's random `\restrict`/`\unrestrict` tokens are normalized; application
objects, constraints, indexes, functions, triggers, publications, and comments
remain comparison authority. Failure output contains at most 64 KiB of schema
diff and must never contain table rows.

## Focused data assertions

A pending revision may own this pair:

```text
Application/Migration/Rehearsal/<revision>/predecessor.sql
Application/Migration/Rehearsal/<revision>/assert.sql
```

The harness rejects an incomplete pair. It executes `predecessor.sql` against
the reconstructed predecessor database before the pinned IHP runner, then
executes `assert.sql` after migration and revision verification. Both files run
through PostgreSQL with `ON_ERROR_STOP`; assertions should use `DO` blocks and
raise a stable, descriptive exception naming the failed invariant without
including customer row values. Fixture standard output and raw PostgreSQL error
text are suppressed; failure evidence names the assertion file only. Runner
failure evidence is reduced to revision, exit status, and SQLSTATE so notices or
constraint details cannot disclose row values.

This pair is mandatory when a migration transforms existing customer rows. The
predecessor fixture must be minimal and synthetic while covering preservation,
backfill, and exceptional values relevant to that revision. Purely structural
migrations need no bespoke fixture. Revision `1784761930` is the retained billing
example; `billing-migration-check` invokes the shared harness from that
revision's exact Git predecessor. These runtime SQL checks—not source-text
inspection—are migration data authority.
