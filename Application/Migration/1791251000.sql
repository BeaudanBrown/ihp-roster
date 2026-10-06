-- Add a roster-only creation default. Existing shifts and Timesheets are untouched.
-- Code rollback may leave this additive column and recorded revision in place.
ALTER TABLE venue_config
    ADD COLUMN default_roster_shift_duration_minutes INT DEFAULT 480 NOT NULL,
    ADD CONSTRAINT venue_config_default_roster_shift_duration_check
        CHECK ((default_roster_shift_duration_minutes >= 15)
            AND ((default_roster_shift_duration_minutes <= 1440)
            AND (mod(default_roster_shift_duration_minutes, 15) = 0)));
