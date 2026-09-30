INSERT INTO users (id, email, password_hash) VALUES
    ('e2000000-0000-0000-0000-000000000001', 'pay-hidden@example.test', 'synthetic'),
    ('e2000000-0000-0000-0000-000000000002', 'pay-daily@example.test', 'synthetic'),
    ('e2000000-0000-0000-0000-000000000003', 'pay-new@example.test', 'synthetic');
INSERT INTO user_preferences (user_id, show_wage_estimates, highlight_own_live_shifts, timesheet_wage_display_mode) VALUES
    ('e2000000-0000-0000-0000-000000000001', FALSE, FALSE, 'all_timesheets'),
    ('e2000000-0000-0000-0000-000000000002', TRUE, TRUE, 'visible_timesheets');
