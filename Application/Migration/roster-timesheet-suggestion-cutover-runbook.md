# Roster Timesheet Suggestion Cutover

Operator procedure for `Application/Migration/1784005193.sql`, which retires
background roster-to-Timesheet creation and enables transient suggestions.

## Preflight And Apply

1. Take and verify the normal restorable database backup.
2. Stop every web/worker process from the legacy release. In particular, no
   legacy app-job worker may claim `roster_timesheet_creation` while the
   migration runs.
3. Apply the migration through the normal IHP runner before starting the new
   release.
4. Verify `venue_config.auto_timesheet_creation_enabled` is false for every
   venue; no `roster_timesheet_creation` job remains in an active status; and
   `idx_timesheet_entries_source_roster_slot` is the partial unique index over
   non-deleted source-linked entries.
5. Start only the new release, then verify a live eligible roster shift appears
   as a suggestion and soft-deleting its materialized entry makes the suggestion
   eligible again without removing history.

## Recovery

A failed migration transaction rolls back atomically. Stop deployment and
investigate before retrying. After commit, an application rollback may leave the
false compatibility setting, retired historical jobs, partial unique index, and
identity trigger in place. Do not restore the former all-history unique index
after a new source snapshot exists: it would conflict with retained soft-deleted
history. Any different reversal requires a separately reviewed migration and
backup-based recovery plan.
