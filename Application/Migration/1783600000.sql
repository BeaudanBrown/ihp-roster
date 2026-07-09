ALTER TABLE venue_config
    ADD COLUMN IF NOT EXISTS time_picker_start_minute_of_day INT DEFAULT 360 NOT NULL,
    ADD COLUMN IF NOT EXISTS time_picker_final_selectable_minute_of_day INT DEFAULT 345 NOT NULL;

ALTER TABLE venue_config
    DROP CONSTRAINT IF EXISTS venue_config_time_picker_start_minute_of_day_check,
    ADD CONSTRAINT venue_config_time_picker_start_minute_of_day_check
        CHECK ((time_picker_start_minute_of_day >= 0) AND (time_picker_start_minute_of_day < 1440) AND ((time_picker_start_minute_of_day % 15) = 0));

ALTER TABLE venue_config
    DROP CONSTRAINT IF EXISTS venue_config_time_picker_final_selectable_minute_of_day_check,
    ADD CONSTRAINT venue_config_time_picker_final_selectable_minute_of_day_check
        CHECK ((time_picker_final_selectable_minute_of_day >= 0) AND (time_picker_final_selectable_minute_of_day < 1440) AND ((time_picker_final_selectable_minute_of_day % 15) = 0));

ALTER TABLE venue_config
    DROP CONSTRAINT IF EXISTS venue_config_time_picker_window_non_empty_check,
    ADD CONSTRAINT venue_config_time_picker_window_non_empty_check
        CHECK (time_picker_start_minute_of_day <> time_picker_final_selectable_minute_of_day);
