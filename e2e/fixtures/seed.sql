-- Seed data for e2e tests.
-- All test data uses fixed ids and/or the 'e2e-' prefix to stay idempotent.
-- Password for this user is: test-password-123

-- Reset mutable venue-scoped test data so repeated runs start from the same roster state.
DELETE FROM export_jobs
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM billing_events
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');
DELETE FROM billing_checkout_attempts
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');
DELETE FROM venue_subscriptions
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');
DELETE FROM venue_billing_customers
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM passkeys
WHERE user_id IN (
    SELECT id
    FROM users
    WHERE email LIKE 'e2e-%'
);

DELETE FROM timesheet_entries
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM leave_requests
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM staff_pay_versions
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM shift_type_pay_versions
WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002');

DELETE FROM day_names
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

INSERT INTO venues (id, name, status)
VALUES
    ('a1000000-0000-0000-0000-000000000001', 'e2e-alpha-venue', 'active'),
    ('a1000000-0000-0000-0000-000000000002', 'e2e-beta-venue', 'active')
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    status = EXCLUDED.status;

INSERT INTO venue_config (id, venue_id, timezone, roster_week_starts_on, week_offset_epoch, late_to_early_min_start_gap_minutes, staff_timesheet_edit_window_days)
VALUES
    (
        'a1000000-0000-0000-0000-000000000011',
        'a1000000-0000-0000-0000-000000000001',
        'Australia/Melbourne',
        1,
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        600,
        7
    ),
    (
        'a1000000-0000-0000-0000-000000000012',
        'a1000000-0000-0000-0000-000000000002',
        'Australia/Melbourne',
        1,
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        600,
        7
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    timezone = EXCLUDED.timezone,
    roster_week_starts_on = EXCLUDED.roster_week_starts_on,
    week_offset_epoch = EXCLUDED.week_offset_epoch,
    late_to_early_min_start_gap_minutes = EXCLUDED.late_to_early_min_start_gap_minutes,
    staff_timesheet_edit_window_days = EXCLUDED.staff_timesheet_edit_window_days;

INSERT INTO users (id, email, password_hash, user_role, platform_role, is_profile_completed, email_verified_at, failed_login_attempts)
VALUES
    (
        'a0000000-0000-0000-0000-000000000001',
        'e2e-test@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        NULL,
        TRUE,
        NOW(),
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000003',
        'e2e-admin@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'admin',
        NULL,
        TRUE,
        NOW(),
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000002',
        'e2e-worker@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'staff',
        NULL,
        TRUE,
        NOW(),
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000004',
        'e2e-super-admin@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        'super_admin',
        TRUE,
        NOW(),
        0
    ),
    (
        'a0000000-0000-0000-0000-000000000005',
        'e2e-billing-owner@example.com',
        'sha256|17|pTjl57yJOvFluR4n2l2OmA==|beKP33BwrGQhNd1xvMF0rt7EKxW1tR6KaN1i8ExJLzs=',
        'manager',
        NULL,
        TRUE,
        NOW(),
        0
    )
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    password_hash = EXCLUDED.password_hash,
    user_role = EXCLUDED.user_role,
    platform_role = EXCLUDED.platform_role,
    is_profile_completed = EXCLUDED.is_profile_completed,
    email_verified_at = EXCLUDED.email_verified_at,
    failed_login_attempts = EXCLUDED.failed_login_attempts,
    locked_at = NULL;

-- Deterministic passkey rows for non-passkey E2E specs. These satisfy the
-- app's "has a passkey" gate; real WebAuthn registration/step-up coverage lives
-- in e2e/passkeys.spec.ts, which clears these rows before exercising that flow.
INSERT INTO passkeys (id, user_id, credential_id, public_key, sign_count, name, created_at, updated_at)
VALUES
    (
        'a0000000-0000-0000-0000-000000000031',
        'a0000000-0000-0000-0000-000000000003',
        decode('6532652d61646d696e2d7365656465642d706173736b6579', 'hex'),
        decode('6532652d61646d696e2d7365656465642d7075626c69632d6b6579', 'hex'),
        0,
        'Seeded E2E passkey',
        '2025-01-01 00:00:00+00',
        '2025-01-01 00:00:00+00'
    ),
    (
        'a0000000-0000-0000-0000-000000000032',
        'a0000000-0000-0000-0000-000000000004',
        decode('6532652d73757065722d61646d696e2d7365656465642d706173736b6579', 'hex'),
        decode('6532652d73757065722d61646d696e2d7365656465642d7075626c69632d6b6579', 'hex'),
        0,
        'Seeded E2E passkey',
        '2025-01-01 00:00:00+00',
        '2025-01-01 00:00:00+00'
    ),
    (
        'a0000000-0000-0000-0000-000000000033',
        'a0000000-0000-0000-0000-000000000005',
        decode('6532652d62696c6c696e672d6f776e65722d7365656465642d706173736b6579', 'hex'),
        decode('6532652d62696c6c696e672d6f776e65722d7365656465642d7075626c69632d6b6579', 'hex'),
        0,
        'Seeded E2E passkey',
        '2025-01-01 00:00:00+00',
        '2025-01-01 00:00:00+00'
    )
ON CONFLICT (id) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    credential_id = EXCLUDED.credential_id,
    public_key = EXCLUDED.public_key,
    sign_count = EXCLUDED.sign_count,
    name = EXCLUDED.name,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at;

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
    ),
    (
        'a1000000-0000-0000-0000-000000000025',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000004',
        'venue_owner',
        TRUE,
        '2025-01-05 00:00:00+00',
        '2025-01-05 00:00:00+00'
    ),
    (
        'a1000000-0000-0000-0000-000000000026',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000005',
        'venue_owner',
        TRUE,
        '2025-01-06 00:00:00+00',
        '2025-01-06 00:00:00+00'
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    user_id = EXCLUDED.user_id,
    venue_role = EXCLUDED.venue_role,
    is_active = EXCLUDED.is_active,
    created_at = EXCLUDED.created_at,
    updated_at = EXCLUDED.updated_at;

INSERT INTO award_levels (
    id,
    award_fixed_id,
    classification_fixed_id,
    classification,
    classification_level,
    operative_from,
    published_year,
    is_active,
    raw_json
)
VALUES
    ('a1000000-0000-0000-0000-000000000111', 900001, 1, 'LVL 1', NULL, '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000112', 900001, 2, 'LVL 2', NULL, '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000113', 900001, 3, 'Floor Level', NULL, '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000121', 900001, 4, 'Beta Level', NULL, '2025-07-01', 2025, TRUE, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    classification_level = EXCLUDED.classification_level,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    is_active = EXCLUDED.is_active,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

INSERT INTO fwc_mapd_pay_rates (
    id,
    award_fixed_id,
    classification_fixed_id,
    classification,
    classification_level,
    employee_rate_type_code,
    calculated_rate,
    calculated_rate_type,
    operative_from,
    published_year,
    raw_json
)
VALUES
    ('a1000000-0000-0000-0000-000000000711', 900001, 1, 'LVL 1', NULL, 'AD', 30.00, 'Hourly', '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000712', 900001, 2, 'LVL 2', NULL, 'AD', 35.00, 'Hourly', '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000713', 900001, 3, 'Floor Level', NULL, 'AD', 28.00, 'Hourly', '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000714', 900001, 4, 'Beta Level', NULL, 'AD', 27.00, 'Hourly', '2025-07-01', 2025, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    classification_level = EXCLUDED.classification_level,
    employee_rate_type_code = EXCLUDED.employee_rate_type_code,
    calculated_rate = EXCLUDED.calculated_rate,
    calculated_rate_type = EXCLUDED.calculated_rate_type,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

INSERT INTO award_level_base_rates (
    id,
    award_level_id,
    employment_basis,
    fwc_mapd_pay_rate_id,
    hourly_rate,
    rate_label,
    operative_from,
    published_year
)
VALUES
    ('a1000000-0000-0000-0000-000000000721', 'a1000000-0000-0000-0000-000000000111', 'permanent', 'a1000000-0000-0000-0000-000000000711', 30.00, 'Permanent hourly', '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000722', 'a1000000-0000-0000-0000-000000000112', 'permanent', 'a1000000-0000-0000-0000-000000000712', 35.00, 'Permanent hourly', '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000723', 'a1000000-0000-0000-0000-000000000113', 'permanent', 'a1000000-0000-0000-0000-000000000713', 28.00, 'Permanent hourly', '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000724', 'a1000000-0000-0000-0000-000000000121', 'permanent', 'a1000000-0000-0000-0000-000000000714', 27.00, 'Permanent hourly', '2025-07-01', 2025)
ON CONFLICT (id) DO UPDATE SET
    award_level_id = EXCLUDED.award_level_id,
    employment_basis = EXCLUDED.employment_basis,
    fwc_mapd_pay_rate_id = EXCLUDED.fwc_mapd_pay_rate_id,
    hourly_rate = EXCLUDED.hourly_rate,
    rate_label = EXCLUDED.rate_label,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    updated_at = NOW();

INSERT INTO fwc_mapd_wage_allowances (
    id,
    award_fixed_id,
    wage_allowance_fixed_id,
    allowance,
    rate_unit,
    allowance_amount,
    operative_from,
    published_year,
    raw_json
)
VALUES
    ('a1000000-0000-0000-0000-000000000731', 900001, 7001, 'Monday to Friday - 7pm to midnight allowance', 'Hourly', 2.81, '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000732', 900001, 7002, 'Monday to Friday - midnight to 7am allowance', 'Hourly', 4.22, '2025-07-01', 2025, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    wage_allowance_fixed_id = EXCLUDED.wage_allowance_fixed_id,
    allowance = EXCLUDED.allowance,
    rate_unit = EXCLUDED.rate_unit,
    allowance_amount = EXCLUDED.allowance_amount,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

INSERT INTO award_time_penalty_allowances (
    id,
    award_fixed_id,
    penalty_kind,
    fwc_mapd_wage_allowance_id,
    hourly_amount,
    starts_at_time,
    ends_at_time,
    operative_from,
    published_year
)
VALUES
    ('a1000000-0000-0000-0000-000000000741', 900001, 'evening_after_7pm', 'a1000000-0000-0000-0000-000000000731', 2.81, '19:00', '00:00', '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000742', 900001, 'late_night_after_midnight', 'a1000000-0000-0000-0000-000000000732', 4.22, '00:00', '07:00', '2025-07-01', 2025)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    penalty_kind = EXCLUDED.penalty_kind,
    fwc_mapd_wage_allowance_id = EXCLUDED.fwc_mapd_wage_allowance_id,
    hourly_amount = EXCLUDED.hourly_amount,
    starts_at_time = EXCLUDED.starts_at_time,
    ends_at_time = EXCLUDED.ends_at_time,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    updated_at = NOW();

INSERT INTO fwc_mapd_penalty_rates (
    id,
    award_fixed_id,
    classification_fixed_id,
    classification,
    classification_level,
    employee_rate_type_code,
    penalty_fixed_id,
    penalty_description,
    penalty_calculated_value,
    operative_from,
    published_year,
    raw_json
)
VALUES
    ('a1000000-0000-0000-0000-000000000751', 900001, 1, 'LVL 1', NULL, 'AD', 7501, 'Saturday', 45.00, '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000752', 900001, 1, 'LVL 1', NULL, 'AD', 7502, 'Sunday', 52.50, '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000753', 900001, 1, 'LVL 1', NULL, 'AD', 7503, 'Public holiday', 67.50, '2025-07-01', 2025, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    classification_level = EXCLUDED.classification_level,
    employee_rate_type_code = EXCLUDED.employee_rate_type_code,
    penalty_fixed_id = EXCLUDED.penalty_fixed_id,
    penalty_description = EXCLUDED.penalty_description,
    penalty_calculated_value = EXCLUDED.penalty_calculated_value,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

INSERT INTO award_level_penalty_rates (
    id,
    award_level_id,
    employment_basis,
    penalty_kind,
    fwc_mapd_penalty_rate_id,
    hourly_rate,
    operative_from,
    published_year
)
VALUES
    ('a1000000-0000-0000-0000-000000000761', 'a1000000-0000-0000-0000-000000000111', 'permanent', 'saturday_penalty', 'a1000000-0000-0000-0000-000000000751', 45.00, '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000762', 'a1000000-0000-0000-0000-000000000111', 'permanent', 'sunday_penalty', 'a1000000-0000-0000-0000-000000000752', 52.50, '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000763', 'a1000000-0000-0000-0000-000000000111', 'permanent', 'public_holiday_penalty', 'a1000000-0000-0000-0000-000000000753', 67.50, '2025-07-01', 2025)
ON CONFLICT (id) DO UPDATE SET
    award_level_id = EXCLUDED.award_level_id,
    employment_basis = EXCLUDED.employment_basis,
    penalty_kind = EXCLUDED.penalty_kind,
    fwc_mapd_penalty_rate_id = EXCLUDED.fwc_mapd_penalty_rate_id,
    hourly_rate = EXCLUDED.hourly_rate,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    updated_at = NOW();

INSERT INTO staff (
    id,
    venue_id,
    user_id,
    first_name,
    last_name,
    phone,
    emergency_contact_name,
    emergency_contact_phone,
    ideal_shifts_per_week,
    employment_basis,
    default_award_level_id,
    is_active
)
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
        'permanent',
        'a1000000-0000-0000-0000-000000000111',
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
        'permanent',
        'a1000000-0000-0000-0000-000000000111',
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
        'permanent',
        'a1000000-0000-0000-0000-000000000111',
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
        'permanent',
        'a1000000-0000-0000-0000-000000000121',
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000034',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000004',
        'E2E',
        'Super Admin',
        '0400000005',
        'Emergency Support',
        '0400000105',
        0,
        'permanent',
        'a1000000-0000-0000-0000-000000000111',
        TRUE
    ),
    (
        'a1000000-0000-0000-0000-000000000036',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000005',
        'Billing',
        'Owner',
        '0400000007',
        'Emergency Owner',
        '0400000107',
        0,
        'permanent',
        'a1000000-0000-0000-0000-000000000111',
        FALSE
    ),
    (
        'a1000000-0000-0000-0000-000000000035',
        'a1000000-0000-0000-0000-000000000001',
        NULL,
        'E2E',
        'Trial',
        '0400000006',
        'Emergency Trial',
        '0400000106',
        0,
        'casual',
        'a1000000-0000-0000-0000-000000000111',
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
    employment_basis = EXCLUDED.employment_basis,
    default_award_level_id = EXCLUDED.default_award_level_id,
    is_active = EXCLUDED.is_active;

INSERT INTO shift_types (id, venue_id, name, sort_order, override_award_level_id, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000131', 'a1000000-0000-0000-0000-000000000001', 'Bar', 10, 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000132', 'a1000000-0000-0000-0000-000000000001', 'Kitchen', 20, 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000133', 'a1000000-0000-0000-0000-000000000001', 'Floor', 30, 'a1000000-0000-0000-0000-000000000113', TRUE),
    ('a1000000-0000-0000-0000-000000000141', 'a1000000-0000-0000-0000-000000000002', 'Beta Shift', 10, 'a1000000-0000-0000-0000-000000000121', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    override_award_level_id = EXCLUDED.override_award_level_id,
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

INSERT INTO staff_pay_versions (
    id,
    venue_id,
    staff_id,
    default_award_level_id,
    employment_basis,
    effective_from,
    created_by_user_id,
    locked_at,
    locked_by_user_id
)
VALUES
    (
        'a1000000-0000-0000-0000-000000000301',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000101',
        'a1000000-0000-0000-0000-000000000111',
        'permanent',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000302',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000111',
        'permanent',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000303',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000033',
        'a1000000-0000-0000-0000-000000000111',
        'permanent',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000304',
        'a1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000121',
        'permanent',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        NULL,
        NULL
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    staff_id = EXCLUDED.staff_id,
    default_award_level_id = EXCLUDED.default_award_level_id,
    employment_basis = EXCLUDED.employment_basis,
    effective_from = EXCLUDED.effective_from,
    created_by_user_id = EXCLUDED.created_by_user_id,
    locked_at = EXCLUDED.locked_at,
    locked_by_user_id = EXCLUDED.locked_by_user_id,
    updated_at = NOW();

INSERT INTO shift_type_pay_versions (
    id,
    venue_id,
    shift_type_id,
    override_award_level_id,
    payroll_label,
    effective_from,
    created_by_user_id,
    locked_at,
    locked_by_user_id
)
VALUES
    (
        'a1000000-0000-0000-0000-000000000311',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000131',
        'a1000000-0000-0000-0000-000000000111',
        'Bar',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000312',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000132',
        'a1000000-0000-0000-0000-000000000111',
        'Kitchen',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000313',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000133',
        'a1000000-0000-0000-0000-000000000113',
        'Floor',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        '2025-01-12 01:00:00+00',
        'a0000000-0000-0000-0000-000000000003'
    ),
    (
        'a1000000-0000-0000-0000-000000000314',
        'a1000000-0000-0000-0000-000000000002',
        'a1000000-0000-0000-0000-000000000141',
        'a1000000-0000-0000-0000-000000000121',
        'Beta Shift',
        CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1),
        'a0000000-0000-0000-0000-000000000003',
        NULL,
        NULL
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    shift_type_id = EXCLUDED.shift_type_id,
    override_award_level_id = EXCLUDED.override_award_level_id,
    payroll_label = EXCLUDED.payroll_label,
    effective_from = EXCLUDED.effective_from,
    created_by_user_id = EXCLUDED.created_by_user_id,
    locked_at = EXCLUDED.locked_at,
    locked_by_user_id = EXCLUDED.locked_by_user_id,
    updated_at = NOW();

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

INSERT INTO staff_roster_groups (id, staff_id, roster_group_id)
VALUES
    ('a1000000-0000-0000-0000-000000000241', 'a0000000-0000-0000-0000-000000000101', 'a1000000-0000-0000-0000-000000000211'),
    ('a1000000-0000-0000-0000-000000000242', 'a1000000-0000-0000-0000-000000000031', 'a1000000-0000-0000-0000-000000000211'),
    ('a1000000-0000-0000-0000-000000000243', 'a1000000-0000-0000-0000-000000000033', 'a1000000-0000-0000-0000-000000000211'),
    ('a1000000-0000-0000-0000-000000000244', 'a1000000-0000-0000-0000-000000000032', 'a1000000-0000-0000-0000-000000000212'),
    ('a1000000-0000-0000-0000-000000000245', 'a1000000-0000-0000-0000-000000000035', 'a1000000-0000-0000-0000-000000000211')
ON CONFLICT (id) DO UPDATE SET
    staff_id = EXCLUDED.staff_id,
    roster_group_id = EXCLUDED.roster_group_id,
    updated_at = NOW();

INSERT INTO slot_names (id, venue_id, roster_group_id, name, sort_order, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000041', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', 'Early', 0, TRUE),
    ('a1000000-0000-0000-0000-000000000042', 'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000212', 'Late', 0, TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    roster_group_id = EXCLUDED.roster_group_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    is_active = EXCLUDED.is_active;

INSERT INTO roster_weeks (id, venue_id, roster_group_id, week_offset, is_live)
VALUES
    ('a1000000-0000-0000-0000-000000000051', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000053', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', 1, FALSE),
    ('a1000000-0000-0000-0000-000000000052', 'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000212', 0, FALSE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    roster_group_id = EXCLUDED.roster_group_id,
    week_offset = EXCLUDED.week_offset,
    is_live = EXCLUDED.is_live;

INSERT INTO roster_days (id, roster_week_id, day_offset, is_closed)
VALUES
    ('a1000000-0000-0000-0000-000000000061', 'a1000000-0000-0000-0000-000000000051', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000063', 'a1000000-0000-0000-0000-000000000053', 0, FALSE),
    ('a1000000-0000-0000-0000-000000000062', 'a1000000-0000-0000-0000-000000000052', 0, FALSE)
ON CONFLICT (id) DO UPDATE SET
    roster_week_id = EXCLUDED.roster_week_id,
    day_offset = EXCLUDED.day_offset,
    is_closed = EXCLUDED.is_closed;

INSERT INTO roster_week_slot_definitions (id, roster_week_id, name, sort_order)
VALUES
    ('a1000000-0000-0000-0000-000000000081', 'a1000000-0000-0000-0000-000000000051', 'Early', 0),
    ('a1000000-0000-0000-0000-000000000082', 'a1000000-0000-0000-0000-000000000052', 'Late', 0),
    ('a1000000-0000-0000-0000-000000000083', 'a1000000-0000-0000-0000-000000000053', 'Early', 0)
ON CONFLICT (id) DO UPDATE SET
    roster_week_id = EXCLUDED.roster_week_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    deleted_at = NULL,
    updated_at = NOW();

INSERT INTO roster_slots (id, roster_day_id, staff_id, roster_week_slot_definition_id, row_index, start_time, duration_minutes, shift_type_id)
VALUES
    (
        'a1000000-0000-0000-0000-000000000071',
        'a1000000-0000-0000-0000-000000000061',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000081',
        0,
        '09:00',
        480,
        'a1000000-0000-0000-0000-000000000133'
    ),
    (
        'a1000000-0000-0000-0000-000000000072',
        'a1000000-0000-0000-0000-000000000062',
        'a1000000-0000-0000-0000-000000000032',
        'a1000000-0000-0000-0000-000000000082',
        0,
        '09:00',
        480,
        'a1000000-0000-0000-0000-000000000141'
    ),
    (
        'a1000000-0000-0000-0000-000000000073',
        'a1000000-0000-0000-0000-000000000063',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000083',
        0,
        '09:00',
        240,
        'a1000000-0000-0000-0000-000000000133'
    ),
    (
        'a1000000-0000-0000-0000-000000000074',
        'a1000000-0000-0000-0000-000000000063',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000083',
        1,
        '13:00',
        240,
        'a1000000-0000-0000-0000-000000000133'
    )
ON CONFLICT (id) DO UPDATE SET
    roster_day_id = EXCLUDED.roster_day_id,
    staff_id = EXCLUDED.staff_id,
    roster_week_slot_definition_id = EXCLUDED.roster_week_slot_definition_id,
    row_index = EXCLUDED.row_index,
    start_time = EXCLUDED.start_time,
    duration_minutes = EXCLUDED.duration_minutes,
    shift_type_id = EXCLUDED.shift_type_id;

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
    ),
    (
        'a1000000-0000-0000-0000-000000000083',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + INTERVAL '7 day')::date,
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + INTERVAL '8 day')::date,
        'pending',
        'January overview leave request'
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
    staff_pay_version_id,
    shift_type_pay_version_id,
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
        'a1000000-0000-0000-0000-000000000302',
        'a1000000-0000-0000-0000-000000000311',
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
        'a1000000-0000-0000-0000-000000000302',
        'a1000000-0000-0000-0000-000000000312',
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
        'a1000000-0000-0000-0000-000000000302',
        'a1000000-0000-0000-0000-000000000311',
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
        'a1000000-0000-0000-0000-000000000301',
        'a1000000-0000-0000-0000-000000000313',
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
    staff_pay_version_id = EXCLUDED.staff_pay_version_id,
    shift_type_pay_version_id = EXCLUDED.shift_type_pay_version_id,
    is_approved = EXCLUDED.is_approved,
    approved_at = EXCLUDED.approved_at,
    approved_by_user_id = EXCLUDED.approved_by_user_id;
