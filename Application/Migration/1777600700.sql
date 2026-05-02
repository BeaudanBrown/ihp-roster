ALTER TABLE venue_config
    ADD COLUMN IF NOT EXISTS auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL;

ALTER TABLE timesheet_entries
    ADD COLUMN IF NOT EXISTS source_roster_slot_id UUID DEFAULT NULL;

ALTER TABLE timesheet_entries
    DROP CONSTRAINT IF EXISTS timesheet_entries_source_roster_slot_id_fkey,
    ADD CONSTRAINT timesheet_entries_source_roster_slot_id_fkey
        FOREIGN KEY (source_roster_slot_id) REFERENCES roster_slots (id) ON DELETE RESTRICT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_timesheet_entries_source_roster_slot
    ON timesheet_entries (source_roster_slot_id)
    WHERE source_roster_slot_id IS NOT NULL;

CREATE OR REPLACE FUNCTION enforce_timesheet_entry_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match staff_id venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM shift_types st
        WHERE st.id = NEW.shift_type_id
            AND st.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match shift_type_id venue';
    END IF;

    IF NEW.staff_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM staff_pay_versions spv
            WHERE spv.id = NEW.staff_pay_version_id
                AND spv.venue_id = NEW.venue_id
                AND spv.staff_id = NEW.staff_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry staff_pay_version_id must match entry staff and venue';
    END IF;

    IF NEW.shift_type_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM shift_type_pay_versions stpv
            WHERE stpv.id = NEW.shift_type_pay_version_id
                AND stpv.venue_id = NEW.venue_id
                AND stpv.shift_type_id = NEW.shift_type_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry shift_type_pay_version_id must match entry shift type and venue';
    END IF;

    IF NEW.source_roster_slot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_slots rs
            JOIN roster_days rd ON rd.id = rs.roster_day_id
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            WHERE rs.id = NEW.source_roster_slot_id
                AND rw.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry source_roster_slot_id must stay within entry venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_timesheet_entry_venue_integrity ON timesheet_entries;
CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_entry_venue_integrity();
