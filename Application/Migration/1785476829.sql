-- Optional venue-wide manager warning threshold for unavailable staff.
-- NULL keeps warnings disabled for all existing and new venues.
ALTER TABLE venue_config
    ADD COLUMN unavailable_staff_warning_threshold INT DEFAULT NULL;

ALTER TABLE venue_config
    ADD CONSTRAINT venue_config_unavailable_staff_warning_threshold_check
    CHECK (
        unavailable_staff_warning_threshold IS NULL
        OR unavailable_staff_warning_threshold BETWEEN 1 AND 100
    ) NOT VALID;

ALTER TABLE venue_config
    VALIDATE CONSTRAINT venue_config_unavailable_staff_warning_threshold_check;

-- Rollback: DROP CONSTRAINT venue_config_unavailable_staff_warning_threshold_check,
-- then DROP COLUMN unavailable_staff_warning_threshold. No customer data is modified.
