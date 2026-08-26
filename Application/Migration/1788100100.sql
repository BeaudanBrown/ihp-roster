-- GitHub #374: repair trigger functions left with legacy record-field references
-- after migration 1788100000 retired those columns. PostgreSQL does not resolve
-- PL/pgSQL NEW/OLD record fields until trigger execution, so the predecessor
-- function bodies survived the column drops but failed on the next write.

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
