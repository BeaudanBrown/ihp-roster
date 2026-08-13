# Roster template snapshot cutover (#397)

Migration `1789000000.sql` retires the unused roster-template draft/version tables and creates direct snapshot tables. GitHub issue #397 is the change record: its operator-approved scope confirms there is no customer template data and requires old drafts and versions not to be migrated. This approval does not permit changes to Roster, Roster Week, Roster Slot, Timesheet, or other customer data.

## Approval boundary

Deployment requires the operator to record approval against GitHub issue #397 after reviewing the preflight counts, verified backup reference, and representative Roster/Timesheet evidence. A merged migration, this runbook, or the implementation issue's closure is not deployment approval. Record the approver, timestamp, backup reference, zero-count query results, and maintenance window before running the migration.

## Before deployment

1. Stop application writes for the migration window.
2. Take and verify a restorable database snapshot using the normal production backup procedure.
3. Export schema and template tables separately for recovery evidence:

   ```bash
   pg_dump "$DATABASE_URL" --schema-only > roster-template-397-schema.sql
   pg_dump "$DATABASE_URL" --data-only \
     --table=roster_templates \
     --table=roster_template_designs \
     --table=roster_template_days \
     --table=roster_template_columns \
     --table=roster_template_shifts \
     > roster-template-397-data.sql
   ```

4. Confirm every legacy template table is empty. Any non-zero count is a hard stop; do not delete rows or bypass the migration preflight.
5. Record representative Roster and Timesheet row counts and immutable identifiers for post-migration comparison.

## Apply and verify

1. Run the normal IHP migration runner. The migration is transactional and aborts before destructive DDL if any legacy template row exists.
2. Confirm `roster_template_designs` is absent.
3. Confirm `roster_template_days`, `roster_template_columns`, and `roster_template_shifts` each contain `roster_template_id` and reference `roster_templates`.
4. Confirm the recorded Roster and Timesheet counts and representative identifiers are unchanged.
5. Start the application and verify schema parsing/type generation and a scoped template-library read.

## Failure and recovery

- Before commit: allow the migration transaction to roll back, investigate, and leave writes stopped.
- After commit but before application release: restore the verified full database snapshot. Do not reconstruct legacy template tables manually.
- If unrelated Roster or Timesheet verification differs: stop immediately, keep writes disabled, restore the full snapshot, and escalate with the before/after evidence.
- The template-only dump is evidence and an additional recovery aid; because the approved precondition is zero template rows, it must contain no customer rows. A non-empty dump invalidates approval and blocks deployment.
