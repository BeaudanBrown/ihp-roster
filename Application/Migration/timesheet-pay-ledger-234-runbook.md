# Immutable timesheet pay ledger cutover (#234)

1. Take and verify a database backup.
2. Apply `1785240000.sql`. This is additive; existing approval metadata is unchanged. Existing approved rows alone receive `legacy_pay_backfill_pending = TRUE`; new approvals cannot use that migration-only exemption.
3. Deploy code containing the frozen `hospitality-award-v1` engine and the backfill script.
4. Run:

   ```bash
   bash ./bin/in-env run-script BackfillTimesheetPayLedger
   ```

   The script bulk-loads and locks all approved entries lacking an active calculation, writes the complete batch in one transaction, and clears each migration-only exemption. Any missing effective rate, imported-item, or holiday fact rolls back the batch and reports the blocking entry IDs. Correct source data, then rerun; successful reruns are idempotent.
5. Verify no approved, non-deleted entry lacks `active_pay_calculation_id`, and verify every active calculation has earnings components and its ordered paid-time rows.
6. Only then activate issue #239's consumer cutover.

Rollback before consumer cutover: revert application code. The additive ledger tables and nullable pointers may remain. Do not delete immutable history. After consumer cutover, restore the backup or deploy a separately reviewed compatibility change; never silently clear approval state.
