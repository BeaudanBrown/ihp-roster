# Haskell wage authority cutover (#239)

This is a forward-only production cutover. There is no repository-managed restoration
of the retired SQL calculators.

## Pre-deployment

1. Back up the production database and record the restore point under normal operator
   procedures.
2. Deploy/apply all migrations through `1785241000.sql`.
3. Run readiness/source checks required by the wage compliance workstream.
4. Execute the atomic historical backfill:

   ```bash
   bash ./bin/in-env run-script BackfillTimesheetPayLedger
   ```

   Stop if it reports any entry IDs. Correct missing effective rate/holiday facts and
   rerun the complete transaction; do not partially mark entries complete.
5. Verify no active approved entry lacks a sealed calculation:

   ```sql
   SELECT te.id
   FROM timesheet_entries te
   LEFT JOIN timesheet_pay_calculations c
     ON c.id = te.active_pay_calculation_id
   WHERE te.is_approved = TRUE
     AND te.deleted_at IS NULL
     AND (c.id IS NULL OR c.sealed_at IS NULL);
   ```

   Expected result: zero rows. Confirm approval timestamps, approver IDs, staff pay
   versions, and shift-type pay versions remain populated.

## Operator approval gate

After pre-deployment evidence is complete, record the named operator, timestamp,
database restore point, zero-row readiness result, and explicit approval to perform the
forward-only function retirement in the deployment record. Do not deploy the cutover
application or apply `1785242000.sql` without that approval.

## Cutover

1. Deploy the operator-approved application version whose draft paths use
   `Application.WageEngine` and whose final paths use the approved ledger.
2. Apply `1785242000.sql`. Its guard aborts and reports approved entry IDs when backfill
   is incomplete; otherwise it drops both legacy SQL functions.
3. Restart/wait for the application and run normal health checks.

## Post-deployment

- Verify `to_regprocedure('calculate_timesheet_pay(uuid)')` and
  `to_regprocedure('calculate_timesheet_pay_range(uuid,date,date)')` are both `NULL`.
- Exercise one draft preview and one approved payroll output through authorized test
  data.
- Verify approved calculations remain sealed and approval metadata unchanged.
- Run the repository search/check gates recorded by #239.

Recovery from an operator/deployment failure uses the pre-cutover database restore
point and normal deployment rollback procedures. Do not recreate legacy calculator DDL
from this repository.
