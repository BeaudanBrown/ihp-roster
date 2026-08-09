-- Timesheet wage estimates are an independent, global per-user presentation
-- preference. Existing and new users start with estimates hidden.
ALTER TABLE user_preferences
    ADD COLUMN show_timesheet_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL;
