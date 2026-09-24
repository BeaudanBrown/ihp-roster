DO $$
BEGIN
    IF (SELECT timesheet_wage_display_mode FROM user_preferences WHERE user_id = 'c2000000-0000-0000-0000-000000000001') <> 'visible_timesheets' THEN
        RAISE EXCEPTION 'worker TRUE preference was not preserved';
    END IF;
    IF (SELECT timesheet_wage_display_mode FROM user_preferences WHERE user_id = 'c2000000-0000-0000-0000-000000000002') <> 'hidden' THEN
        RAISE EXCEPTION 'admin FALSE preference was not preserved as hidden';
    END IF;
    IF EXISTS (
        SELECT 1 FROM user_preferences
        WHERE user_id IN ('c2000000-0000-0000-0000-000000000003', 'c2000000-0000-0000-0000-000000000004')
          AND timesheet_wage_display_mode <> 'hidden'
    ) THEN
        RAISE EXCEPTION 'manager/supervisor dormant preferences became visible';
    END IF;
    IF (SELECT timesheet_wage_display_mode FROM user_preferences WHERE user_id = 'c2000000-0000-0000-0000-000000000005') <> 'visible_timesheets' THEN
        RAISE EXCEPTION 'support TRUE preference was not preserved';
    END IF;
END $$;
