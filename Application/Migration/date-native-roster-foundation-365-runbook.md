# Date-native roster foundation deployment and recovery (#365)

This rollout is additive. Legacy `roster_weeks`, `week_offset`, `day_offset`,
`roster_week_slot_definitions`, and slot references remain authoritative and are
not removed. Compatibility triggers project legacy writes into dated days and
lanes until #366 performs the mutation cutover. The IHP migration file is a
one-time, revision-tracked DDL unit; its day/lane/slot data backfill is
idempotent and deterministic (`ON CONFLICT` plus derived IDs), but operators must
never replay the complete tracked DDL file after success.

## Before deployment

1. Take and verify a restorable PostgreSQL backup.
2. Restore a recent production copy into staging.
3. Run `Application/Migration/1787001000.sql` there. Treat any `date-native
   roster preflight blocked` error as customer-data evidence to investigate;
   do not weaken a check or repair rows implicitly.
4. Record counts for roster days, weekly definitions, retained/active slots,
   and the expected day-definition cross product.
5. Verify no roster slot starts outside its projected Operational day (06:00
   boundary), and verify venue/group ownership for every projected row.

## Deployment

1. Stop roster mutations or place the application in maintenance mode.
2. Run the normal transactional migration runner. A preflight, DDL, backfill,
   or equivalence failure rolls the whole migration back.
3. Verify:

   ```sql
   SELECT count(*) FROM roster_days WHERE operational_date IS NULL;
   SELECT count(*) FROM roster_slots WHERE roster_lane_id IS NULL;
   SELECT count(*) FROM roster_lanes;
   SELECT count(*)
   FROM roster_days d
   JOIN roster_week_slot_definitions w
     ON w.roster_week_id = d.roster_week_id;
   ```

   The first two results must be zero and the final two counts must agree.
4. Start the application build generated from the additive schema. Exercise one
   Draft and one Published week, including a retained lane/shift, before
   restoring normal roster mutations.

## Recovery

- If the migration fails, retain its transaction rollback, capture the complete
  error, and restore service on the unchanged schema. Restore the backup only
  if independent evidence shows the transactional rollback did not preserve the
  predecessor database.
- After a successful migration, do **not** drop new columns/tables or rewrite
  customer rows. Roll application behavior back to a compatibility build that
  is generated from this additive schema and continues using legacy week
  authority. The projection triggers keep both representations aligned.
- If equivalence later fails, stop roster mutations, capture the mismatching IDs
  and database backup, and repair/replay only after operator approval. The
  retained legacy tables and columns are the recovery authority until #374's
  separately approved retirement.
