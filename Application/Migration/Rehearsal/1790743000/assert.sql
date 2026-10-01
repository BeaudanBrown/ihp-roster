DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM user_preferences WHERE user_id = 'e2000000-0000-0000-0000-000000000001' AND roster_pay_display_mode = 'roster_pay_hidden' AND NOT show_wage_estimates AND NOT highlight_own_live_shifts AND timesheet_wage_display_mode = 'all_timesheets') THEN
        RAISE EXCEPTION 'Hidden roster preference or unrelated preferences not preserved';
    END IF;
    IF NOT EXISTS (SELECT FROM user_preferences WHERE user_id = 'e2000000-0000-0000-0000-000000000002' AND roster_pay_display_mode = 'roster_pay_daily' AND show_wage_estimates AND highlight_own_live_shifts AND timesheet_wage_display_mode = 'visible_timesheets') THEN
        RAISE EXCEPTION 'Enabled roster preference or unrelated preferences not preserved';
    END IF;
    IF EXISTS (SELECT FROM user_preferences WHERE user_id = 'e2000000-0000-0000-0000-000000000003') THEN
        RAISE EXCEPTION 'Migration unexpectedly initialized absent preferences';
    END IF;
END $$;
INSERT INTO user_preferences (user_id) VALUES ('e2000000-0000-0000-0000-000000000003');
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM user_preferences WHERE user_id = 'e2000000-0000-0000-0000-000000000003' AND roster_pay_display_mode = 'roster_pay_hidden') THEN
        RAISE EXCEPTION 'New roster preference must default to Hidden';
    END IF;
END $$;
