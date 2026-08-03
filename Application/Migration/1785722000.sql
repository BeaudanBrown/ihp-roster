ALTER TABLE venue_config
    ADD COLUMN IF NOT EXISTS minute_precision_shift_times_enabled BOOLEAN DEFAULT FALSE NOT NULL;
