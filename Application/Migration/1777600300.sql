DROP TRIGGER IF EXISTS enforce_staff_shift_preference_venue_integrity ON staff_shift_preferences;
DROP TRIGGER IF EXISTS enforce_staff_shift_preference_venue_integrity_trigger ON staff_shift_preferences;

DROP INDEX IF EXISTS idx_staff_shift_preferences_group_day;
DROP INDEX IF EXISTS idx_staff_shift_preferences_group_staff_day;
DROP INDEX IF EXISTS idx_staff_shift_preferences_active_unique;

ALTER TABLE staff_shift_preferences
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_start_hour_check,
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_end_hour_check,
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_start_hour_check1,
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_preferred_end_hour_check1,
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_roster_group_id_fkey,
    DROP CONSTRAINT IF EXISTS staff_shift_preferences_roster_group_id_fk;

UPDATE staff_shift_preferences
SET preferred_start_hour = GREATEST(5, LEAST(preferred_start_hour, 23)),
    preferred_end_hour = GREATEST(5, LEAST(preferred_end_hour, 23));

WITH active_preferences AS (
    SELECT
        id,
        staff_id,
        weekday_index,
        MIN(preferred_start_hour) OVER (PARTITION BY staff_id, weekday_index) AS collapsed_start_hour,
        MAX(preferred_end_hour) OVER (PARTITION BY staff_id, weekday_index) AS collapsed_end_hour,
        ROW_NUMBER() OVER (PARTITION BY staff_id, weekday_index ORDER BY created_at ASC, id ASC) AS row_number
    FROM staff_shift_preferences
    WHERE deleted_at IS NULL
),
kept_preferences AS (
    SELECT id, collapsed_start_hour, collapsed_end_hour
    FROM active_preferences
    WHERE row_number = 1
)
UPDATE staff_shift_preferences preference
SET preferred_start_hour = kept.collapsed_start_hour,
    preferred_end_hour = kept.collapsed_end_hour
FROM kept_preferences kept
WHERE preference.id = kept.id;

WITH active_preferences AS (
    SELECT
        id,
        ROW_NUMBER() OVER (PARTITION BY staff_id, weekday_index ORDER BY created_at ASC, id ASC) AS row_number
    FROM staff_shift_preferences
    WHERE deleted_at IS NULL
)
UPDATE staff_shift_preferences preference
SET deleted_at = NOW(),
    delete_reason = 'collapsed_roster_group_preferences_to_global_day_window'
FROM active_preferences ranked
WHERE preference.id = ranked.id
    AND ranked.row_number > 1;

ALTER TABLE staff_shift_preferences
    DROP COLUMN IF EXISTS roster_group_id;

ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_preferred_start_hour_check CHECK ((preferred_start_hour >= 5) AND (preferred_start_hour <= 23)),
    ADD CONSTRAINT staff_shift_preferences_preferred_end_hour_check CHECK ((preferred_end_hour >= 5) AND (preferred_end_hour <= 23));

CREATE INDEX idx_staff_shift_preferences_venue_day
    ON staff_shift_preferences (venue_id, weekday_index)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX idx_staff_shift_preferences_active_unique
    ON staff_shift_preferences (staff_id, weekday_index)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION enforce_staff_shift_preference_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff shift preference staff must stay within its venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_staff_shift_preference_venue_integrity
    BEFORE INSERT OR UPDATE ON staff_shift_preferences
    FOR EACH ROW EXECUTE FUNCTION enforce_staff_shift_preference_venue_integrity();
