# Legacy Schema Retirement #151 Operator Runbook

## Approval Boundary

On 2026-07-12, the operator approved **Stage A read-only inventory and verified
export only** for:

- `report_definitions`
- `report_definition_shift_type_filters`
- `xero_payroll_calendar_selections`

This approval does not authorize a production `DROP TABLE`, schema migration, or
row mutation. Stage B requires a separate recorded approval after the evidence
and restore rehearsal below are reviewed.

The retained system includes fixed `export_jobs` exports and all active Xero
connection, payroll-calendar reference, mapping, preparation, submission, sync,
and audit data.

## Preconditions

The named operator must confirm all of the following before production capture:

1. The deployed application release no longer reads or writes the three reviewed
   tables. GitHub #140 retired configurable reports and #142 retired the old Xero
   calendar-selection workflow.
2. The normal full-database backup is healthy and identifies a restorable
   baseline. The table-specific export produced here supplements rather than
   replaces that backup.
3. The evidence directory is outside the repository on an access-controlled,
   encrypted volume, or an `age` recipient is available.
4. The expected production database name and connection path are known. Do not
   guess a host or database name from the repository's example NixOS config.
5. A quiet capture window is available. The command uses short lock and statement
   timeouts and fails if the reviewed tables change during capture.

## Read-Only Capture

Run from the deployed repository checkout. Prefer an `age` recipient:

```bash
nix shell nixpkgs#age -c env \
  LEGACY_SCHEMA_REVIEW_APPROVAL=read-only-stage-a \
  LEGACY_SCHEMA_REVIEW_OPERATOR='<named operator>' \
  LEGACY_SCHEMA_REVIEW_EXPECTED_DATABASE='<production database name>' \
  LEGACY_SCHEMA_REVIEW_AGE_RECIPIENT='<age public recipient>' \
  LEGACY_SCHEMA_REVIEW_DATABASE_URL='<production connection URL, if required>' \
  bash ./bin/in-env ./bin/legacy-schema-retirement-review \
  /secure/bepis/issue-151/<capture timestamp>
```

On a host where standard libpq variables or peer authentication already select
production, omit `LEGACY_SCHEMA_REVIEW_DATABASE_URL`. Never put a connection URL
or customer-data artifact in Git, shell history, issue comments, or chat.

If the destination itself is an operator-confirmed encrypted volume and `age` is
not used, replace the recipient variable with:

```bash
LEGACY_SCHEMA_REVIEW_PLAINTEXT_APPROVED=encrypted-volume
```

The command forces every PostgreSQL connection to `transaction_read_only=on`.
It refuses system databases, a database-name mismatch, a non-empty output
directory, output inside the Git checkout, missing tables, an unstable
before/after fingerprint, or an unprotected data archive.

## Artifacts

| Artifact | Purpose |
| --- | --- |
| `inventory.json` | Aggregate counts by venue/status/engine, retained-Xero matches, integrity anomalies, and content fingerprints. It excludes report names, descriptions, slugs, and calendar names. |
| `fingerprints-before.csv` / `fingerprints-after.csv` | Exact row-count/content stability evidence around the dump. They must be identical. |
| `table-data.dump.age` or `table-data.dump` | Complete data-only custom archive for the three tables. The plaintext form is allowed only on the approved encrypted volume. |
| `table-data.dump.plaintext.sha256` | Checksum to verify the decrypted archive before restore. |
| `table-data.archive-list.txt` | `pg_restore --list` output proving all three table-data entries exist. |
| `public-schema.sql` | Schema-only reference for rollback authoring. Do not apply this whole file to production. |
| `capture-metadata.txt` | Named operator, timestamp, database identity, server version, approval scope, and protection mode. |
| `manifest.sha256` | Integrity manifest for every captured artifact. |

Verify the artifact set immediately:

```bash
cd /secure/bepis/issue-151/<capture timestamp>
sha256sum --check manifest.sha256
```

Record only aggregate counts, checksum values, secure-location identifier, and
operator identity in GitHub #151. Do not paste customer rows or the archive.

## Evidence Review And Data Disposition

Before requesting Stage B approval, review:

- all five `integrityAnomalies` values are zero;
- before/after fingerprints are identical;
- report-definition counts by venue, engine, active state, and archive state;
- report-filter counts by venue and deleted state;
- each Xero selection group's `rows_with_calendar_id`,
  `rows_matching_retained_calendar`, and `rows_matching_retained_pay_run`;
- archive and manifest checksums;
- the normal full-backup identifier and its successful restore evidence.

Non-empty tables do not automatically authorize deletion. Assign an explicit
disposition to every category:

- preserve only in the secured retirement archive;
- migrate a still-required fact into a retained model through a separately
  reviewed additive migration; or
- stop retirement because the data is still operationally required.

An unmatched Xero selection or active report definition requires explicit human
review. Do not infer business meaning from names or silently translate it.

## Restore Rehearsal

Use an isolated database restored from the normal full production backup. Never
perform this rehearsal against production.

1. Record the clone's fingerprints with
   `scripts/operations/legacy-schema-retirement-151-fingerprints.sql`.
2. Apply the proposed Stage B drop migration to the clone only.
3. Apply the separately reviewed rollback DDL that recreates the parent tables,
   child table, indexes, constraints, and table-specific triggers/functions.
   Do not apply all of `public-schema.sql`.
4. Decrypt and verify the table archive when applicable:

   ```bash
   age --decrypt --identity '<operator identity file>' \
     --output table-data.dump table-data.dump.age
   sha256sum --check table-data.dump.plaintext.sha256
   ```

5. Restore the data into the clone:

   ```bash
   pg_restore --exit-on-error --single-transaction --disable-triggers \
     --data-only --dbname='<isolated clone URL>' table-data.dump
   ```

   Use a privileged restore role on the isolated clone because
   `--disable-triggers` is required: PostgreSQL custom-archive restore clears the
   session search path, while the existing report-filter integrity trigger calls
   an unqualified parent table. The reviewed rollback path must restore all
   three tables before re-enabling constraints/triggers and validating them.
6. Re-run the fingerprint and inventory SQL. Counts and content fingerprints
   must exactly match the capture evidence, every integrity-anomaly count must
   be zero, and application/schema startup checks must pass.
7. Delete rehearsal plaintext according to the approved retention procedure.

## Stage B Migration Constraints

The future destructive migration must be a new, separately reviewed change. It
must:

- drop `report_definition_shift_type_filters` before `report_definitions`;
- avoid `CASCADE` so unexpected dependencies stop the migration;
- remove the report-filter-specific
  `enforce_report_definition_filter_venue_integrity()` function;
- remove table-owned indexes and triggers;
- retain shared `prevent_hard_delete()` and
  `enforce_xero_connection_venue_integrity()` functions because retained tables
  still use them;
- preserve `export_jobs`, fixed exports, `xero_payroll_calendars`, mappings,
  preparation/submission records, sync rows, and audit rows;
- update `Application/Schema.sql`, add an IHP migration, regenerate types, and
  pass schema/parser/startup verification.

## Separate Stage B Approval Record

Stage B remains **not approved** until GitHub #151 records:

- aggregate production counts and explicit data disposition;
- secure archive location identifier and checksums;
- normal full-backup identifier;
- successful isolated restore-rehearsal evidence;
- reviewed forward and rollback SQL;
- named operator and deployment window; and
- an explicit statement authorizing the destructive production migration.
