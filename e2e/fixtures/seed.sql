-- Seed data for e2e tests.
-- All test data uses fixed ids and/or the 'e2e-' prefix to stay idempotent.
-- Password for this user is: test-password-123

-- Reset mutable venue-scoped test data so repeated runs start from the same roster state.
DELETE FROM export_jobs
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM timesheet_entries
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM leave_requests
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM pay_config_snapshots
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM report_definition_shift_type_filters
WHERE report_definition_id IN (
    SELECT id
    FROM report_definitions
    WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM report_definitions
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM pay_level_day_rules
WHERE shift_type_id IN (
    SELECT id
    FROM shift_types
    WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM day_names
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM staff_availability
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM roster_slots
WHERE roster_day_id IN (
    SELECT rd.id
    FROM roster_days rd
    JOIN roster_weeks rw ON rw.id = rd.roster_week_id
    WHERE rw.venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM roster_days
WHERE roster_week_id IN (
    SELECT id
    FROM roster_weeks
    WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM roster_weeks
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM shift_types
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM pay_levels
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

INSERT INTO venues (id, name, status)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'e2e-alpha-venue', 'active'),
    ('a1000000-0000-0000-0000-000000000002', 'e2e-beta-venue', 'active')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status;

INSERT INTO venue_config (id, venue_id, timezone, week_offset_epoch, late_to_early_min_start_gap_minutes, staff_timesheet_edit_window_days)
VALUES
    (
        'a1000000-0000-0000-0000-000000000011',
        'a1000000-0000-0000-0000-000000000001',
        'UTC',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        600,
        7
    ),
    (
        'a1000000-0000-0000-0000-000000000012',
        'a1000000-0000-0000-0000-000000000002',
        'UTC',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        600,
        7
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    timezone = EXCLUDED.timezone,
    week_offset_epoch = EXCLUDED.week_offset_epoch,
    late_to_early_min_start_gap_minutes = EXCLUDED.late_to_early_min_start_gap_minutes,
    staff_timesheet_edit_window_days = EXCLUDED.staff_timesheet_edit_window_days;

INSERT INTO users (id, email, password_hash, user_role, platform_role, is_profile_completed, failed_login_attempts)
VALUES
    (
        'a0000000-0000-0000-0000-000000000001',
        'e2e-test@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        NULL,
        TRUE,
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000003',
        'e2e-admin@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'admin',
        NULL,
        TRUE,
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000002',
        'e2e-worker@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'staff',
        NULL,
        TRUE,
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000004',
        'e2e-super-admin@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        'super_admin',
        TRUE,
        0
    )
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    user_role = EXCLUDED.user_role,
    platform_role = EXCLUDED.platform_role,
    is_profile_completed = EXCLUDED.is_profile_completed,
    failed_login_attempts = EXCLUDED.failed_login_attempts,
    locked_at = NULL;

INSERT INTO venue_memberships (id, venue_id, user_id, venue_role, is_active, created_at, updated_at)
VALUES
    (
        'a1000000-0000-0000-0000-000000000021',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        'manager',
        TRUE,
        '2025-01-01 00:00:00+00',
        '2025-01-01 00:00:00+00'
    ),
    (
        'a1000000-0000-0000-0000-000000000022',
        'a1000000-0000-0000-0000-000000000002',
        'a0000000-0000-0000-0000-000000000001',
        'manager',
        TRUE,
        '2025-01-02 00:00:00+00',
        '2025-01-02 00:00:00+00'
    ),
    (
        'a1000000-0000-0000-0000-000000000023',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000002',
        'worker',
        TRUE,
        '2025-01-03 00:00:00+00',
        '2025-01-03 00:00:00+00'
    ),
    (
        'a1000000-0000-0000-0000-000000000024',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000003',
        'venue_admin',
        TRUE,
        '2025-01-04 00:00:00+00',
        '2025-01-04 00:00:00+00'
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    user_id = EXCLUDED.user_id,
    venue_role = EXCLUDED.venue_role,
    is_active = EXCLUDED.is_active,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at;

INSERT INTO staff (id, venue_id, user_id, first_name, last_name, phone, emergency_contact_name, emergency_contact_phone, ideal_shifts_per_week, is_active)
VALUES
    (
        'a0000000-0000-0000-0000-000000000101',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        'E2E',
        'Manager',
        '0400000001',
        'Emergency Manager',
        '0400000101',
        0,
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000002',
        'Alpha',
        'Crew',
        '0400000002',
        'Emergency Alpha',
        '0400000102',
        0,
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000033',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000003',
        'Admin',
        'Crew',
        '0400000003',
        'Emergency Admin',
        '0400000103',
        0,
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000002',
        NULL,
        'Beta',
        'Crew',
        '0400000004',
        'Emergency Beta',
        '0400000104',
        0,
        TRUE
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    user_id = EXCLUDED.user_id,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    phone = EXCLUDED.phone,
    emergency_contact_name = EXCLUDED.emergency_contact_name,
    emergency_contact_phone = EXCLUDED.emergency_contact_phone,
    ideal_shifts_per_week = EXCLUDED.ideal_shifts_per_week,
    is_active = EXCLUDED.is_active;

INSERT INTO pay_levels (
    id,
    venue_id,
    name,
    base_rate,
    evening_penalty,
    after_12_penalty,
    weekday_multiplier,
    saturday_multiplier,
    sunday_multiplier,
    is_active
)
VALUES
    ('a1000000-0000-0000-0000-000000000111', 'a1000000-0000-0000-0000-000000000001', 'LVL 1', 30.00, 0.00, 0.00, 1.250, 1.500, 1.750, TRUE),
    ('a1000000-0000-0000-0000-000000000112', 'a1000000-0000-0000-0000-000000000001', 'LVL 2', 35.00, 0.00, 0.00, 1.250, 1.500, 1.750, TRUE),
    ('a1000000-0000-0000-0000-000000000113', 'a1000000-0000-0000-0000-000000000001', 'Floor Level', 28.00, 0.00, 0.00, 1.250, 1.500, 1.750, TRUE),
    ('a1000000-0000-0000-0000-000000000121', 'a1000000-0000-0000-0000-000000000002', 'Beta Level', 27.00, 0.00, 0.00, 1.100, 1.250, 1.500, TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    base_rate = EXCLUDED.base_rate,
    evening_penalty = EXCLUDED.evening_penalty,
    after_12_penalty = EXCLUDED.after_12_penalty,
    weekday_multiplier = EXCLUDED.weekday_multiplier,
    saturday_multiplier = EXCLUDED.saturday_multiplier,
    sunday_multiplier = EXCLUDED.sunday_multiplier,
    is_active = EXCLUDED.is_active;

INSERT INTO shift_types (id, venue_id, name, sort_order, default_pay_level_id, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000131', 'a1000000-0000-0000-0000-000000000001', 'Bar', 10, 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000132', 'a1000000-0000-0000-0000-000000000001', 'Kitchen', 20, 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000133', 'a1000000-0000-0000-0000-000000000001', 'Floor', 30, 'a1000000-0000-0000-0000-000000000113', TRUE),
    ('a1000000-0000-0000-0000-000000000141', 'a1000000-0000-0000-0000-000000000002', 'Beta Shift', 10, 'a1000000-0000-0000-0000-000000000121', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    default_pay_level_id = EXCLUDED.default_pay_level_id,
    is_active = EXCLUDED.is_active;

INSERT INTO day_names (id, venue_id, weekday_index, name, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000151', 'a1000000-0000-0000-0000-000000000001', 1, 'Monday', TRUE),
    ('a1000000-0000-0000-0000-000000000152', 'a1000000-0000-0000-0000-000000000001', 2, 'Tuesday', TRUE),
    ('a1000000-0000-0000-0000-000000000153', 'a1000000-0000-0000-0000-000000000001', 3, 'Wednesday', TRUE),
    ('a1000000-0000-0000-0000-000000000154', 'a1000000-0000-0000-0000-000000000001', 4, 'Thursday', TRUE),
    ('a1000000-0000-0000-0000-000000000155', 'a1000000-0000-0000-0000-000000000001', 5, 'Friday', TRUE),
    ('a1000000-0000-0000-0000-000000000156', 'a1000000-0000-0000-0000-000000000001', 6, 'Saturday', TRUE),
    ('a1000000-0000-0000-0000-000000000157', 'a1000000-0000-0000-0000-000000000001', 0, 'Sunday', TRUE),
    ('a1000000-0000-0000-0000-000000000161', 'a1000000-0000-0000-0000-000000000002', 1, 'Monday', TRUE),
    ('a1000000-0000-0000-0000-000000000162', 'a1000000-0000-0000-0000-000000000002', 2, 'Tuesday', TRUE),
    ('a1000000-0000-0000-0000-000000000163', 'a1000000-0000-0000-0000-000000000002', 3, 'Wednesday', TRUE),
    ('a1000000-0000-0000-0000-000000000164', 'a1000000-0000-0000-0000-000000000002', 4, 'Thursday', TRUE),
    ('a1000000-0000-0000-0000-000000000165', 'a1000000-0000-0000-0000-000000000002', 5, 'Friday', TRUE),
    ('a1000000-0000-0000-0000-000000000166', 'a1000000-0000-0000-0000-000000000002', 6, 'Saturday', TRUE),
    ('a1000000-0000-0000-0000-000000000167', 'a1000000-0000-0000-0000-000000000002', 0, 'Sunday', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    weekday_index = EXCLUDED.weekday_index,
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

INSERT INTO pay_level_day_rules (id, shift_type_id, day_name_id, pay_level_id)
VALUES
    ('a1000000-0000-0000-0000-000000000171', 'a1000000-0000-0000-0000-000000000131', 'a1000000-0000-0000-0000-000000000155', 'a1000000-0000-0000-0000-000000000112')
ON CONFLICT (id) DO UPDATE SET
    shift_type_id = EXCLUDED.shift_type_id,
    day_name_id = EXCLUDED.day_name_id,
    pay_level_id = EXCLUDED.pay_level_id;

INSERT INTO pay_config_snapshots (id, venue_id, version_number, version_label, created_by_user_id, snapshot)
VALUES
    (
        'a1000000-0000-0000-0000-000000000181',
        'a1000000-0000-0000-0000-000000000001',
        1,
        'v1',
        'a0000000-0000-0000-0000-000000000003',
        jsonb_build_object(
            'venueConfig', jsonb_build_object(
                'id', 'a1000000-0000-0000-0000-000000000011',
                'timezone', 'UTC',
                'weekOffsetEpoch', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)),
                'lateToEarlyMinStartGapMinutes', 600,
                'staffTimesheetEditWindowDays', 7
            ),
            'payLevels', jsonb_build_array(
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000111', 'name', 'LVL 1', 'baseRate', 30.00, 'eveningPenalty', 0.00, 'after12Penalty', 0.00, 'weekdayMultiplier', 1.250, 'saturdayMultiplier', 1.500, 'sundayMultiplier', 1.750, 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000112', 'name', 'LVL 2', 'baseRate', 35.00, 'eveningPenalty', 0.00, 'after12Penalty', 0.00, 'weekdayMultiplier', 1.250, 'saturdayMultiplier', 1.500, 'sundayMultiplier', 1.750, 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000113', 'name', 'Floor Level', 'baseRate', 28.00, 'eveningPenalty', 0.00, 'after12Penalty', 0.00, 'weekdayMultiplier', 1.250, 'saturdayMultiplier', 1.500, 'sundayMultiplier', 1.750, 'isActive', TRUE)
            ),
            'shiftTypes', jsonb_build_array(
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000131', 'name', 'Bar', 'defaultPayLevelId', 'a1000000-0000-0000-0000-000000000111', 'sortOrder', 10, 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000132', 'name', 'Kitchen', 'defaultPayLevelId', 'a1000000-0000-0000-0000-000000000111', 'sortOrder', 20, 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000133', 'name', 'Floor', 'defaultPayLevelId', 'a1000000-0000-0000-0000-000000000113', 'sortOrder', 30, 'isActive', TRUE)
            ),
            'dayNames', jsonb_build_array(
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000151', 'weekdayIndex', 1, 'name', 'Monday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000152', 'weekdayIndex', 2, 'name', 'Tuesday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000153', 'weekdayIndex', 3, 'name', 'Wednesday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000154', 'weekdayIndex', 4, 'name', 'Thursday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000155', 'weekdayIndex', 5, 'name', 'Friday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000156', 'weekdayIndex', 6, 'name', 'Saturday', 'isActive', TRUE),
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000157', 'weekdayIndex', 0, 'name', 'Sunday', 'isActive', TRUE)
            ),
            'payLevelDayRules', jsonb_build_array(
                jsonb_build_object('id', 'a1000000-0000-0000-0000-000000000171', 'shiftTypeId', 'a1000000-0000-0000-0000-000000000131', 'dayNameId', 'a1000000-0000-0000-0000-000000000155', 'payLevelId', 'a1000000-0000-0000-0000-000000000112')
            )
        )
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    version_number = EXCLUDED.version_number,
    version_label = EXCLUDED.version_label,
    created_by_user_id = EXCLUDED.created_by_user_id,
    snapshot = EXCLUDED.snapshot;

INSERT INTO report_definitions (id, venue_id, slug, name, description, engine, sort_order, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000191', 'a1000000-0000-0000-0000-000000000001', 'wage', 'Wage Report', 'Hourly staff count breakdown per day (ZIP of CSVs)', 'hourly_breakdown_zip', 10, TRUE),
    ('a1000000-0000-0000-0000-000000000192', 'a1000000-0000-0000-0000-000000000001', 'staff_hours', 'Staff Hours Report', 'Staff hours broken down by pay level and day', 'staff_pay_csv', 20, TRUE),
    ('a1000000-0000-0000-0000-000000000193', 'a1000000-0000-0000-0000-000000000001', 'kitchen', 'Kitchen Report', 'Kitchen staff hours by day', 'staff_pay_csv', 30, TRUE),
    ('a1000000-0000-0000-0000-000000000194', 'a1000000-0000-0000-0000-000000000002', 'beta_hours', 'Beta Hours', 'Beta venue report', 'staff_pay_csv', 10, TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    slug = EXCLUDED.slug,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    engine = EXCLUDED.engine,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active;

INSERT INTO report_definition_shift_type_filters (id, report_definition_id, shift_type_id)
VALUES
    ('a1000000-0000-0000-0000-000000000201', 'a1000000-0000-0000-0000-000000000193', 'a1000000-0000-0000-0000-000000000132')
ON CONFLICT (id) DO UPDATE SET
    report_definition_id = EXCLUDED.report_definition_id,
    shift_type_id = EXCLUDED.shift_type_id;

INSERT INTO roster_groups (id, venue_id, name, sort_order, is_active, is_default)
VALUES
    ('a1000000-0000-0000-0000-000000000211', 'a1000000-0000-0000-0000-000000000001', 'Main', 0, TRUE, TRUE),
    ('a1000000-0000-0000-0000-000000000212', 'a1000000-0000-0000-0000-000000000002', 'Main', 0, TRUE, TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active,
    is_default = EXCLUDED.is_default;

INSERT INTO slot_names (id, venue_id, roster_group_id, name, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000041', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', 'Early', TRUE),
    ('a1000000-0000-0000-0000-000000000042', 'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000212', 'Late', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    roster_group_id = EXCLUDED.roster_group_id,
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

INSERT INTO roster_weeks (id, venue_id, roster_group_id, week_offset, is_live)
VALUES
    ('a1000000-0000-0000-0000-000000000051', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000052', 'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000212', 0, FALSE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    roster_group_id = EXCLUDED.roster_group_id,
    week_offset = EXCLUDED.week_offset,
    is_live = EXCLUDED.is_live;

INSERT INTO roster_days (id, roster_week_id, day_offset, is_closed)
VALUES
    ('a1000000-0000-0000-0000-000000000061', 'a1000000-0000-0000-0000-000000000051', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000062', 'a1000000-0000-0000-0000-000000000052', 0, FALSE)
ON CONFLICT (id) DO UPDATE SET
    roster_week_id = EXCLUDED.roster_week_id,
    day_offset = EXCLUDED.day_offset,
    is_closed = EXCLUDED.is_closed;

INSERT INTO roster_slots (id, roster_day_id, staff_id, slot_name_id, row_index, start_time, duration_minutes, note)
VALUES
    (
        'a1000000-0000-0000-0000-000000000071',
        'a1000000-0000-0000-0000-000000000061',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000041',
        0,
        '09:00',
        480,
        'Alpha coverage'
    ),
    (
        'a1000000-0000-0000-0000-000000000072',
        'a1000000-0000-0000-0000-000000000062',
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000042',
        0,
        '09:00',
        480,
        'Beta coverage'
    )
ON CONFLICT (id) DO UPDATE SET
    roster_day_id = EXCLUDED.roster_day_id,
    staff_id = EXCLUDED.staff_id,
    slot_name_id = EXCLUDED.slot_name_id,
    row_index = EXCLUDED.row_index,
    start_time = EXCLUDED.start_time,
    duration_minutes = EXCLUDED.duration_minutes,
    note = EXCLUDED.note;

INSERT INTO leave_requests (id, venue_id, staff_id, start_date, end_date, status, notes)
VALUES
    (
        'a1000000-0000-0000-0000-000000000081',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '1 day',
        'pending',
        'Alpha leave request'
    ),
    (
        'a1000000-0000-0000-0000-000000000082',
        'a1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000032',
        CURRENT_DATE,
        CURRENT_DATE + INTERVAL '1 day',
        'pending',
        'Beta leave request'
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    staff_id = EXCLUDED.staff_id,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date,
    status = EXCLUDED.status,
    notes = EXCLUDED.notes;

INSERT INTO timesheet_entries (
    id,
    venue_id,
    staff_id,
    shift_type_id,
    worked_on,
    start_time,
    end_time,
    had_break,
    break_minutes,
    pay_config_snapshot_id,
    is_approved,
    approved_at,
    approved_by_user_id
)
VALUES
    (
        'a1000000-0000-0000-0000-000000000091',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000131',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        '08:00',
        '16:00',
        FALSE,
        0,
        'a1000000-0000-0000-0000-000000000181',
        TRUE,
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'a1000000-0000-0000-0000-000000000092',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000132',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + 1,
        '10:00',
        '14:00',
        FALSE,
        0,
        'a1000000-0000-0000-0000-000000000181',
        TRUE,
        '2025-01-12 01:05:00+00',
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'a1000000-0000-0000-0000-000000000093',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000131',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + 4,
        '19:00',
        '01:00',
        FALSE,
        0,
        'a1000000-0000-0000-0000-000000000181',
        TRUE,
        '2025-01-12 01:10:00+00',
        'a0000000-0000-0000-0000-000000000001'
    ),
    (
        'a1000000-0000-0000-0000-000000000094',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000101',
        'a1000000-0000-0000-0000-000000000133',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        '09:00',
        '11:00',
        FALSE,
        0,
        'a1000000-0000-0000-0000-000000000181',
        TRUE,
        '2025-01-12 01:15:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000096',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000133',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + 2,
        '12:00',
        '15:00',
        FALSE,
        0,
        NULL,
        FALSE,
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000095',
        'a1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000141',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        '09:00',
        '17:00',
        FALSE,
        0,
        NULL,
        FALSE,
        NULL,
        NULL
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    staff_id = EXCLUDED.staff_id,
    shift_type_id = EXCLUDED.shift_type_id,
    worked_on = EXCLUDED.worked_on,
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    had_break = EXCLUDED.had_break,
    break_minutes = EXCLUDED.break_minutes,
    pay_config_snapshot_id = EXCLUDED.pay_config_snapshot_id,
    is_approved = EXCLUDED.is_approved,
    approved_at = EXCLUDED.approved_at,
    approved_by_user_id = EXCLUDED.approved_by_user_id;
