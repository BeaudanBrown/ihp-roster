INSERT INTO venues (id, name) VALUES
    ('d1000000-0000-0000-0000-000000000001', 'Roster Wage Migration Venue');

INSERT INTO users (id, email, password_hash, platform_role) VALUES
    ('d2000000-0000-0000-0000-000000000001', 'worker-roster-wage@example.test', 'synthetic', NULL),
    ('d2000000-0000-0000-0000-000000000002', 'admin-roster-wage@example.test', 'synthetic', NULL),
    ('d2000000-0000-0000-0000-000000000003', 'manager-roster-wage@example.test', 'synthetic', NULL),
    ('d2000000-0000-0000-0000-000000000004', 'support-roster-wage@example.test', 'synthetic', 'super_admin'),
    ('d2000000-0000-0000-0000-000000000005', 'archived-admin-roster-wage@example.test', 'synthetic', NULL),
    ('d2000000-0000-0000-0000-000000000006', 'owner-roster-wage@example.test', 'synthetic', NULL);

INSERT INTO venue_memberships (venue_id, user_id, venue_role, is_active, archived_at) VALUES
    ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'worker', TRUE, NULL),
    ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000002', 'venue_admin', TRUE, NULL),
    ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000003', 'manager', TRUE, NULL),
    ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000005', 'venue_admin', FALSE, NOW()),
    ('d1000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000006', 'venue_owner', TRUE, NULL);

INSERT INTO user_preferences (user_id, show_wage_estimates) VALUES
    ('d2000000-0000-0000-0000-000000000001', TRUE),
    ('d2000000-0000-0000-0000-000000000002', TRUE),
    ('d2000000-0000-0000-0000-000000000003', TRUE),
    ('d2000000-0000-0000-0000-000000000004', TRUE),
    ('d2000000-0000-0000-0000-000000000005', TRUE),
    ('d2000000-0000-0000-0000-000000000006', TRUE);
