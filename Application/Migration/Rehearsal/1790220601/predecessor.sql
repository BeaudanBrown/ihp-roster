INSERT INTO venues (id, name) VALUES
    ('c1000000-0000-0000-0000-000000000001', 'Wage Display Migration Venue');

INSERT INTO users (id, email, password_hash, platform_role) VALUES
    ('c2000000-0000-0000-0000-000000000001', 'worker-visible@example.test', 'synthetic', NULL),
    ('c2000000-0000-0000-0000-000000000002', 'admin-hidden@example.test', 'synthetic', NULL),
    ('c2000000-0000-0000-0000-000000000003', 'manager-dormant@example.test', 'synthetic', NULL),
    ('c2000000-0000-0000-0000-000000000004', 'supervisor-dormant@example.test', 'synthetic', NULL),
    ('c2000000-0000-0000-0000-000000000005', 'support-visible@example.test', 'synthetic', 'super_admin');

INSERT INTO venue_memberships (venue_id, user_id, venue_role) VALUES
    ('c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000001', 'worker'),
    ('c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'venue_admin'),
    ('c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000003', 'manager'),
    ('c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000004', 'supervisor');

INSERT INTO user_preferences (user_id, show_timesheet_wage_estimates) VALUES
    ('c2000000-0000-0000-0000-000000000001', TRUE),
    ('c2000000-0000-0000-0000-000000000002', FALSE),
    ('c2000000-0000-0000-0000-000000000003', TRUE),
    ('c2000000-0000-0000-0000-000000000004', TRUE),
    ('c2000000-0000-0000-0000-000000000005', TRUE);
