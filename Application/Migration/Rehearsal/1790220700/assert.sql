DO $$
DECLARE
    worker_value BOOLEAN;
    admin_value BOOLEAN;
    manager_value BOOLEAN;
    support_value BOOLEAN;
    archived_admin_value BOOLEAN;
    owner_value BOOLEAN;
BEGIN
    SELECT show_wage_estimates INTO worker_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000001';
    SELECT show_wage_estimates INTO admin_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000002';
    SELECT show_wage_estimates INTO manager_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000003';
    SELECT show_wage_estimates INTO support_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000004';
    SELECT show_wage_estimates INTO archived_admin_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000005';
    SELECT show_wage_estimates INTO owner_value FROM user_preferences WHERE user_id = 'd2000000-0000-0000-0000-000000000006';

    IF worker_value OR manager_value OR archived_admin_value THEN
        RAISE EXCEPTION 'roster wage preference migration retained dormant unauthorized choices';
    END IF;
    IF NOT admin_value OR NOT support_value OR NOT owner_value THEN
        RAISE EXCEPTION 'roster wage preference migration discarded authorized choices';
    END IF;
END $$;
