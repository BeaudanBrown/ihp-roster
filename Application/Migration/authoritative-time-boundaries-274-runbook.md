# Authoritative time boundaries migration (#274)

## Scope

`1784932300.sql` replaces roster/timesheet wall-clock columns with `TIMESTAMPTZ`
boundaries and an IANA timezone snapshot. It drops the superseded columns in the
same transaction, so old and new application versions are not schema-compatible.

## Required approval and backup

Before production:

1. Record operator approval on GitHub #274.
2. Stop web, worker, and migration units for a maintenance window.
3. Take and verify a restorable database backup, for example:

   ```bash
   pg_dump --format=custom --file=bepis-before-1784932300.dump "$DATABASE_URL"
   pg_restore --list bepis-before-1784932300.dump >/dev/null
   ```

4. Test restore plus migration against a production copy before the maintenance
   window.

Do not apply without the backup. The migration is forward-only and intentionally
drops the legacy authority columns.

## Preflight

The application must be fully stopped. Confirm every operational venue has a
non-empty timezone and that legacy rows satisfy the shape expected by the
backfill:

```sql
SELECT id, timezone
FROM venue_config
WHERE btrim(timezone) IS DISTINCT FROM 'Australia/Melbourne';

SELECT te.id
FROM timesheet_entries te
WHERE te.end_time = te.start_time
   OR ((te.break_start_time IS NULL) <> (te.break_end_time IS NULL));

SELECT te.id
FROM timesheet_entries te
WHERE te.had_break
  AND te.break_minutes IS DISTINCT FROM
      EXTRACT(EPOCH FROM (
          (te.break_end_time - te.break_start_time)
          + CASE
              WHEN te.break_end_time <= te.break_start_time THEN INTERVAL '1 day'
              ELSE INTERVAL '0'
            END
      )) / 60;

SELECT rs.id
FROM roster_slots rs
JOIN roster_days rd ON rd.id = rs.roster_day_id
JOIN roster_weeks rw ON rw.id = rd.roster_week_id
LEFT JOIN venue_config vc ON vc.venue_id = rw.venue_id
WHERE vc.id IS NULL OR char_length(btrim(vc.timezone)) = 0;

SELECT rs.id
FROM roster_slots rs
WHERE rs.duration_minutes IS NOT NULL
  AND (
      rs.start_time IS NULL
      OR rs.end_time IS NULL
      OR rs.duration_minutes IS DISTINCT FROM
          EXTRACT(EPOCH FROM (
              (rs.end_time - rs.start_time)
              + CASE
                  WHEN rs.end_time <= rs.start_time THEN INTERVAL '1 day'
                  ELSE INTERVAL '0'
                END
          )) / 60
  );
```

All queries must return zero rows. The current `VenueTime` authority supports
Melbourne only, so another configured timezone needs its own approved authority
work before this migration can run. Roster clocks before 06:00 are interpreted as
the following calendar day of the hospitality operational day. Repeated autumn
clocks use their first occurrence. A spring-forward clock that does not exist
causes the migration to abort instead of being normalized; correct that legacy
row under an approved operator data-fix before retrying. A legacy
`break_minutes` and any `duration_minutes` value must agree with their clocks;
the migration repeats those checks after instant resolution so a DST/ambiguity
difference cannot silently change paid duration.

The migration performs a second, instant-based validation and aborts
transactionally before dropping columns if any positive, paired, or
contained-boundary invariant fails.

## Apply and verify

Run the normal IHP migration command with the new application release, then check:

```sql
SELECT count(*) FROM roster_slots
WHERE timezone <> 'Australia/Melbourne'
   OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at <= starts_at);

SELECT count(*) FROM timesheet_entries
WHERE timezone <> 'Australia/Melbourne'
   OR ends_at <= starts_at
   OR ((break_starts_at IS NULL) <> (break_ends_at IS NULL))
   OR (break_starts_at IS NOT NULL AND
       (break_starts_at < starts_at OR break_ends_at <= break_starts_at OR break_ends_at > ends_at));

SELECT column_name
FROM information_schema.columns
WHERE table_name IN ('roster_slots', 'timesheet_entries')
  AND column_name IN (
      'worked_on', 'start_time', 'end_time', 'had_break',
      'break_start_time', 'break_end_time', 'break_minutes', 'duration_minutes'
  );
```

Every count and the retired-column query must return zero. Repeated autumn civil
times are backfilled to the first occurrence. Start the new application only
after these checks pass, then smoke-test one roster and one Timesheets week.

## Recovery

There is no in-place rollback because the superseded columns have been dropped.
If verification fails after commit:

1. Stop all new application units.
2. Preserve the failed database for diagnosis.
3. Restore `bepis-before-1784932300.dump` into a clean database.
4. Point the old application release at the restored database.
5. Record the incident and recovery result on #274 before another attempt.
