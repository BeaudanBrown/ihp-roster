-- #365: add the date-native roster persistence foundation while the legacy
-- roster-week runtime remains authoritative. The migration is additive and
-- aborts before changing schema when any legacy row cannot be projected exactly.

DO $$
DECLARE
    issue_summary TEXT;
BEGIN
    SELECT string_agg(issue, '; ' ORDER BY issue)
    INTO issue_summary
    FROM (
        SELECT format('roster_week:%s:missing_or_cross_scope_group_or_config', rw.id) AS issue
        FROM roster_weeks rw
        LEFT JOIN roster_groups rg ON rg.id = rw.roster_group_id
        LEFT JOIN venue_config vc ON vc.venue_id = rw.venue_id
        WHERE rg.id IS NULL
           OR rg.venue_id IS DISTINCT FROM rw.venue_id
           OR vc.id IS NULL
        UNION ALL
        SELECT format('roster_day:%s:invalid_day_offset:%s', rd.id, rd.day_offset)
        FROM roster_days rd
        WHERE rd.day_offset < 0 OR rd.day_offset > 6
        UNION ALL
        SELECT format('roster_slot:%s:cross_scope_or_unmappable_lane', rs.id)
        FROM roster_slots rs
        LEFT JOIN roster_days rd ON rd.id = rs.roster_day_id
        LEFT JOIN roster_week_slot_definitions definition
            ON definition.id = rs.roster_week_slot_definition_id
        WHERE rd.id IS NULL
           OR definition.id IS NULL
           OR definition.roster_week_id IS DISTINCT FROM rd.roster_week_id
        UNION ALL
        SELECT format('roster_slot:%s:cross_scope_staff', rs.id)
        FROM roster_slots rs
        JOIN roster_days rd ON rd.id = rs.roster_day_id
        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
        JOIN staff s ON s.id = rs.staff_id
        WHERE s.venue_id IS DISTINCT FROM rw.venue_id
        UNION ALL
        SELECT format('roster_slot:%s:cross_scope_shift_type', rs.id)
        FROM roster_slots rs
        JOIN roster_days rd ON rd.id = rs.roster_day_id
        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
        JOIN shift_types st ON st.id = rs.shift_type_id
        WHERE st.venue_id IS DISTINCT FROM rw.venue_id
        UNION ALL
        SELECT format('roster_day:%s:deterministic_missing_day_id_collision', existing.id)
        FROM roster_weeks rw
        CROSS JOIN generate_series(0, 6) AS offsets(day_offset)
        JOIN roster_days existing
          ON existing.id = md5(rw.id::text || ':day:' || offsets.day_offset::text)::uuid
        WHERE existing.roster_week_id IS DISTINCT FROM rw.id
           OR existing.day_offset IS DISTINCT FROM offsets.day_offset
        UNION ALL
        SELECT format('roster_slot:%s:unsupported_timezone:%s', rs.id, rs.timezone)
        FROM roster_slots rs
        WHERE rs.starts_at IS NOT NULL
          AND rs.timezone IS DISTINCT FROM 'Australia/Melbourne'
    ) issues;

    IF issue_summary IS NOT NULL THEN
        RAISE EXCEPTION 'date-native roster preflight blocked: %', issue_summary;
    END IF;

    -- Cast through bigint so corrupt extreme offsets are reported as a
    -- preflight failure rather than wrapping integer multiplication.
    BEGIN
        PERFORM vc.week_offset_epoch + ((rw.week_offset::bigint * 7)::int) + rd.day_offset
        FROM roster_days rd
        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
        JOIN venue_config vc ON vc.venue_id = rw.venue_id;
    EXCEPTION
        WHEN numeric_value_out_of_range OR datetime_field_overflow THEN
            RAISE EXCEPTION 'date-native roster preflight blocked: invalid week/day offset cannot produce an Operational date';
    END;
END
$$;

DO $$
DECLARE
    issue_summary TEXT;
BEGIN
    SELECT string_agg(issue, '; ' ORDER BY issue)
    INTO issue_summary
    FROM (
        SELECT format(
            'roster_day_collision:group=%s,date=%s,count=%s',
            roster_group_id,
            operational_date,
            row_count
        ) AS issue
        FROM (
            SELECT
                rw.roster_group_id,
                vc.week_offset_epoch + (rw.week_offset * 7) + offsets.day_offset AS operational_date,
                count(*) AS row_count
            FROM roster_weeks rw
            JOIN venue_config vc ON vc.venue_id = rw.venue_id
            CROSS JOIN generate_series(0, 6) AS offsets(day_offset)
            GROUP BY rw.roster_group_id, vc.week_offset_epoch + (rw.week_offset * 7) + offsets.day_offset
            HAVING count(*) <> 1
        ) collisions
        UNION ALL
        SELECT format(
            'roster_slot:%s:date_instant_contradiction:expected=%s,actual=%s',
            rs.id,
            vc.week_offset_epoch + (rw.week_offset * 7) + rd.day_offset,
            ((rs.starts_at AT TIME ZONE rs.timezone) - INTERVAL '6 hours')::DATE
        ) AS issue
        FROM roster_slots rs
        JOIN roster_days rd ON rd.id = rs.roster_day_id
        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
        JOIN venue_config vc ON vc.venue_id = rw.venue_id
        WHERE rs.starts_at IS NOT NULL
          AND rs.timezone = 'Australia/Melbourne'
          AND ((rs.starts_at AT TIME ZONE rs.timezone) - INTERVAL '6 hours')::DATE
                IS DISTINCT FROM vc.week_offset_epoch + (rw.week_offset * 7) + rd.day_offset
    ) issues;

    IF issue_summary IS NOT NULL THEN
        RAISE EXCEPTION 'date-native roster preflight blocked: %', issue_summary;
    END IF;
END
$$;

CREATE TYPE roster_day_publication_state_enum AS ENUM ('draft', 'published');

ALTER TABLE venue_config
    ADD COLUMN roster_calendar_revision INT DEFAULT 1 NOT NULL,
    ADD CONSTRAINT venue_config_roster_calendar_revision_check CHECK (roster_calendar_revision > 0);

ALTER TABLE roster_days
    ADD COLUMN venue_id UUID DEFAULT NULL,
    ADD COLUMN roster_group_id UUID DEFAULT NULL,
    ADD COLUMN operational_date DATE DEFAULT NULL,
    ADD COLUMN publication_state roster_day_publication_state_enum DEFAULT NULL;

CREATE TABLE roster_lanes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_day_id UUID NOT NULL,
    legacy_roster_week_slot_definition_id UUID DEFAULT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_day_id, legacy_roster_week_slot_definition_id),
    FOREIGN KEY (roster_day_id) REFERENCES roster_days (id) ON DELETE RESTRICT,
    FOREIGN KEY (legacy_roster_week_slot_definition_id) REFERENCES roster_week_slot_definitions (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (sort_order >= 0)
);

ALTER TABLE roster_slots
    ADD COLUMN roster_lane_id UUID DEFAULT NULL;

-- Materialize absent empty days so every legacy week's publication state has
-- exactly seven deterministic day projections. Existing day IDs and timestamps
-- are untouched; synthesized empty days inherit their week timestamps.
INSERT INTO roster_days (
    id,
    roster_week_id,
    day_offset,
    is_closed,
    row_count,
    created_at,
    updated_at
)
SELECT
    md5(rw.id::text || ':day:' || offsets.day_offset::text)::uuid,
    rw.id,
    offsets.day_offset,
    FALSE,
    4,
    rw.created_at,
    rw.updated_at
FROM roster_weeks rw
CROSS JOIN generate_series(0, 6) AS offsets(day_offset)
ON CONFLICT (roster_week_id, day_offset) DO NOTHING;

-- Preserve roster-day IDs and timestamps; only populate the additive identity
-- and publication columns from the still-authoritative week aggregate.
UPDATE roster_days rd
SET venue_id = rw.venue_id,
    roster_group_id = rw.roster_group_id,
    operational_date = vc.week_offset_epoch + (rw.week_offset * 7) + rd.day_offset,
    publication_state = (CASE WHEN rw.is_live THEN 'published' ELSE 'draft' END)::roster_day_publication_state_enum
FROM roster_weeks rw
JOIN venue_config vc ON vc.venue_id = rw.venue_id
WHERE rw.id = rd.roster_week_id;

-- A weekly definition has one deterministic date-local projection for every
-- legacy day, including retained soft-deleted definitions.
INSERT INTO roster_lanes (
    id,
    roster_day_id,
    legacy_roster_week_slot_definition_id,
    name,
    sort_order,
    deleted_at,
    deleted_by_user_id,
    delete_reason,
    created_at,
    updated_at
)
SELECT
    md5(rd.id::text || ':' || definition.id::text)::uuid,
    rd.id,
    definition.id,
    definition.name,
    definition.sort_order,
    definition.deleted_at,
    definition.deleted_by_user_id,
    definition.delete_reason,
    definition.created_at,
    definition.updated_at
FROM roster_days rd
JOIN roster_week_slot_definitions definition
    ON definition.roster_week_id = rd.roster_week_id
ON CONFLICT (id) DO UPDATE SET
    roster_day_id = EXCLUDED.roster_day_id,
    legacy_roster_week_slot_definition_id = EXCLUDED.legacy_roster_week_slot_definition_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    deleted_at = EXCLUDED.deleted_at,
    deleted_by_user_id = EXCLUDED.deleted_by_user_id,
    delete_reason = EXCLUDED.delete_reason,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at;

UPDATE roster_slots rs
SET roster_lane_id = lane.id
FROM roster_lanes lane
WHERE lane.roster_day_id = rs.roster_day_id
  AND lane.legacy_roster_week_slot_definition_id = rs.roster_week_slot_definition_id;

DO $$
DECLARE
    issue_summary TEXT;
BEGIN
    SELECT string_agg(issue, '; ' ORDER BY issue)
    INTO issue_summary
    FROM (
        SELECT format('roster_day:%s:projection_mismatch', rd.id) AS issue
        FROM roster_days rd
        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
        JOIN venue_config vc ON vc.venue_id = rw.venue_id
        WHERE rd.venue_id IS DISTINCT FROM rw.venue_id
           OR rd.roster_group_id IS DISTINCT FROM rw.roster_group_id
           OR rd.operational_date IS DISTINCT FROM vc.week_offset_epoch + (rw.week_offset * 7) + rd.day_offset
           OR rd.publication_state::text IS DISTINCT FROM CASE WHEN rw.is_live THEN 'published' ELSE 'draft' END
        UNION ALL
        SELECT format('roster_week:%s:expected_seven_day_projections:actual=%s', rw.id, count(rd.id))
        FROM roster_weeks rw
        LEFT JOIN roster_days rd ON rd.roster_week_id = rw.id
        GROUP BY rw.id
        HAVING count(rd.id) <> 7
            OR min(rd.day_offset) <> 0
            OR max(rd.day_offset) <> 6
        UNION ALL
        SELECT format('roster_lane:%s:projection_mismatch', lane.id)
        FROM roster_lanes lane
        JOIN roster_days rd ON rd.id = lane.roster_day_id
        JOIN roster_week_slot_definitions definition
            ON definition.id = lane.legacy_roster_week_slot_definition_id
        WHERE definition.roster_week_id IS DISTINCT FROM rd.roster_week_id
           OR lane.id IS DISTINCT FROM md5(rd.id::text || ':' || definition.id::text)::uuid
           OR lane.name IS DISTINCT FROM definition.name
           OR lane.sort_order IS DISTINCT FROM definition.sort_order
           OR lane.deleted_at IS DISTINCT FROM definition.deleted_at
           OR lane.deleted_by_user_id IS DISTINCT FROM definition.deleted_by_user_id
           OR lane.delete_reason IS DISTINCT FROM definition.delete_reason
           OR lane.created_at IS DISTINCT FROM definition.created_at
           OR lane.updated_at IS DISTINCT FROM definition.updated_at
        UNION ALL
        SELECT format('roster_slot:%s:projection_mismatch', rs.id)
        FROM roster_slots rs
        LEFT JOIN roster_lanes lane ON lane.id = rs.roster_lane_id
        WHERE lane.id IS NULL
           OR lane.roster_day_id IS DISTINCT FROM rs.roster_day_id
           OR lane.legacy_roster_week_slot_definition_id IS DISTINCT FROM rs.roster_week_slot_definition_id
        UNION ALL
        SELECT format('roster_lane_count:expected=%s,actual=%s', expected_count, actual_count)
        FROM (
            SELECT
                (SELECT count(*)
                 FROM roster_days rd
                 JOIN roster_week_slot_definitions definition
                   ON definition.roster_week_id = rd.roster_week_id) AS expected_count,
                (SELECT count(*) FROM roster_lanes) AS actual_count
        ) counts
        WHERE expected_count IS DISTINCT FROM actual_count
    ) issues;

    IF issue_summary IS NOT NULL THEN
        RAISE EXCEPTION 'date-native roster equivalence check failed: %', issue_summary;
    END IF;
END
$$;

ALTER TABLE roster_days
    ALTER COLUMN venue_id SET NOT NULL,
    ALTER COLUMN roster_group_id SET NOT NULL,
    ALTER COLUMN operational_date SET NOT NULL,
    ALTER COLUMN publication_state SET DEFAULT 'draft',
    ALTER COLUMN publication_state SET NOT NULL,
    ADD CONSTRAINT roster_days_venue_id_fkey FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    ADD CONSTRAINT roster_days_roster_group_id_fkey FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    ADD CONSTRAINT roster_days_group_operational_date_key UNIQUE (roster_group_id, operational_date);

ALTER TABLE roster_slots
    ALTER COLUMN roster_lane_id SET NOT NULL,
    ADD CONSTRAINT roster_slots_roster_lane_id_fkey FOREIGN KEY (roster_lane_id) REFERENCES roster_lanes (id) ON DELETE RESTRICT;

CREATE INDEX idx_roster_days_venue_date ON roster_days (venue_id, operational_date);
CREATE INDEX idx_roster_lanes_day_sort ON roster_lanes (roster_day_id, sort_order);
CREATE INDEX idx_roster_slots_lane ON roster_slots (roster_lane_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_slots_active_lane_cell ON roster_slots (roster_day_id, row_index, roster_lane_id) WHERE deleted_at IS NULL;

-- Compatibility projection: legacy writes remain authoritative until #366.
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

    SELECT
        rw.venue_id,
        rw.roster_group_id,
        vc.week_offset_epoch + (rw.week_offset * 7) + NEW.day_offset,
        (CASE WHEN rw.is_live THEN 'published' ELSE 'draft' END)::roster_day_publication_state_enum
    INTO STRICT
        NEW.venue_id,
        NEW.roster_group_id,
        NEW.operational_date,
        NEW.publication_state
    FROM roster_weeks rw
    JOIN venue_config vc ON vc.venue_id = rw.venue_id
    WHERE rw.id = NEW.roster_week_id;

    IF TG_OP = 'UPDATE' THEN
        NEW.venue_id := OLD.venue_id;
        NEW.roster_group_id := OLD.roster_group_id;
        NEW.operational_date := OLD.operational_date;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
        deleted_at = EXCLUDED.deleted_at,
        deleted_by_user_id = EXCLUDED.deleted_by_user_id,
        delete_reason = EXCLUDED.delete_reason,
        created_at = EXCLUDED.created_at,
        updated_at = EXCLUDED.updated_at
    RETURNING id INTO projected_lane_id;

    IF projected_lane_id IS NULL THEN
        RAISE EXCEPTION 'legacy roster definition cannot be projected to the requested date-local lane';
    END IF;
    RETURN projected_lane_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_legacy_roster_day_lanes()
RETURNS TRIGGER
AS $$
BEGIN
    PERFORM project_legacy_roster_lane(NEW.id, definition.id)
    FROM roster_week_slot_definitions definition
    WHERE definition.roster_week_id = NEW.roster_week_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_legacy_roster_week_definition_lanes()
RETURNS TRIGGER
AS $$
BEGIN
    PERFORM project_legacy_roster_lane(day.id, NEW.id)
    FROM roster_days day
    WHERE day.roster_week_id = NEW.roster_week_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION project_legacy_roster_slot_lane()
RETURNS TRIGGER
AS $$
BEGIN
    NEW.roster_lane_id := project_legacy_roster_lane(
        NEW.roster_day_id,
        NEW.roster_week_slot_definition_id
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_legacy_roster_lane_identity_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_day_id IS DISTINCT FROM OLD.roster_day_id
        OR NEW.legacy_roster_week_slot_definition_id IS DISTINCT FROM OLD.legacy_roster_week_slot_definition_id
    THEN
        RAISE EXCEPTION 'projected roster lane identity is immutable during legacy compatibility';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_legacy_roster_definition_week_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_week_id IS DISTINCT FROM OLD.roster_week_id THEN
        RAISE EXCEPTION 'legacy roster definition week identity is immutable after date-native projection';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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
    IF NEW.is_live IS DISTINCT FROM OLD.is_live THEN
        UPDATE roster_days
        SET roster_week_id = roster_week_id
        WHERE roster_week_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION advance_roster_calendar_revision()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_week_starts_on IS DISTINCT FROM OLD.roster_week_starts_on THEN
        IF OLD.roster_calendar_revision = 2147483647 THEN
            RAISE EXCEPTION 'roster calendar revision exhausted';
        END IF;
        NEW.roster_calendar_revision := OLD.roster_calendar_revision + 1;
    ELSE
        NEW.roster_calendar_revision := OLD.roster_calendar_revision;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER refresh_legacy_roster_week_day_projections
    AFTER UPDATE ON roster_weeks
    FOR EACH ROW EXECUTE FUNCTION refresh_legacy_roster_week_day_projections();
CREATE TRIGGER advance_roster_calendar_revision
    BEFORE UPDATE ON venue_config
    FOR EACH ROW EXECUTE FUNCTION advance_roster_calendar_revision();
CREATE TRIGGER project_legacy_roster_day
    BEFORE INSERT OR UPDATE ON roster_days
    FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_day();
CREATE TRIGGER project_legacy_roster_day_lanes
    AFTER INSERT OR UPDATE ON roster_days
    FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_day_lanes();
CREATE TRIGGER prevent_legacy_roster_definition_week_change
    BEFORE UPDATE ON roster_week_slot_definitions
    FOR EACH ROW EXECUTE FUNCTION prevent_legacy_roster_definition_week_change();
CREATE TRIGGER project_legacy_roster_week_definition_lanes
    AFTER INSERT OR UPDATE ON roster_week_slot_definitions
    FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_week_definition_lanes();
CREATE TRIGGER prevent_legacy_roster_lane_identity_change
    BEFORE UPDATE ON roster_lanes
    FOR EACH ROW EXECUTE FUNCTION prevent_legacy_roster_lane_identity_change();
CREATE TRIGGER project_legacy_roster_slot_lane
    BEFORE INSERT OR UPDATE ON roster_slots
    FOR EACH ROW EXECUTE FUNCTION project_legacy_roster_slot_lane();
CREATE TRIGGER prevent_hard_delete_roster_lanes
    BEFORE DELETE ON roster_lanes
    FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
