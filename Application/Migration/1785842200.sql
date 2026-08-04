ALTER TABLE user_preferences
    ADD COLUMN highlight_own_live_shifts BOOLEAN DEFAULT TRUE NOT NULL;
