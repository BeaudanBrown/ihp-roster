# Explicit roster-shift assignment migration (#304)

Migration: `1785813000.sql`

## Purpose

Preserve every `roster_slots` row while introducing explicit `staff` / `open`
assignment state. Complete legacy rows with no staff become Open. Complete rows
with staff remain Staff-assigned. Wrong-venue staff references become Open.
Structurally incomplete active legacy rows are soft-deleted with
`delete_reason = legacy_incomplete_shift_cleanup`; no row or Timesheet source
reference is deleted.

## Before deployment

1. Take and verify a restorable database backup.
2. Record these counts and retain the output with the deployment:

```sql
SELECT COUNT(*) AS all_slots,
       COUNT(*) FILTER (WHERE deleted_at IS NULL) AS active_slots,
       COUNT(*) FILTER (
           WHERE deleted_at IS NULL
             AND (starts_at IS NULL OR ends_at IS NULL OR ends_at <= starts_at
                  OR shift_type_id IS NULL
                  OR btrim(timezone) <> 'Australia/Melbourne')
       ) AS incomplete_active_slots
FROM roster_slots;

SELECT COUNT(*) AS wrong_venue_staff_assignments
FROM roster_slots rs
JOIN staff s ON s.id = rs.staff_id
JOIN roster_days rd ON rd.id = rs.roster_day_id
JOIN roster_weeks rw ON rw.id = rd.roster_week_id
WHERE rs.deleted_at IS NULL
  AND s.venue_id <> rw.venue_id;

SELECT COUNT(*) AS timesheet_source_references
FROM timesheet_entries
WHERE source_roster_slot_id IS NOT NULL;
```

3. Review the incomplete and wrong-venue rows. The migration deliberately keeps
   them: incomplete rows become deleted history; wrong-venue assignments become
   Open.
4. Ensure no concurrent deployment writes roster shifts during the migration.

## Deployment checks

Run the normal IHP migration runner. It performs repair and a guarded preflight
before setting `assignment_state` `NOT NULL` and validating constraints. Abort
and investigate if it raises `explicit roster shift assignment preflight failed`.

After migration:

```sql
SELECT assignment_state, COUNT(*)
FROM roster_slots
WHERE deleted_at IS NULL
GROUP BY assignment_state
ORDER BY assignment_state;

SELECT COUNT(*) AS invalid_active_slots
FROM roster_slots
WHERE deleted_at IS NULL
  AND (starts_at IS NULL OR ends_at IS NULL OR ends_at <= starts_at
       OR shift_type_id IS NULL
       OR NOT ((assignment_state = 'staff' AND staff_id IS NOT NULL)
               OR (assignment_state = 'open' AND staff_id IS NULL)));

SELECT COUNT(*) AS cleaned_legacy_slots
FROM roster_slots
WHERE deleted_at IS NOT NULL
  AND delete_reason = 'legacy_incomplete_shift_cleanup';

SELECT COUNT(*) AS timesheet_source_references
FROM timesheet_entries
WHERE source_roster_slot_id IS NOT NULL;
```

`invalid_active_slots` must be zero. The Timesheet source-reference count must be
unchanged.

## Rollback and recovery

Application rollback alone is unsafe after this migration because old code does
not supply explicit assignment state or structurally complete shifts. Prefer
forward repair.

If rollback is operator-approved before new application writes:

1. Stop application roster writes and take another backup.
2. Drop the three new checks, remove `assignment_state` `NOT NULL`, and remove
   the column only after confirming the old release is restored.
3. Restore the former `ON DELETE SET NULL` staff/shift-type foreign keys and
   former roster-slot integrity trigger definition from the previous release.
4. Do **not** automatically reactivate `legacy_incomplete_shift_cleanup` rows.
   Review them for active-cell collisions and completeness first. Recover exact
   prior state from the pre-deployment backup if automatic reversal is required.

A failed migration transaction rolls back atomically under the IHP migration
runner. If post-deployment verification fails, stop writes and restore the
verified backup rather than deleting or rewriting historical roster slots or
Timesheet entries ad hoc.
