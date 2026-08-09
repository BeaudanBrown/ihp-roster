-- Cut roster publication authority from legacy weeks to dated roster days.
-- Legacy week identity remains immutable and newly inserted compatibility days
-- snapshot the legacy state, but later roster_weeks.is_live writes cannot
-- reinterpret a roster day's publication history.
CREATE OR REPLACE FUNCTION project_legacy_roster_day()
RETURNS TRIGGER
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
        AND (NEW.roster_week_id IS DISTINCT FROM OLD.roster_week_id
            OR NEW.day_offset IS DISTINCT FROM OLD.day_offset)
    THEN
        RAISE EXCEPTION 'roster day legacy identity is immutable after date-native projection';
    END IF;

    IF NEW.roster_week_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT
        rw.venue_id,
        rw.roster_group_id,
        vc.week_offset_epoch + (rw.week_offset * 7) + NEW.day_offset
    INTO STRICT
        NEW.venue_id,
        NEW.roster_group_id,
        NEW.operational_date
    FROM roster_weeks rw
    JOIN venue_config vc ON vc.venue_id = rw.venue_id
    WHERE rw.id = NEW.roster_week_id;

    IF TG_OP = 'INSERT' THEN
        SELECT (CASE WHEN rw.is_live THEN 'published' ELSE 'draft' END)::roster_day_publication_state_enum
        INTO STRICT NEW.publication_state
        FROM roster_weeks rw
        WHERE rw.id = NEW.roster_week_id;
    ELSE
        NEW.venue_id := OLD.venue_id;
        NEW.roster_group_id := OLD.roster_group_id;
        NEW.operational_date := OLD.operational_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Establish the whole-window invariant for retained history under each venue's
-- current configured start day. Complete groups stay Published; partial groups
-- return entirely to Draft and are never automatically republished.
WITH published_groups AS (
    SELECT
        rd.id,
        COUNT(*) OVER (
            PARTITION BY rd.roster_group_id,
            rd.operational_date - (((EXTRACT(DOW FROM rd.operational_date)::int - vc.roster_week_starts_on + 7) % 7)::int)
        ) AS published_day_count
    FROM roster_days rd
    JOIN venue_config vc ON vc.venue_id = rd.venue_id
    WHERE rd.publication_state = 'published'
)
UPDATE roster_days
SET publication_state = 'draft'
FROM published_groups
WHERE roster_days.id = published_groups.id
  AND published_groups.published_day_count < 7;

CREATE OR REPLACE FUNCTION refresh_legacy_roster_week_day_projections()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.venue_id IS DISTINCT FROM OLD.venue_id
        OR NEW.roster_group_id IS DISTINCT FROM OLD.roster_group_id
        OR NEW.week_offset IS DISTINCT FROM OLD.week_offset
    THEN
        RAISE EXCEPTION 'legacy roster week identity is immutable after date-native projection';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
