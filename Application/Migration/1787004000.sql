-- Give Week template days immutable calendar-weekday meaning while preserving
-- Day templates as target-date-relative content. Existing Week day_index values
-- are interpreted under each venue's current configured start weekday.
ALTER TABLE roster_template_days
    ADD COLUMN weekday_index INT DEFAULT NULL;

-- Saved template rows are normally immutable. This bounded backfill is the one
-- deployment-time exception and changes identity metadata only, not content.
ALTER TABLE roster_template_days DISABLE TRIGGER prevent_saved_roster_template_days_mutation;

UPDATE roster_template_days
SET weekday_index = (venue_config.roster_week_starts_on + roster_template_days.day_index) % 7
FROM roster_template_designs
JOIN roster_groups
  ON roster_groups.id = roster_template_designs.roster_group_id
JOIN venue_config
  ON venue_config.venue_id = roster_groups.venue_id
WHERE roster_template_designs.id = roster_template_days.roster_template_design_id
  AND roster_template_designs.scale = 'week';

ALTER TABLE roster_template_days ENABLE TRIGGER prevent_saved_roster_template_days_mutation;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM roster_template_days day
        JOIN roster_template_designs design ON design.id = day.roster_template_design_id
        WHERE (design.scale = 'week' AND day.weekday_index IS NULL)
           OR (design.scale = 'day' AND day.weekday_index IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'roster template weekday backfill failed';
    END IF;
END;
$$;

ALTER TABLE roster_template_days
    ADD CONSTRAINT roster_template_days_weekday_index_check
    CHECK (weekday_index IS NULL OR ((weekday_index >= 0) AND (weekday_index <= 6)));

CREATE UNIQUE INDEX idx_roster_template_days_design_weekday
    ON roster_template_days (roster_template_design_id, weekday_index)
    WHERE weekday_index IS NOT NULL;

-- Notification runs now identify an immutable explicit [week_start, window_end)
-- date window. Legacy week identity remains nullable provenance for old runs.
ALTER TABLE roster_notification_runs
    ADD COLUMN window_end DATE;

UPDATE roster_notification_runs
SET window_end = week_start + 7;

ALTER TABLE roster_notification_runs
    ALTER COLUMN window_end SET NOT NULL,
    ALTER COLUMN roster_week_id DROP NOT NULL,
    ALTER COLUMN week_offset DROP NOT NULL;

ALTER TABLE roster_notification_runs
    ADD CONSTRAINT roster_notification_runs_window_range_check
    CHECK (window_end > week_start);

CREATE INDEX idx_roster_notification_runs_group_window_created
    ON roster_notification_runs (roster_group_id, week_start, window_end, created_at DESC);

CREATE OR REPLACE FUNCTION validate_roster_notification_window()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.window_end <> NEW.week_start + 7 THEN
        RAISE EXCEPTION 'roster notification window must span exactly seven days';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER validate_roster_notification_window
    BEFORE INSERT OR UPDATE ON roster_notification_runs
    FOR EACH ROW EXECUTE FUNCTION validate_roster_notification_window();

CREATE OR REPLACE FUNCTION enforce_roster_template_integrity()
RETURNS TRIGGER
AS $$
DECLARE
    design_group_id UUID;
    design_scale TEXT;
    group_venue_id UUID;
BEGIN
    IF TG_TABLE_NAME = 'roster_template_days' THEN
        SELECT roster_group_id, scale INTO design_group_id, design_scale
        FROM roster_template_designs WHERE id = NEW.roster_template_design_id;
        IF design_scale = 'day' AND (NEW.day_index <> 0 OR NEW.weekday_index IS NOT NULL) THEN
            RAISE EXCEPTION 'day roster templates may contain only target-relative day index zero';
        END IF;
        IF design_scale = 'week' AND NEW.weekday_index IS NULL THEN
            RAISE EXCEPTION 'week roster template days require explicit weekday identity';
        END IF;
        RETURN NEW;
    END IF;

    SELECT d.roster_group_id, d.scale, rg.venue_id
    INTO design_group_id, design_scale, group_venue_id
    FROM roster_template_designs d
    JOIN roster_groups rg ON rg.id = d.roster_group_id
    WHERE d.id = NEW.roster_template_design_id;

    IF NOT EXISTS (
        SELECT 1
        FROM roster_template_days d
        JOIN roster_template_columns c ON c.roster_template_design_id = d.roster_template_design_id
        WHERE d.id = NEW.roster_template_day_id
          AND c.id = NEW.roster_template_column_id
          AND d.roster_template_design_id = NEW.roster_template_design_id
    ) THEN
        RAISE EXCEPTION 'roster template shift content must belong to one design';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM shift_types st
        WHERE st.id = NEW.shift_type_id AND st.venue_id = group_venue_id
    ) THEN
        RAISE EXCEPTION 'roster template shift type must stay within template venue';
    END IF;

    IF NEW.staff_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM staff s
        WHERE s.id = NEW.staff_id AND s.venue_id = group_venue_id
    ) THEN
        RAISE EXCEPTION 'roster template staff assignment must stay within template venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
