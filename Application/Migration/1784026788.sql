-- Roster provenance identifies the originating slot and worked day. Managers
-- may correct the assigned staff without rewriting or removing that provenance.
CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF (OLD.source_roster_slot_id IS NOT NULL OR NEW.source_roster_slot_id IS NOT NULL)
        AND (
            NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id
            OR NEW.worked_on IS DISTINCT FROM OLD.worked_on
        )
    THEN
        RAISE EXCEPTION 'roster-derived timesheet worked date and source are immutable';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
