ALTER TABLE roster_slots
    DROP CONSTRAINT IF EXISTS roster_slots_note_check;

ALTER TABLE roster_slots
    DROP COLUMN IF EXISTS note;
