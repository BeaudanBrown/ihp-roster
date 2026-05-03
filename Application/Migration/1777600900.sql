ALTER TABLE roster_days
    ADD COLUMN IF NOT EXISTS row_count INT DEFAULT 4 NOT NULL;

UPDATE roster_days
SET row_count = GREATEST(
        4,
        COALESCE((
            SELECT MAX(roster_slots.row_index) + 1
            FROM roster_slots
            WHERE roster_slots.roster_day_id = roster_days.id
              AND roster_slots.deleted_at IS NULL
        ), 0)
    );

ALTER TABLE roster_days
    DROP CONSTRAINT IF EXISTS roster_days_row_count_check,
    ADD CONSTRAINT roster_days_row_count_check CHECK (row_count >= 0);

UPDATE roster_slots
SET deleted_at = NOW(),
    delete_reason = 'blank_slot_removed',
    updated_at = NOW()
WHERE deleted_at IS NULL
  AND staff_id IS NULL
  AND start_time IS NULL
  AND end_time IS NULL
  AND shift_type_id IS NULL
  AND duration_minutes IS NULL
  AND (note IS NULL OR btrim(note) = '');
