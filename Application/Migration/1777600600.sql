ALTER TABLE venue_config
    ADD COLUMN IF NOT EXISTS roster_end_times_enabled BOOLEAN DEFAULT FALSE NOT NULL;

ALTER TABLE roster_slots
    ADD COLUMN IF NOT EXISTS end_time TIME DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS shift_type_id UUID DEFAULT NULL;

ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_shift_type_id_fkey,
    ADD CONSTRAINT roster_slots_shift_type_id_fkey
        FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_roster_slots_shift_type
    ON roster_slots (shift_type_id)
    WHERE shift_type_id IS NOT NULL AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION enforce_roster_slot_week_definition_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM roster_days rd
        JOIN roster_week_slot_definitions rwsd ON rwsd.id = NEW.roster_week_slot_definition_id
        WHERE rd.id = NEW.roster_day_id
            AND rd.roster_week_id = rwsd.roster_week_id
    ) THEN
        RAISE EXCEPTION 'roster slot day and slot definition must belong to the same roster week';
    END IF;

    IF NEW.shift_type_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_days rd
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            JOIN shift_types st ON st.id = NEW.shift_type_id
            WHERE rd.id = NEW.roster_day_id
                AND st.venue_id = rw.venue_id
        )
    THEN
        RAISE EXCEPTION 'roster slot shift_type_id must stay within roster week venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_slot_week_definition_integrity ON roster_slots;
CREATE TRIGGER enforce_roster_slot_week_definition_integrity BEFORE INSERT OR UPDATE ON roster_slots FOR EACH ROW EXECUTE FUNCTION enforce_roster_slot_week_definition_integrity();
