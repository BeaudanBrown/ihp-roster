-- Preserve every deployed user's current Timesheets choices. The marker lets
-- preference rows created after this migration receive first-visit defaults
-- even when another feature created the shared row first.
ALTER TABLE user_preferences
    ADD COLUMN timesheet_preferences_initialized_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

UPDATE user_preferences
SET timesheet_preferences_initialized_at = NOW()
WHERE timesheet_preferences_initialized_at IS NULL;

ALTER TABLE user_preferences
    ALTER COLUMN hide_approved SET DEFAULT FALSE,
    ALTER COLUMN show_timesheet_suggestions SET DEFAULT TRUE,
    ALTER COLUMN show_timesheet_wage_estimates SET DEFAULT TRUE;
