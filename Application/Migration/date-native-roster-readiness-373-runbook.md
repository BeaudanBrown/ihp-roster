# Date-native Roster rollout, reconciliation, and recovery (#373)

This runbook governs deployment of the additive date-native Roster migrations
through `1787006000.sql`. It does not authorize deletion of legacy
`roster_weeks`, offset fields, weekly definitions, or compatibility provenance.
Those remain the application rollback substrate until #374 receives separate
approval after production observation.

## Safety boundaries

- Obtain separate named approvals for production backup/restore rehearsal and
  production deployment. A successful repository verification run is not
  deployment approval.
- Pause application writes while the production migration runner is active.
  Stop retired automatic Roster-to-Timesheet workers before migration and do not
  restart them.
- Never rerun a tracked migration that the migration ledger records as applied.
  Never repair a failed diagnostic by deleting, moving, republishing, or
  rewriting customer rows without a separately reviewed recovery plan.
- Evidence directories contain customer database identifiers and bounded row
  UUIDs. Store them outside the checkout on an operator-approved encrypted
  volume with mode `0700`; do not attach them to a public issue.
- Offset-based Roster and Timesheet URLs remain intentionally unsupported under
  the accepted runtime contract. Do not add an offset redirect as rollback
  behavior. Canonical links carry an ISO `anchorDate`.

## Backup and restore rehearsal

1. Record the candidate commit and the exact production database identity.
2. In a quiet window, create a complete PostgreSQL custom-format backup with
   schema, data, large objects, migration ledger, and privileges needed by the
   recovery environment. Encrypt it before it leaves the database host. Record
   its SHA-256 digest, PostgreSQL version, start/end timestamps, and backup tool
   exit status without recording connection credentials.
3. Restore that exact archive into an isolated database using the production
   PostgreSQL major version. Run `pg_restore --list`, restore with
   `--exit-on-error`, and record the restore log and resulting database size.
4. Start the currently deployed compatibility application build against the
   restore. Confirm authentication plus one historical Draft and Published
   Roster window, one Timesheet window, one approved payroll export, and one
   retained notification run. Destroy the isolated restore only after the
   evidence is reviewed.
5. Do not proceed if the restore was partial, required manual row edits, or did
   not include the migration ledger.

## Staging production-copy preflight

1. Restore a recent production backup into staging and apply the normal ordered
   migration runner through:

   - `1787001000.sql` — dated Roster days and lanes;
   - `1787002000.sql` — date-local lane mutation integrity;
   - `1787003000.sql` — per-day publication authority;
   - `1787004000.sql` — date-native templates and notifications;
   - `1787005000.sql` — explicit Timesheet Operational dates;
   - `1787006000.sql` — immutable Operational payroll/Xero facts.

   Migration failures are blocking evidence. Preserve the unchanged restored
   source and complete migration log; do not weaken checks.
2. From the exact candidate checkout, capture read-only evidence:

   ```bash
   export PGHOST='/approved/staging-postgresql/socket-or-host'
   export PGPORT='5432'
   export PGUSER='read_only_audit_role'
   export PGPASSFILE='/secure/protected-pgpass'
   export DATE_NATIVE_ROSTER_READINESS_APPROVAL=read-only-issue-373
   export DATE_NATIVE_ROSTER_READINESS_OPERATOR='reviewed operator name'
   export DATE_NATIVE_ROSTER_READINESS_EXPECTED_DATABASE='restored_database_name'
   bash ./bin/in-env ./bin/date-native-roster-readiness \
     preflight /secure/date-native-preflight-YYYYMMDDTHHMMSSZ
   ```

3. Verify `manifest.sha256`, confirm `capture-metadata.txt` names the expected
   commit/database/phase, and review `audit.json`. `totalViolationCount` must be
   zero. Every failed check is blocking; the 25 UUID sample is diagnostic only,
   not a complete repair set.
4. Review informational counts rather than requiring them to be zero:
   `sparseRosterWindows`, `roughLaneUnionWindows`,
   `historicalAdHocLocalDateDifferences`,
   `legacyApprovedEntriesPendingPayBackfill`, `legacyLedgerComponents`, and
   `activeNotificationRuns` describe supported retained history.
5. Run the source authority gate and complete candidate verification:

   ```bash
   bash ./bin/in-env ./bin/date-native-roster-migration-check
   bash ./bin/in-env hspec-test
   bash ./bin/in-env frontend-check
   bash ./bin/in-env e2e
   bash ./bin/in-env verify-fast
   bash ./bin/in-env verify-full
   ```

6. Exercise the acceptance matrix on staging without editing imported history:

   - inspect all Roster groups and sparse historical windows;
   - preview Monday-to-non-Monday and reversal changes using mixed Draft and
     Published days, then confirm only in disposable staging data;
   - verify mixed windows become Draft, wholly Published windows remain
     Published, and reversal never restores publication;
   - inspect date-local lane unions and active notification delivery from its
     immutable snapshot;
   - submit a stale browser confirmation and verify rejection/refresh;
   - trace a whole cross-midnight shift, including spring and autumn DST cases,
     through Roster ownership, Timesheet Operational date, approval, Staff
     Hours, Payroll Earnings, Xero preview/submission, and actual-date holiday
     components. The shift remains in one Operational day while component dates
     retain their actual local dates;
   - request canonical anchor-date links and verify offset-only Roster and
     Timesheet links are unsupported rather than interpreted as authority.

## Production deployment

1. Confirm reviewed backup/restore, preflight evidence, verification logs,
   maintenance window, rollback build, and responsible operators in the private
   deployment record.
2. Pause writes and queue consumers. Take the approved final backup and record
   its digest. Run the normal transactional migration runner once. If it fails,
   retain the transaction rollback and follow **Migration failure** below.
3. Deploy the exact candidate application generated from the additive schema.
   Resume queue consumers, excluding retired automatic Roster-to-Timesheet
   workers, then restore writes.
4. Immediately capture reconciliation evidence with protected non-URL libpq
   settings, the production database identity, and a new empty secure directory:

   ```bash
   export PGHOST='/approved/postgresql/socket-or-host'
   export PGPORT='5432'
   export PGUSER='read_only_audit_role'
   export PGPASSFILE='/secure/protected-pgpass'
   export DATE_NATIVE_ROSTER_READINESS_APPROVAL=read-only-issue-373
   export DATE_NATIVE_ROSTER_READINESS_OPERATOR='reviewed operator name'
   export DATE_NATIVE_ROSTER_READINESS_EXPECTED_DATABASE='production_database_name'
   bash ./bin/in-env ./bin/date-native-roster-readiness \
     reconcile /secure/date-native-reconcile-YYYYMMDDTHHMMSSZ
   ```

5. Require zero violations and compare aggregate counts with staging and the
   pre-deployment record. Explain expected differences caused by writes between
   captures; do not compare UUID samples as a row inventory.
6. Smoke-test a Draft and Published Roster window, Timesheets, Staff Hours,
   Payroll Earnings, and Xero readiness without approving, publishing, or
   changing customer data solely for the test.

## Observation before #374

Observe at least one complete seven-Operational-day window after deployment and
one normal payroll/Xero cycle. Capture read-only reconciliation at deployment,
after the first complete window, and after the payroll cycle. Require zero
violations each time and review application errors for stale-calendar conflicts,
route parameter failures, publication normalization, notification delivery,
payroll reconciliation, and Xero submission failures.

A customer-requested Roster start-day change may provide additional evidence,
but operators must not change a customer setting solely to test deployment. If
a change occurs, record before/after counts and verify that reversal does not
restore publication. #374 remains blocked until the observation evidence and
rollback viability receive separate operator approval.

## Recovery

### Migration failure

Keep writes paused, preserve the complete runner error, and verify that the
transaction and migration ledger rolled back. Restart the predecessor
application against the unchanged schema only after that verification. Restore
from backup only if independent evidence shows transactional rollback failed.

### Application rollback after successful migration

Do not reverse migrations, drop additive objects, rewrite Operational dates, or
restore the pre-deployment backup over newer customer writes. Deploy the
prebuilt compatibility application that is generated from the additive schema
and retains legacy week provenance. Keep new tables/columns intact, stop new
start-day changes, and rerun the read-only reconciliation to preserve the fault
state. Immutable notification and approved payroll snapshots continue from
sealed facts.

### Data contradiction after writes resume

Pause affected writes and queue consumers. Capture reconciliation evidence and
a new full backup. Do not infer repairs from missing current mappings or mutable
venue settings. Prepare a row-specific forward repair and recovery validation
for separate approval. If service can remain available, prefer the additive
compatibility rollback above; restoring an old backup is a last-resort incident recovery
because it would discard post-backup customer writes.

A Roster start-day reversal is an ordinary confirmed product mutation, not
schema rollback. It advances the calendar revision and cannot republish days
that were conservatively returned to Draft.
