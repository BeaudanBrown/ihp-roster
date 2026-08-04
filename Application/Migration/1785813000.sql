-- GitHub #304: make every retained roster shift assignment explicit.
-- This migration preserves every row. Structurally incomplete active legacy rows
-- are soft-deleted, and wrong-venue staff assignments are repaired to Open.

ALTER TABLE roster_slots
    ADD COLUMN assignment_state TEXT DEFAULT NULL;

-- Soft-delete cleanup must be able to update malformed historical rows without
-- the existing cross-table trigger rejecting the lifecycle-only update.
CREATE OR REPLACE FUNCTION enforce_roster_slot_week_definition_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

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

    IF NEW.staff_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_days rd
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            JOIN staff s ON s.id = NEW.staff_id
            WHERE rd.id = NEW.roster_day_id
                AND s.venue_id = rw.venue_id
        )
    THEN
        RAISE EXCEPTION 'roster slot staff_id must stay within roster week venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

UPDATE roster_slots AS rs
SET deleted_at = NOW(),
    delete_reason = 'legacy_incomplete_shift_cleanup',
    updated_at = NOW()
WHERE rs.deleted_at IS NULL
  AND (
      rs.starts_at IS NULL
      OR rs.ends_at IS NULL
      OR rs.ends_at <= rs.starts_at
      OR rs.shift_type_id IS NULL
      OR btrim(rs.timezone) <> 'Australia/Melbourne'
      OR NOT EXISTS (
          SELECT 1
          FROM roster_days rd
          JOIN roster_week_slot_definitions rwsd
            ON rwsd.id = rs.roster_week_slot_definition_id
          WHERE rd.id = rs.roster_day_id
            AND rd.roster_week_id = rwsd.roster_week_id
      )
      OR NOT EXISTS (
          SELECT 1
          FROM roster_days rd
          JOIN roster_weeks rw ON rw.id = rd.roster_week_id
          JOIN shift_types st ON st.id = rs.shift_type_id
          WHERE rd.id = rs.roster_day_id
            AND st.venue_id = rw.venue_id
      )
  );

UPDATE roster_slots AS rs
SET assignment_state = 'open',
    staff_id = NULL,
    updated_at = NOW()
WHERE rs.deleted_at IS NULL
  AND rs.staff_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM roster_days rd
      JOIN roster_weeks rw ON rw.id = rd.roster_week_id
      JOIN staff s ON s.id = rs.staff_id
      WHERE rd.id = rs.roster_day_id
        AND s.venue_id = rw.venue_id
  );

UPDATE roster_slots
SET assignment_state = CASE
        WHEN staff_id IS NULL THEN 'open'
        ELSE 'staff'
    END,
    updated_at = NOW()
WHERE assignment_state IS NULL;

DO $$
DECLARE
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO invalid_count
    FROM roster_slots rs
    WHERE rs.assignment_state IS NULL
       OR NOT (
            (rs.assignment_state = 'staff' AND rs.staff_id IS NOT NULL)
            OR (rs.assignment_state = 'open' AND rs.staff_id IS NULL)
       )
       OR (
            rs.deleted_at IS NULL
            AND (
                rs.starts_at IS NULL
                OR rs.ends_at IS NULL
                OR rs.ends_at <= rs.starts_at
                OR rs.shift_type_id IS NULL
                OR btrim(rs.timezone) <> 'Australia/Melbourne'
                OR NOT EXISTS (
                    SELECT 1
                    FROM roster_days rd
                    JOIN roster_week_slot_definitions rwsd
                      ON rwsd.id = rs.roster_week_slot_definition_id
                    WHERE rd.id = rs.roster_day_id
                      AND rd.roster_week_id = rwsd.roster_week_id
                )
                OR NOT EXISTS (
                    SELECT 1
                    FROM roster_days rd
                    JOIN roster_weeks rw ON rw.id = rd.roster_week_id
                    JOIN shift_types st ON st.id = rs.shift_type_id
                    WHERE rd.id = rs.roster_day_id
                      AND st.venue_id = rw.venue_id
                )
                OR (
                    rs.staff_id IS NOT NULL
                    AND NOT EXISTS (
                        SELECT 1
                        FROM roster_days rd
                        JOIN roster_weeks rw ON rw.id = rd.roster_week_id
                        JOIN staff s ON s.id = rs.staff_id
                        WHERE rd.id = rs.roster_day_id
                          AND s.venue_id = rw.venue_id
                    )
                )
            )
       );

    IF invalid_count <> 0 THEN
        RAISE EXCEPTION 'explicit roster shift assignment preflight failed: % invalid rows remain', invalid_count;
    END IF;
END;
$$;

ALTER TABLE roster_slots
    ALTER COLUMN assignment_state SET NOT NULL;

ALTER TABLE roster_slots
    ADD CONSTRAINT roster_slots_assignment_state_check
        CHECK (assignment_state = 'staff' OR assignment_state = 'open') NOT VALID,
    ADD CONSTRAINT roster_slots_assignment_shape_check
        CHECK (
            (assignment_state = 'staff' AND staff_id IS NOT NULL)
            OR (assignment_state = 'open' AND staff_id IS NULL)
        ) NOT VALID,
    ADD CONSTRAINT roster_slots_active_structure_check
        CHECK (
            deleted_at IS NOT NULL
            OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at > starts_at AND shift_type_id IS NOT NULL)
        ) NOT VALID;

ALTER TABLE roster_slots
    VALIDATE CONSTRAINT roster_slots_assignment_state_check;
ALTER TABLE roster_slots
    VALIDATE CONSTRAINT roster_slots_assignment_shape_check;
ALTER TABLE roster_slots
    VALIDATE CONSTRAINT roster_slots_active_structure_check;

ALTER TABLE roster_slots
    DROP CONSTRAINT roster_slots_staff_id_fkey,
    ADD CONSTRAINT roster_slots_staff_id_fkey
        FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    DROP CONSTRAINT roster_slots_shift_type_id_fkey,
    ADD CONSTRAINT roster_slots_shift_type_id_fkey
        FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT;
