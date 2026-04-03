-- Bootstrap data loaded by `make db` and any environment that applies
-- `Application/Fixtures.sql` during database initialization.
--
-- Keep only deliberate bootstrap rows here. In this repo that includes a
-- deterministic founder login so every `make db` produces a known account
-- for manual testing. The intended bootstrap account is
-- `beaudan.brown@gmail.com`.
--
-- Required rows for that account:
--   1. `users` row with a valid `password_hash`
--   2. active `venue_memberships` row in the default dev venue with
--      `venue_role = 'venue_owner'` or `venue_role = 'venue_admin'`
--   3. optional linked `staff` row if roster/profile flows should work
--
-- Generate the password hash with:
--   bash ./bin/in-env hash-password
--
-- Do not rely on `users.user_role = 'admin'` for this bootstrap login.
-- App authority is venue-scoped today, so the seeded membership role is
-- what grants admin access.
--
-- Future product note: a true cross-venue "super admin" / platform-admin
-- should be modelled as a separate capability for the founder sysadmin
-- account, not by overloading venue roles.

-- Default venue for development
INSERT INTO venues (id, name, status) VALUES
('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Dev Venue', 'active');

-- Venue config (one per venue)
INSERT INTO venue_config (venue_id, timezone, week_offset_epoch, late_to_early_min_start_gap_minutes)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'UTC', DATE '2025-01-06', 600);

INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default) VALUES
('a0a0a0a0-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Main', 0, true, true);

-- Founder bootstrap login for manual testing after `make db`
INSERT INTO users (id, email, password_hash, user_role, platform_role, is_profile_completed, failed_login_attempts, locked_at) VALUES
('b0000000-0000-0000-0000-000000000001', 'beaudan.brown@gmail.com', 'sha256|17|QsCg6vyI99zgdc8d6k9CAQ==|U17VHHhZnBKByPfiHkrPH16BdDQaND55Uq8Ubbku/cQ=', 'staff', 'super_admin', true, 0, NULL);

INSERT INTO venue_memberships (id, venue_id, user_id, venue_role, is_active) VALUES
('b1000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b0000000-0000-0000-0000-000000000001', 'venue_owner', true);

INSERT INTO staff (id, venue_id, user_id, first_name, last_name, preferred_name, phone, emergency_contact_name, emergency_contact_phone, ideal_shifts_per_week, is_active) VALUES
('b2000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'b0000000-0000-0000-0000-000000000001', 'Beau', 'Brown', NULL, '0400000000', 'Emergency Contact', '0411111111', 0, true);

-- Pay Levels
INSERT INTO pay_levels (id, venue_id, name, is_active) VALUES
('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Standard Level 1', true),
('22222222-2222-2222-2222-222222222222', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Supervisor Level 2', true);

-- Shift Types
INSERT INTO shift_types (id, venue_id, name, default_pay_level_id, is_active) VALUES
('33333333-3333-3333-3333-333333333333', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Ordinary', '11111111-1111-1111-1111-111111111111', true),
('44444444-4444-4444-4444-444444444444', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Management', '22222222-2222-2222-2222-222222222222', true);

-- Slot Names
INSERT INTO slot_names (id, venue_id, roster_group_id, name, is_active) VALUES
('55555555-5555-5555-5555-555555555555', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a0a0a0a0-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Early', true),
('66666666-6666-6666-6666-666666666666', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a0a0a0a0-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Mid', true),
('77777777-7777-7777-7777-777777777777', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'a0a0a0a0-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Late', true);

INSERT INTO day_names (id, venue_id, weekday_index, name, is_active) VALUES
('d1000000-0000-0000-0000-000000000001', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1, 'Monday', true),
('d1000000-0000-0000-0000-000000000002', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 2, 'Tuesday', true),
('d1000000-0000-0000-0000-000000000003', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 3, 'Wednesday', true),
('d1000000-0000-0000-0000-000000000004', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 4, 'Thursday', true),
('d1000000-0000-0000-0000-000000000005', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 5, 'Friday', true),
('d1000000-0000-0000-0000-000000000006', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 6, 'Saturday', true),
('d1000000-0000-0000-0000-000000000007', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 0, 'Sunday', true);
