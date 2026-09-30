-- Preserve existing choices: enabled includes daily amounts; disabled stays hidden.
-- Keep the legacy boolean for rollback compatibility. New application writes mirror
-- whether the mode is visible; the new mode alone owns presentation.
CREATE TYPE roster_pay_display_mode AS ENUM ('roster_pay_hidden', 'roster_pay_total', 'roster_pay_daily');
ALTER TABLE user_preferences ADD COLUMN roster_pay_display_mode roster_pay_display_mode DEFAULT 'roster_pay_hidden' NOT NULL;
UPDATE user_preferences SET roster_pay_display_mode = 'roster_pay_daily' WHERE show_wage_estimates;
