# Date-native Roster compatibility retirement (#374)

This runbook governs migrations `1788100000.sql` and `1788100100.sql`. The
first permanently removes the legacy roster-week/offset rollback substrate
after production observation; the second replaces two retained integrity
trigger functions whose predecessor bodies referenced the retired columns. The
operator's explicit approval of #374 authorizes repository implementation only;
production deployment still requires the named deployment approval below.

## Destructive scope

The migration drops `roster_weeks`, `roster_week_slot_definitions`,
`venue_config.week_offset_epoch`, `roster_days.roster_week_id/day_offset`, legacy
lane/slot definition references, notification week ID/offset columns, and their
triggers, functions, constraints and indexes. These are redundant identities,
not current business authority.

It retains all Operational-date roster days, date-local lanes, roster slots,
publication state, notification windows and immutable JSON snapshots, Timesheet
entries and versions, exports, payroll ledgers, audit records and Xero evidence.
Historical migration files remain immutable.

## Required approval and evidence

Before deployment, record privately:

1. Exact candidate commit and production database identity.
2. Successful #373 observation evidence covering at least one complete
   seven-Operational-day window and one payroll/Xero cycle. Retain the bounded
   zero-violation `date-native-roster-readiness reconcile` capture and compare
   its aggregate counts with the approved preflight capture.
3. Legacy-link ingress evidence for the same observation period: review bounded
   application/request telemetry for offset-only Roster and Timesheet links and
   any compatibility redirects. Approval requires zero accepted offset-only
   requests and zero compatibility redirects for the full period; retain only
   sanitized counts, route classes, timestamps, and candidate commit privately.
   Any hit is blocking until its source is reconciled and a new full observation
   period completes.
4. A current encrypted PostgreSQL custom-format backup, SHA-256 digest,
   PostgreSQL version, timestamps and successful command status.
5. A restore rehearsal of that exact archive into an isolated database using
   the production PostgreSQL major version. `pg_restore --list` and restore must
   complete with `--exit-on-error`.
6. Read-only acceptance of one historical Draft and Published roster window,
   one Timesheet window, one approved payroll/export record and one retained
   roster-notification snapshot in the restored database.
7. Named approval: `issue-374-production-retirement-approved`.

Do not proceed if the backup omits the migration ledger, the restore requires
manual row edits, observation found unresolved date-native contradictions, or a
predecessor application rollback remains necessary.

## Production-copy rehearsal

1. Restore the approved backup into isolated staging.
2. Stop application writers and queue consumers for that copy.
3. Deploy the candidate package and run the normal migration runner once so it
   applies `1788100000.sql` followed by `1788100100.sql`. The retirement
   migration aborts transactionally if date-native day scope, lane/slot identity
   or notification windows contradict the retained schema. The repair migration
   must then replace the retained day/slot integrity function bodies before any
   application writes resume.
4. Verify the retired objects are absent:

   ```sql
   SELECT to_regclass('public.roster_weeks'),
          to_regclass('public.roster_week_slot_definitions');

   SELECT table_name, column_name
   FROM information_schema.columns
   WHERE (table_name = 'venue_config' AND column_name = 'week_offset_epoch')
      OR (table_name = 'roster_days' AND column_name IN ('roster_week_id', 'day_offset'))
      OR (table_name = 'roster_lanes' AND column_name = 'legacy_roster_week_slot_definition_id')
      OR (table_name = 'roster_slots' AND column_name = 'roster_week_slot_definition_id')
      OR (table_name = 'roster_notification_runs' AND column_name IN ('roster_week_id', 'week_offset'));
   ```

   Both relation values and the column query must be empty/null.
5. Execute harmless updates against representative `roster_days` and
   `roster_slots` rows and confirm both retained integrity triggers complete
   without referring to removed fields.
6. Run authentication and the acceptance matrix from the required evidence,
   plus roster creation, lane add/remove, Draft/Published transitions,
   notification delivery and a venue start-day change/reversal on disposable
   staging data.
7. Run the repository's full verification against the candidate.

## Production deployment

1. Enter the approved maintenance window. Pause web writes and queue consumers.
2. Take the final approved backup and record its digest.
3. Confirm the exact candidate commit and named approval.
4. Run the normal transactional migration runner once, applying both retirement
   migrations in order. Do not manually mark either migration applied or retry
   against a modified database.
5. Deploy the candidate application, then resume app and worker processes.
6. Run the bounded absence queries above and smoke-test Draft/Published roster,
   Timesheets, roster notification history, payroll/export and Xero readiness.
7. Preserve migration output and sanitized aggregate evidence privately.

## Failure and recovery

### Migration failure

Keep writes paused. Preserve the complete error and confirm PostgreSQL rolled
back both DDL and the migration ledger entry. Restart the predecessor package
only after verifying all compatibility objects remain. Restore from backup only
if independent evidence shows transactional rollback failed.

### Failure after successful retirement

There is no in-place SQL rollback: IHP migrations are forward-only and the
predecessor package requires the retired generated schema. Pause writes and
workers, capture a new incident backup, and restore the approved pre-retirement
archive into an isolated replacement database. Account explicitly for any writes
accepted after retirement before switching service; never overwrite the active
database or bulk-reconstruct offsets. Prepare a reviewed forward repair when
post-migration customer writes must be preserved.

Do not recreate legacy tables, offsets or compatibility triggers as an ad-hoc
recovery mechanism.
