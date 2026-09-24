-- Synthetic historical Timesheets for deterministic roster-group classification.
INSERT INTO venues (id, name) VALUES
    ('b1000000-0000-0000-0000-000000000001', 'Classification Venue');

INSERT INTO staff (
    id, venue_id, first_name, last_name, phone,
    emergency_contact_name, emergency_contact_phone
) VALUES
    ('b2000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Multiple', 'Groups', 'synthetic', 'Synthetic', 'synthetic'),
    ('b2000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'No', 'Groups', 'synthetic', 'Synthetic', 'synthetic');

INSERT INTO shift_types (id, venue_id, name) VALUES
    ('b3000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'Synthetic Shift');

INSERT INTO roster_groups (id, venue_id, name, sort_order) VALUES
    ('b4000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'First Group', 10),
    ('b4000000-0000-0000-0000-000000000002', 'b1000000-0000-0000-0000-000000000001', 'Source Group', 20);

INSERT INTO staff_roster_groups (staff_id, roster_group_id) VALUES
    ('b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000002'),
    ('b2000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001');

INSERT INTO roster_days (id, venue_id, roster_group_id, operational_date) VALUES
    ('b5000000-0000-0000-0000-000000000001', 'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000002', DATE '2025-01-06');

INSERT INTO roster_lanes (id, roster_day_id, name) VALUES
    ('b6000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001', 'Synthetic Lane');

INSERT INTO roster_slots (
    id, roster_day_id, roster_lane_id, assignment_state, staff_id,
    row_index, starts_at, ends_at, timezone, shift_type_id
) VALUES (
    'b7000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000001',
    'staff',
    'b2000000-0000-0000-0000-000000000001',
    0,
    TIMESTAMPTZ '2025-01-05 22:00:00+00',
    TIMESTAMPTZ '2025-01-06 06:00:00+00',
    'Australia/Melbourne',
    'b3000000-0000-0000-0000-000000000001'
);

INSERT INTO timesheet_entries (
    id, venue_id, staff_id, shift_type_id, starts_at, ends_at,
    timezone, operational_date, source_roster_slot_id, staff_comment
) VALUES
    (
        'b8000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001',
        'b2000000-0000-0000-0000-000000000001',
        'b3000000-0000-0000-0000-000000000001',
        TIMESTAMPTZ '2025-01-05 22:00:00+00', TIMESTAMPTZ '2025-01-06 06:00:00+00',
        'Australia/Melbourne', DATE '2025-01-06',
        'b7000000-0000-0000-0000-000000000001', 'preserve-linked'
    ),
    (
        'b8000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000001',
        'b2000000-0000-0000-0000-000000000001',
        'b3000000-0000-0000-0000-000000000001',
        TIMESTAMPTZ '2025-01-06 22:00:00+00', TIMESTAMPTZ '2025-01-07 06:00:00+00',
        'Australia/Melbourne', DATE '2025-01-07', NULL, 'preserve-membership'
    ),
    (
        'b8000000-0000-0000-0000-000000000003',
        'b1000000-0000-0000-0000-000000000001',
        'b2000000-0000-0000-0000-000000000002',
        'b3000000-0000-0000-0000-000000000001',
        TIMESTAMPTZ '2025-01-07 22:00:00+00', TIMESTAMPTZ '2025-01-08 06:00:00+00',
        'Australia/Melbourne', DATE '2025-01-08', NULL, 'preserve-none'
    );
