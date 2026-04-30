DROP TRIGGER IF EXISTS enforce_staff_shift_preference_venue_integrity ON staff_shift_preferences;

DROP INDEX IF EXISTS idx_staff_shift_preferences_active_unique;
DROP INDEX IF EXISTS idx_staff_shift_preferences_group_staff_day_slot;

ALTER TABLE staff_shift_preferences
    ADD COLUMN IF NOT EXISTS preferred_start_hour INT DEFAULT 9 NOT NULL,
    ADD COLUMN IF NOT EXISTS preferred_end_hour INT DEFAULT 17 NOT NULL;

WITH duplicate_active_preferences AS (
    SELECT id
    FROM (
        SELECT
            id,
            row_number() OVER (
                PARTITION BY staff_id, roster_group_id, weekday_index
                ORDER BY created_at ASC, id ASC
            ) AS row_number
        FROM staff_shift_preferences
        WHERE deleted_at IS NULL
    ) ranked_preferences
    WHERE row_number > 1
)
UPDATE staff_shift_preferences
SET
    deleted_at = NOW(),
    delete_reason = 'collapsed_slot_preferences_to_day_window'
WHERE id IN (SELECT id FROM duplicate_active_preferences);

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_slot_name_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_slot_name_id_fk;
ALTER TABLE staff_shift_preferences DROP COLUMN IF EXISTS slot_name_id;

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_weekday_index_check;
ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_weekday_index_check
    CHECK ((weekday_index >= 0) AND (weekday_index <= 6));

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_start_hour_check;
ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_preferred_start_hour_check
    CHECK ((preferred_start_hour >= 0) AND (preferred_start_hour <= 23));

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_end_hour_check;
ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_preferred_end_hour_check
    CHECK ((preferred_end_hour >= 0) AND (preferred_end_hour <= 23));

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_hour_window_check;
ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_preferred_hour_window_check
    CHECK (preferred_start_hour <= preferred_end_hour);

CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_group_staff_day
    ON staff_shift_preferences (roster_group_id, staff_id, weekday_index)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_shift_preferences_active_unique
    ON staff_shift_preferences (staff_id, roster_group_id, weekday_index)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION enforce_staff_shift_preference_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        JOIN roster_groups rg ON rg.id = NEW.roster_group_id
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
            AND rg.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff shift preference staff and roster group must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_staff_shift_preference_venue_integrity BEFORE INSERT OR UPDATE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION enforce_staff_shift_preference_venue_integrity();
