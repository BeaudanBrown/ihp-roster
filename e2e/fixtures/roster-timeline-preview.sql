-- Fictional, roster-only schedule for populated layout/overlap screenshots.
-- The a6500000 namespace is owned exclusively by this disposable E2E fixture.
INSERT INTO staff (id, venue_id, first_name, last_name, phone, emergency_contact_name, emergency_contact_phone)
SELECT ('a6500000-0000-0000-0000-' || lpad((100 + n)::text, 12, '0'))::uuid,
       'a1000000-0000-0000-0000-000000000001', first_name, last_name,
       '0400000000', 'Fixture contact', '0400000000'
FROM (VALUES
    (1, 'Avery', 'Lane'), (2, 'Blake', 'Reed'), (3, 'Casey', 'Park'),
    (4, 'Drew', 'Stone'), (5, 'Elliot', 'Vale'), (6, 'Frankie', 'Wren'),
    (7, 'Gray', 'West'), (8, 'Harper', 'Lake')
) AS people(n, first_name, last_name)
ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

INSERT INTO staff_roster_groups (staff_id, roster_group_id)
SELECT id, 'a1000000-0000-0000-0000-000000000211'
FROM staff WHERE id::text LIKE 'a6500000-%'
ON CONFLICT DO NOTHING;

INSERT INTO shift_types (id, venue_id, name, colour_key, pay_assignment_mode)
VALUES
    ('a6500000-0000-0000-0000-000000000301', 'a1000000-0000-0000-0000-000000000001', 'Floor service', 'palette_2', 'roster_only'),
    ('a6500000-0000-0000-0000-000000000302', 'a1000000-0000-0000-0000-000000000001', 'Bar service', 'palette_4', 'roster_only'),
    ('a6500000-0000-0000-0000-000000000303', 'a1000000-0000-0000-0000-000000000001', 'Kitchen prep', 'palette_7', 'roster_only')
ON CONFLICT (id) DO UPDATE SET is_active = TRUE;

INSERT INTO roster_days (id, venue_id, roster_group_id, operational_date, row_count)
VALUES ('a6500000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', '2027-06-14', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO roster_lanes (id, roster_day_id, name, sort_order)
SELECT ('a6500000-0000-0000-0000-' || lpad((200 + n)::text, 12, '0'))::uuid,
       'a6500000-0000-0000-0000-000000000001', name, n - 1
FROM (VALUES (1, 'Floor'), (2, 'Bar'), (3, 'Kitchen'), (4, 'Terrace'), (5, 'Events')) AS lanes(n, name)
ON CONFLICT (id) DO UPDATE SET deleted_at = NULL;

INSERT INTO roster_slots (id, roster_day_id, roster_lane_id, staff_id, assignment_state, row_index, starts_at, ends_at, timezone, shift_type_id)
SELECT ('a6500000-0000-0000-0000-' || lpad((400 + n)::text, 12, '0'))::uuid,
       'a6500000-0000-0000-0000-000000000001',
       ('a6500000-0000-0000-0000-' || lpad((200 + lane)::text, 12, '0'))::uuid,
       CASE WHEN person IS NULL THEN NULL ELSE ('a6500000-0000-0000-0000-' || lpad((100 + person)::text, 12, '0'))::uuid END,
       CASE WHEN person IS NULL THEN 'open' ELSE 'staff' END,
       row_index,
       (DATE '2027-06-14' + starts_at::time) AT TIME ZONE 'Australia/Melbourne',
       (DATE '2027-06-14' + ends_at::time) AT TIME ZONE 'Australia/Melbourne',
       'Australia/Melbourne',
       ('a6500000-0000-0000-0000-' || lpad((300 + role)::text, 12, '0'))::uuid
FROM (VALUES
    (1, 1, 1, 0, '08:00', '14:00', 1),
    (2, 1, 2, 1, '09:00', '12:00', 1),
    (3, 1, NULL, 2, '16:00', '23:00', 1),
    (4, 2, 3, 0, '07:00', '13:00', 2),
    (5, 2, 4, 1, '11:00', '17:00', 2),
    (6, 2, NULL, 2, '17:00', '23:00', 2),
    (7, 3, 5, 0, '06:00', '12:00', 3),
    (8, 3, 6, 1, '10:00', '16:00', 3),
    (9, 3, 7, 2, '16:00', '22:00', 3),
    (10, 4, NULL, 0, '08:00', '11:00', 1),
    (11, 4, 8, 1, '12:00', '16:00', 1),
    (12, 4, NULL, 2, '16:00', '19:00', 1)
) AS shifts(n, lane, person, row_index, starts_at, ends_at, role)
ON CONFLICT (id) DO UPDATE SET deleted_at = NULL;
