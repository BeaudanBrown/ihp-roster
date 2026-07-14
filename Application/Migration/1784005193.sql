-- Deployment precondition: stop legacy app-job workers before this migration.
-- Allow a roster-derived suggestion to return after its linked timesheet entry
-- has been soft-deleted, while preserving every historical snapshot.
-- Recovery note: do not restore the former all-history unique index after new
-- snapshots exist. An application rollback can safely leave this partial index,
-- the false compatibility setting, retired jobs, and the identity trigger in place.
DROP INDEX IF EXISTS idx_timesheet_entries_source_roster_slot;

CREATE UNIQUE INDEX idx_timesheet_entries_source_roster_slot
    ON timesheet_entries (source_roster_slot_id)
    WHERE source_roster_slot_id IS NOT NULL
      AND deleted_at IS NULL;

-- Keep the legacy column for a non-destructive deployment, but make it inert.
UPDATE venue_config
SET auto_timesheet_creation_enabled = FALSE
WHERE auto_timesheet_creation_enabled = TRUE;

COMMENT ON COLUMN venue_config.auto_timesheet_creation_enabled IS
    'Deprecated and inert: roster-derived timesheet suggestions replaced background creation.';

-- Preserve historical jobs while retiring every job that could still create a row.
UPDATE app_jobs
SET status = 'job_status_succeeded',
    result = jsonb_build_object(
        'status', 'retired',
        'reason', 'replaced_by_roster_timesheet_suggestions'
    ),
    last_error = NULL,
    locked_at = NULL,
    locked_by = NULL,
    updated_at = NOW()
WHERE job_kind = 'roster_timesheet_creation'
  AND status IN (
      'job_status_not_started',
      'job_status_running',
      'job_status_retry'
  );

CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF (OLD.source_roster_slot_id IS NOT NULL OR NEW.source_roster_slot_id IS NOT NULL)
        AND (
            NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id
            OR NEW.staff_id IS DISTINCT FROM OLD.staff_id
            OR NEW.worked_on IS DISTINCT FROM OLD.worked_on
        )
    THEN
        RAISE EXCEPTION 'roster-derived timesheet staff, worked date, and source are immutable';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_derived_timesheet_identity_immutable
    ON timesheet_entries;

CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable
    BEFORE UPDATE ON timesheet_entries
    FOR EACH ROW
    EXECUTE FUNCTION enforce_roster_derived_timesheet_identity_immutable();
