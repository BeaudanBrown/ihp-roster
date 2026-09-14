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

4. Confirm every legacy template table is empty with the same precondition enforced transactionally by the migration. Any non-zero count is a hard stop; do not delete rows or bypass the migration preflight.

   ```sql
   SELECT 'roster_templates' AS relation, COUNT(*) FROM roster_templates
   UNION ALL SELECT 'roster_template_designs', COUNT(*) FROM roster_template_designs
   UNION ALL SELECT 'roster_template_days', COUNT(*) FROM roster_template_days
   UNION ALL SELECT 'roster_template_columns', COUNT(*) FROM roster_template_columns
   UNION ALL SELECT 'roster_template_shifts', COUNT(*) FROM roster_template_shifts
   ORDER BY relation;
   ```

5. Record representative Roster and Timesheet row counts and immutable identifiers for post-migration comparison. Store the query text and result beside the approval record so the same bounded queries can be repeated after migration; do not retain customer data in the issue.

## Apply and verify

1. Run the normal IHP migration runner. The migration is transactional and aborts before destructive DDL if any legacy template row exists.
2. Confirm `roster_template_designs` is absent.
3. Confirm `roster_template_days`, `roster_template_columns`, and `roster_template_shifts` each contain `roster_template_id` and reference `roster_templates`.
4. Repeat the recorded Roster and Timesheet queries. Counts and representative immutable identifiers must exactly match the preflight evidence.
5. Run schema parsing and generated-type freshness checks, start the application against the migrated schema, and perform an authorized roster-group-scoped template-library read. Record only pass/fail, application revision, and the scoped request identity; do not copy customer rows into the approval record.

## Failure and recovery

- Before commit: allow the migration transaction to roll back, investigate, and leave writes stopped.
- After commit but before application release: restore the verified full database snapshot. Do not reconstruct legacy template tables manually.
- If unrelated Roster or Timesheet verification differs: stop immediately, keep writes disabled, restore the full snapshot, and escalate with the before/after evidence.
- The template-only dump is evidence and an additional recovery aid; because the approved precondition is zero template rows, it must contain no customer rows. A non-empty dump invalidates approval and blocks deployment.
