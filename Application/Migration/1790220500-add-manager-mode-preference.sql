-- One global user preference shared by Roster and Timesheets. Existing and
-- missing preference rows both resolve to enabled by default.
ALTER TABLE user_preferences
    ADD COLUMN manager_mode_enabled BOOLEAN DEFAULT TRUE NOT NULL;
