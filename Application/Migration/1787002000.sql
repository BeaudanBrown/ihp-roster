-- #366: make dated roster days and date-local lanes authoritative for draft
-- planning while retaining nullable legacy links for rollback and later cleanup.

ALTER TABLE roster_days
    ALTER COLUMN roster_week_id DROP NOT NULL,
    ALTER COLUMN roster_week_id SET DEFAULT NULL;

ALTER TABLE roster_slots
    ALTER COLUMN roster_week_slot_definition_id DROP NOT NULL,
    ALTER COLUMN roster_week_slot_definition_id SET DEFAULT NULL;

-- Preserve explicit date-native lane removals when legacy compatibility writes
-- reproject a retained weekly definition.
CREATE OR REPLACE FUNCTION project_legacy_roster_lane(
    projected_day_id UUID,
    projected_definition_id UUID
)
RETURNS UUID
AS $$
DECLARE
    projected_lane_id UUID;
BEGIN
    INSERT INTO roster_lanes (
        id, roster_day_id, legacy_roster_week_slot_definition_id, name,
        sort_order, deleted_at, deleted_by_user_id, delete_reason,
        created_at, updated_at
    )
    SELECT
        md5(day.id::text || ':' || definition.id::text)::uuid,
        day.id,
        definition.id,
        definition.name,
        definition.sort_order,
        definition.deleted_at,
        definition.deleted_by_user_id,
        definition.delete_reason,
        definition.created_at,
        definition.updated_at
    FROM roster_days day
    JOIN roster_week_slot_definitions definition
        ON definition.roster_week_id = day.roster_week_id
    WHERE day.id = projected_day_id
      AND definition.id = projected_definition_id
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        sort_order = EXCLUDED.sort_order,
        deleted_at = CASE WHEN roster_lanes.delete_reason = 'roster_window_lane_removed' THEN roster_lanes.deleted_at ELSE EXCLUDED.deleted_at END,
        deleted_by_user_id = CASE WHEN roster_lanes.delete_reason = 'roster_window_lane_removed' THEN roster_lanes.deleted_by_user_id ELSE EXCLUDED.deleted_by_user_id END,
        delete_reason = CASE WHEN roster_lanes.delete_reason = 'roster_window_lane_removed' THEN roster_lanes.delete_reason ELSE EXCLUDED.delete_reason END,
        created_at = EXCLUDED.created_at,
        updated_at = EXCLUDED.updated_at
    RETURNING id INTO projected_lane_id;

    IF projected_lane_id IS NULL THEN
        RAISE EXCEPTION 'legacy roster definition cannot be projected to the requested date-local lane';
    END IF;
    RETURN projected_lane_id;
END;
$$ LANGUAGE plpgsql;

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
        roster_week.venue_id,
        roster_week.roster_group_id,
        venue_config.week_offset_epoch + (roster_week.week_offset * 7) + NEW.day_offset,
        (CASE WHEN roster_week.is_live THEN 'published' ELSE 'draft' END)::roster_day_publication_state_enum
    INTO STRICT NEW.venue_id, NEW.roster_group_id, NEW.operational_date, NEW.publication_state
    FROM roster_weeks roster_week
    JOIN venue_config ON venue_config.venue_id = roster_week.venue_id
    WHERE roster_week.id = NEW.roster_week_id;
    IF TG_OP = 'UPDATE' THEN
        NEW.venue_id := OLD.venue_id;
        NEW.roster_group_id := OLD.roster_group_id;
        NEW.operational_date := OLD.operational_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_legacy_roster_day_lanes()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_week_id IS NULL THEN
        RETURN NEW;
    END IF;
    PERFORM project_legacy_roster_lane(NEW.id, definition.id)
    FROM roster_week_slot_definitions definition
    WHERE definition.roster_week_id = NEW.roster_week_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_legacy_roster_slot_lane()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_week_slot_definition_id IS NULL THEN
        IF NEW.roster_lane_id IS NULL THEN
            RAISE EXCEPTION 'date-native roster slots require a date-local roster lane';
        END IF;
        RETURN NEW;
    END IF;
    NEW.roster_lane_id := project_legacy_roster_lane(
        NEW.roster_day_id,
        NEW.roster_week_slot_definition_id
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_roster_day_scope()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM roster_groups roster_group
        WHERE roster_group.id = NEW.roster_group_id
          AND roster_group.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'roster day venue and roster group must share scope';
    END IF;
    IF NEW.roster_week_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM roster_weeks roster_week
        WHERE roster_week.id = NEW.roster_week_id
          AND roster_week.venue_id = NEW.venue_id
          AND roster_week.roster_group_id = NEW.roster_group_id
    ) THEN
        RAISE EXCEPTION 'legacy roster week must match roster day scope';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_roster_lane_scope()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.legacy_roster_week_slot_definition_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM roster_days roster_day
        JOIN roster_week_slot_definitions definition
          ON definition.id = NEW.legacy_roster_week_slot_definition_id
        WHERE roster_day.id = NEW.roster_day_id
          AND roster_day.roster_week_id = definition.roster_week_id
    ) THEN
        RAISE EXCEPTION 'legacy roster lane definition must match roster day week';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_roster_slot_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM roster_lanes lane
        WHERE lane.id = NEW.roster_lane_id
          AND lane.roster_day_id = NEW.roster_day_id
          AND lane.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'roster slot lane must be active and belong to its roster day';
    END IF;
    IF NEW.roster_week_slot_definition_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM roster_lanes lane
        WHERE lane.id = NEW.roster_lane_id
          AND lane.legacy_roster_week_slot_definition_id = NEW.roster_week_slot_definition_id
    ) THEN
        RAISE EXCEPTION 'legacy roster slot definition must match its date-local lane';
    END IF;
    IF NEW.shift_type_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM roster_days roster_day
        JOIN shift_types shift_type ON shift_type.id = NEW.shift_type_id
        WHERE roster_day.id = NEW.roster_day_id
          AND shift_type.venue_id = roster_day.venue_id
    ) THEN
        RAISE EXCEPTION 'roster slot shift type must stay within roster day venue';
    END IF;
    IF NEW.staff_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM roster_days roster_day
        JOIN staff staff_member ON staff_member.id = NEW.staff_id
        WHERE roster_day.id = NEW.roster_day_id
          AND staff_member.venue_id = roster_day.venue_id
    ) THEN
        RAISE EXCEPTION 'roster slot staff assignment must stay within roster day venue';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_slot_week_definition_integrity ON roster_slots;
DROP TRIGGER IF EXISTS validate_roster_day_scope ON roster_days;
DROP TRIGGER IF EXISTS validate_roster_lane_scope ON roster_lanes;
DROP TRIGGER IF EXISTS validate_roster_slot_integrity ON roster_slots;

CREATE TRIGGER validate_roster_day_scope
    BEFORE INSERT OR UPDATE ON roster_days
    FOR EACH ROW EXECUTE FUNCTION validate_roster_day_scope();
CREATE TRIGGER validate_roster_lane_scope
    BEFORE INSERT OR UPDATE ON roster_lanes
    FOR EACH ROW EXECUTE FUNCTION validate_roster_lane_scope();
CREATE TRIGGER validate_roster_slot_integrity
    BEFORE INSERT OR UPDATE ON roster_slots
    FOR EACH ROW EXECUTE FUNCTION validate_roster_slot_integrity();
