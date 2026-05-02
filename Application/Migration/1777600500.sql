ALTER TABLE timesheet_entries
    ADD COLUMN IF NOT EXISTS staff_comment TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS manager_note TEXT DEFAULT NULL;

ALTER TABLE timesheet_entries
    DROP CONSTRAINT IF EXISTS timesheet_entries_staff_comment_check,
    DROP CONSTRAINT IF EXISTS timesheet_entries_manager_note_check,
    DROP CONSTRAINT IF EXISTS timesheet_entries_staff_comment_length_check,
    DROP CONSTRAINT IF EXISTS timesheet_entries_manager_note_length_check;

ALTER TABLE timesheet_entries
    ADD CONSTRAINT timesheet_entries_staff_comment_length_check CHECK (staff_comment IS NULL OR char_length(staff_comment) <= 1000),
    ADD CONSTRAINT timesheet_entries_manager_note_length_check CHECK (manager_note IS NULL OR char_length(manager_note) <= 1000);
