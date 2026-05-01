CREATE TABLE IF NOT EXISTS roster_week_slot_definitions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_week_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (sort_order >= 0)
);

ALTER TABLE roster_slots
    ADD COLUMN IF NOT EXISTS roster_week_slot_definition_id UUID;

INSERT INTO roster_week_slot_definitions (roster_week_id, name, sort_order, created_at, updated_at)
SELECT source.roster_week_id, source.name, source.slot_sort_order, NOW(), NOW()
FROM (
    SELECT DISTINCT rd.roster_week_id, sn.name, rs.slot_sort_order
    FROM roster_slots rs
    JOIN roster_days rd ON rd.id = rs.roster_day_id
    JOIN slot_names sn ON sn.id = rs.slot_name_id
    WHERE rs.deleted_at IS NULL
) source
WHERE NOT EXISTS (
    SELECT 1
    FROM roster_week_slot_definitions existing
    WHERE existing.roster_week_id = source.roster_week_id
        AND existing.name = source.name
        AND existing.deleted_at IS NULL
);

UPDATE roster_slots rs
SET roster_week_slot_definition_id = rwsd.id,
    slot_sort_order = rwsd.sort_order,
    updated_at = NOW()
FROM roster_days rd, slot_names sn, roster_week_slot_definitions rwsd
WHERE rd.id = rs.roster_day_id
    AND sn.id = rs.slot_name_id
    AND rwsd.roster_week_id = rd.roster_week_id
    AND rwsd.name = sn.name
    AND rwsd.deleted_at IS NULL
    AND rs.roster_week_slot_definition_id IS NULL;

ALTER TABLE roster_slots
    ALTER COLUMN roster_week_slot_definition_id SET NOT NULL;

ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_roster_week_slot_definition_id_fkey;
ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_roster_week_slot_definition_id_fk;
ALTER TABLE roster_slots
    ADD CONSTRAINT roster_slots_roster_week_slot_definition_id_fk
    FOREIGN KEY (roster_week_slot_definition_id) REFERENCES roster_week_slot_definitions (id) ON DELETE RESTRICT;

DROP INDEX IF EXISTS idx_roster_week_slot_definitions_week_sort;
CREATE INDEX idx_roster_week_slot_definitions_week_sort
    ON roster_week_slot_definitions (roster_week_id, sort_order ASC, created_at ASC)
    WHERE deleted_at IS NULL;

DROP INDEX IF EXISTS idx_roster_week_slot_definitions_active_name;
CREATE UNIQUE INDEX idx_roster_week_slot_definitions_active_name
    ON roster_week_slot_definitions (roster_week_id, name)
    WHERE deleted_at IS NULL;

DROP INDEX IF EXISTS idx_roster_slots_active_cell;
CREATE UNIQUE INDEX idx_roster_slots_active_cell
    ON roster_slots (roster_day_id, row_index, roster_week_slot_definition_id)
    WHERE deleted_at IS NULL;

ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_slot_name_id_fkey;
ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_slot_name_id_fk;
ALTER TABLE roster_slots
    DROP COLUMN IF EXISTS slot_name_id;

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

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_slot_week_definition_integrity ON roster_slots;
CREATE TRIGGER enforce_roster_slot_week_definition_integrity BEFORE INSERT OR UPDATE ON roster_slots FOR EACH ROW EXECUTE FUNCTION enforce_roster_slot_week_definition_integrity();
