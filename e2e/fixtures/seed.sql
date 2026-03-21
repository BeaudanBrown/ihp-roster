-- Seed data for e2e tests.
-- All test data uses fixed ids and/or the 'e2e-' prefix to stay idempotent.
-- Password for this user is: test-password-123

-- Reset mutable venue-scoped test data so repeated runs start from the same roster state.
DELETE FROM timesheet_entries
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM leave_requests
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

INSERT INTO venues (id, name, status)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'e2e-alpha-venue', 'active'),
    ('a1000000-0000-0000-0000-000000000002', 'e2e-beta-venue', 'active')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status;

INSERT INTO venue_config (id, venue_id, timezone, week_offset_epoch, late_to_early_min_start_gap_minutes, staff_timesheet_edit_window_days)
VALUES
    ('a1000000-0000-0000-0000-000000000011', 'a1000000-0000-0000-0000-000000000001', 'UTC', CURRENT_DATE, 600, 7),
    ('a1000000-0000-0000-0000-000000000012', 'a1000000-0000-0000-0000-000000000002', 'UTC', CURRENT_DATE, 600, 7)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    timezone = EXCLUDED.timezone,
    week_offset_epoch = EXCLUDED.week_offset_epoch,
    late_to_early_min_start_gap_minutes = EXCLUDED.late_to_early_min_start_gap_minutes,
    staff_timesheet_edit_window_days = EXCLUDED.staff_timesheet_edit_window_days;

INSERT INTO users (id, email, password_hash, user_role, is_profile_completed, failed_login_attempts)
VALUES
    (
        'a0000000-0000-0000-0000-000000000001',
        'e2e-test@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        TRUE,
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000003',
        'e2e-admin@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'admin',
        TRUE,
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000002',
        'e2e-worker@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'staff',
        TRUE,
        0
    )
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    user_role = EXCLUDED.user_role,
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

INSERT INTO staff (id, venue_id, user_id, first_name, last_name, is_active)
VALUES
    (
        'a0000000-0000-0000-0000-000000000101',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001',
        'E2E',
        'Manager',
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000002',
        'Alpha',
        'Crew',
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000033',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000003',
        'Admin',
        'Crew',
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000002',
        NULL,
        'Beta',
        'Crew',
        TRUE
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    user_id = EXCLUDED.user_id,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    is_active = EXCLUDED.is_active;

INSERT INTO slot_names (id, venue_id, name, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000041', 'a1000000-0000-0000-0000-000000000001', 'Early', TRUE),
    ('a1000000-0000-0000-0000-000000000042', 'a1000000-0000-0000-0000-000000000002', 'Late', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    is_active = EXCLUDED.is_active;

INSERT INTO roster_weeks (id, venue_id, week_offset, is_live)
VALUES
    ('a1000000-0000-0000-0000-000000000051', 'a1000000-0000-0000-0000-000000000001', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000052', 'a1000000-0000-0000-0000-000000000002', 0, FALSE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    week_offset = EXCLUDED.week_offset,
    is_live = EXCLUDED.is_live;

INSERT INTO roster_days (id, roster_week_id, day_offset)
VALUES
    ('a1000000-0000-0000-0000-000000000061', 'a1000000-0000-0000-0000-000000000051', 0),
    ('a1000000-0000-0000-0000-000000000062', 'a1000000-0000-0000-0000-000000000052', 0)
ON CONFLICT (id) DO UPDATE SET
    roster_week_id = EXCLUDED.roster_week_id,
    day_offset = EXCLUDED.day_offset;

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

INSERT INTO timesheet_entries (id, venue_id, staff_id, worked_on, start_time, end_time, had_break, break_minutes, is_approved)
VALUES
    (
        'a1000000-0000-0000-0000-000000000091',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        CURRENT_DATE,
        '09:00',
        '17:00',
        FALSE,
        0,
        FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000092',
        'a1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000032',
        CURRENT_DATE,
        '09:00',
        '17:00',
        FALSE,
        0,
        FALSE
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    staff_id = EXCLUDED.staff_id,
    worked_on = EXCLUDED.worked_on,
    start_time = EXCLUDED.start_time,
    end_time = EXCLUDED.end_time,
    had_break = EXCLUDED.had_break,
    break_minutes = EXCLUDED.break_minutes,
    is_approved = EXCLUDED.is_approved;
