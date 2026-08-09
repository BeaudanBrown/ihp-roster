ALTER TABLE venue_config
    ADD COLUMN roster_layout_mode roster_layout_mode_enum DEFAULT 'day_columns' NOT NULL,
    ADD COLUMN default_staff_pay_assignment_mode pay_assignment_mode_enum DEFAULT 'roster_only' NOT NULL,
    ADD COLUMN default_staff_award_level_id UUID DEFAULT NULL;

ALTER TABLE venue_config
    ADD CONSTRAINT venue_config_default_staff_pay_assignment_check CHECK (
        (default_staff_pay_assignment_mode = 'award_rate' AND default_staff_award_level_id IS NOT NULL)
        OR (default_staff_pay_assignment_mode = 'roster_only' AND default_staff_award_level_id IS NULL)
    ),
    ADD CONSTRAINT venue_config_default_staff_award_level_id_fk
        FOREIGN KEY (default_staff_award_level_id) REFERENCES award_levels (id) ON DELETE RESTRICT;
