# Haskell wage authority cutover (#239)

This is a forward-only production cutover. There is no repository-managed restoration
of the retired SQL calculators.

## Pre-deployment

1. Back up the target database and record the restore point under normal operator
   procedures.
2. Run the wage-source readiness checks required by the compliance workstream.
3. Confirm approved entries retain complete approval metadata:

   ```sql
   SELECT id
   FROM timesheet_entries
   WHERE is_approved = TRUE
     AND deleted_at IS NULL
     AND (
       approved_at IS NULL
       OR approved_by_user_id IS NULL
       OR staff_pay_version_id IS NULL
       OR shift_type_pay_version_id IS NULL
     );
   ```

   Expected result: zero rows.

## Operator approval gate

Record the named operator, timestamp, database restore point, readiness result, and
explicit approval to perform the forward-only function retirement in the deployment
record. Do not rebuild/switch the cutover configuration without that approval.

## Automatic rebuild sequence

For deployments with `services.ihpRoster.enableMigrations = true`, one rebuild performs
the cutover in this order:

1. `migrate.service` applies the additive ledger migrations and the `1785242000.sql`
   deployment marker.
2. `wage-cutover.service` runs the packaged `BackfillTimesheetPayLedger` executable.
   The Haskell backfill locks and processes every eligible approved entry in one
   transaction. Historical reconstruction ignores source age but requires complete
   effective rates and statewide holiday facts. Any entry failure reports its ID and
   rolls back the complete backfill.
3. The same service executes
   `Application/Deployment/retire-legacy-wage-calculators.sql`. Its guard verifies
   sealed child facts, contiguous ordinals, approval metadata, and pinned pay versions,
   then drops both legacy SQL calculators.
4. Only after that service succeeds may the app, worker, bootstrap, and scheduled
   application services start.

A failed backfill or retirement guard fails the rebuild before application startup. Fix
missing source facts and restart `wage-cutover.service` or repeat the rebuild; do not
manually unapprove entries or assign calculation IDs.

## Post-deployment

Verify no active approved entry lacks a sealed calculation:

```sql
SELECT te.id
FROM timesheet_entries te
LEFT JOIN timesheet_pay_calculations calculation
  ON calculation.id = te.active_pay_calculation_id
WHERE te.is_approved = TRUE
  AND te.deleted_at IS NULL
  AND (calculation.id IS NULL OR calculation.sealed_at IS NULL);
```

Expected result: zero rows. Also:

- Verify `to_regprocedure('calculate_timesheet_pay(uuid)')` and
  `to_regprocedure('calculate_timesheet_pay_range(uuid,date,date)')` are both `NULL`.
- Exercise one draft preview and one approved payroll output through authorized test
  data.
- Verify approval timestamps, approver IDs, and pinned pay versions are unchanged.
- Run the repository search/check gates recorded by #239.

Recovery from an operator/deployment failure uses the pre-cutover database restore
point and normal deployment rollback procedures. Do not recreate legacy calculator DDL
from this repository.
