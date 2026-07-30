-- Add bounded, optional feedback diagnostics without changing legacy rows.
ALTER TABLE user_feedback_items
    ADD COLUMN submitted_role TEXT DEFAULT NULL,
    ADD COLUMN viewport_width INTEGER DEFAULT NULL,
    ADD COLUMN viewport_height INTEGER DEFAULT NULL,
    ADD COLUMN device_pixel_ratio DOUBLE PRECISION DEFAULT NULL,
    ADD COLUMN device_class TEXT DEFAULT NULL,
    ADD COLUMN display_mode TEXT DEFAULT NULL;

-- Do not rewrite exceptional legacy diagnostics. NOT VALID preserves every
-- existing row while PostgreSQL enforces these bounds for new/updated rows.
ALTER TABLE user_feedback_items
    ADD CONSTRAINT user_feedback_items_submitted_path_length_check
        CHECK (submitted_path IS NULL OR ((char_length(submitted_path) > 0) AND (char_length(submitted_path) <= 500))) NOT VALID,
    ADD CONSTRAINT user_feedback_items_user_agent_length_check
        CHECK (user_agent IS NULL OR char_length(user_agent) <= 500) NOT VALID,
    ADD CONSTRAINT user_feedback_items_submitted_role_check
        CHECK (submitted_role IS NULL OR (submitted_role = 'worker') OR (submitted_role = 'supervisor') OR (submitted_role = 'manager') OR (submitted_role = 'venue_admin') OR (submitted_role = 'venue_owner') OR (submitted_role = 'support_super_admin')) NOT VALID,
    ADD CONSTRAINT user_feedback_items_viewport_width_check
        CHECK (viewport_width IS NULL OR ((viewport_width >= 1) AND (viewport_width <= 10000))) NOT VALID,
    ADD CONSTRAINT user_feedback_items_viewport_height_check
        CHECK (viewport_height IS NULL OR ((viewport_height >= 1) AND (viewport_height <= 10000))) NOT VALID,
    ADD CONSTRAINT user_feedback_items_device_pixel_ratio_check
        CHECK (device_pixel_ratio IS NULL OR ((device_pixel_ratio > 0) AND (device_pixel_ratio <= 100))) NOT VALID,
    ADD CONSTRAINT user_feedback_items_device_class_check
        CHECK (device_class IS NULL OR (device_class = 'mobile') OR (device_class = 'desktop')) NOT VALID,
    ADD CONSTRAINT user_feedback_items_display_mode_check
        CHECK (display_mode IS NULL OR (display_mode = 'browser') OR (display_mode = 'standalone')) NOT VALID;
