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
    SELECT id
    FROM roster_days
    WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM roster_lanes
WHERE roster_day_id IN (
    SELECT id
    FROM roster_days
    WHERE venue_id IN ('a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000002')
);

DELETE FROM roster_days
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

INSERT INTO venue_config (id, venue_id, timezone, roster_week_starts_on, late_to_early_min_start_gap_minutes, staff_timesheet_edit_window_days)
VALUES
    (
        'a1000000-0000-0000-0000-000000000011',
        'a1000000-0000-0000-0000-000000000001',
        'Australia/Melbourne',
        1,
        600,
        7
    ),
    (
        'a1000000-0000-0000-0000-000000000012',
        'a1000000-0000-0000-0000-000000000002',
        'Australia/Melbourne',
        1,
        600,
        7
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    timezone = EXCLUDED.timezone,
    roster_week_starts_on = EXCLUDED.roster_week_starts_on,
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

INSERT INTO fwc_mapd_sync_runs (
    id,
    status,
    requested_award_fixed_ids,
    synced_award_fixed_ids,
    fetched_award_count,
    fetched_classification_count,
    fetched_pay_rate_count,
    fetched_penalty_rate_count,
    fetched_wage_allowance_count,
    started_at,
    finished_at
)
VALUES (
    'a1000000-0000-0000-0000-000000000701',
    'succeeded',
    ARRAY[9],
    ARRAY[9],
    1,
    7,
    14,
    42,
    2,
    NOW() - INTERVAL '1 minute',
    NOW()
)
ON CONFLICT (id) DO UPDATE SET
    status = EXCLUDED.status,
    requested_award_fixed_ids = EXCLUDED.requested_award_fixed_ids,
    synced_award_fixed_ids = EXCLUDED.synced_award_fixed_ids,
    fetched_award_count = EXCLUDED.fetched_award_count,
    fetched_classification_count = EXCLUDED.fetched_classification_count,
    fetched_pay_rate_count = EXCLUDED.fetched_pay_rate_count,
    fetched_penalty_rate_count = EXCLUDED.fetched_penalty_rate_count,
    fetched_wage_allowance_count = EXCLUDED.fetched_wage_allowance_count,
    started_at = EXCLUDED.started_at,
    finished_at = EXCLUDED.finished_at,
    error_message = NULL,
    updated_at = NOW();

INSERT INTO public_holidays (
    id,
    jurisdiction,
    holiday_date,
    name,
    is_regional,
    source,
    source_id,
    imported_at
)
VALUES (
    md5('e2e-victoria-statewide-' || EXTRACT(YEAR FROM CURRENT_DATE)::text)::uuid,
    'VIC',
    make_date(EXTRACT(YEAR FROM CURRENT_DATE)::int, 1, 1),
    'E2E statewide holiday coverage',
    FALSE,
    'e2e-fixture',
    'e2e-statewide-current-year',
    NOW()
)
ON CONFLICT (id) DO UPDATE SET
    is_regional = FALSE,
    source = EXCLUDED.source,
    source_id = EXCLUDED.source_id,
    imported_at = EXCLUDED.imported_at,
    updated_at = NOW();

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
    ('a1000000-0000-0000-0000-000000000111', 9, 243, 'Level 1', '2.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000112', 9, 246, 'Level 2', '3.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000113', 9, 257, 'Level 3', '4.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000114', 9, 242, 'Introductory level', '1.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000115', 9, 276, 'Level 5', '6.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000116', 9, 282, 'Level 6', '7.0', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000121', 9, 268, 'Level 4', '5.0', '2025-07-01', 2025, TRUE, '{}'::jsonb)
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

WITH fixture_classifications (classification_fixed_id, classification, permanent_ordinary_rate) AS (
    VALUES
        (242, 'Introductory level', 24.28::numeric),
        (243, 'Level 1', 24.95::numeric),
        (246, 'Level 2', 25.85::numeric),
        (257, 'Level 3', 26.70::numeric),
        (268, 'Level 4', 28.12::numeric),
        (276, 'Level 5', 29.88::numeric),
        (282, 'Level 6', 30.00::numeric)
),
fixture_bases (employment_basis, employee_rate_type_code, multiplier) AS (
    VALUES ('permanent'::staff_employment_basis_enum, 'AD', 1.0), ('casual'::staff_employment_basis_enum, 'CA', 1.25)
)
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
SELECT
    md5('e2e-fwc-base-' || classification_fixed_id::text || '-' || employment_basis::text)::uuid,
    9,
    classification_fixed_id,
    classification,
    NULL,
    employee_rate_type_code,
    round(permanent_ordinary_rate * multiplier, 2),
    'Hourly',
    '2025-07-01'::date,
    2025,
    '{}'::jsonb
FROM fixture_classifications
CROSS JOIN fixture_bases
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

WITH fixture_award_levels (award_level_id, classification_fixed_id, permanent_ordinary_rate) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242, 24.28::numeric),
        ('a1000000-0000-0000-0000-000000000111'::uuid, 243, 24.95::numeric),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246, 25.85::numeric),
        ('a1000000-0000-0000-0000-000000000113'::uuid, 257, 26.70::numeric),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268, 28.12::numeric),
        ('a1000000-0000-0000-0000-000000000115'::uuid, 276, 29.88::numeric),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282, 30.00::numeric)
),
fixture_bases (employment_basis, multiplier) AS (
    VALUES ('permanent'::staff_employment_basis_enum, 1.0), ('casual'::staff_employment_basis_enum, 1.25)
)
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
SELECT
    md5('e2e-base-' || award_level_id::text || '-' || employment_basis::text)::uuid,
    award_level_id,
    employment_basis,
    md5('e2e-fwc-base-' || classification_fixed_id::text || '-' || employment_basis::text)::uuid,
    round(permanent_ordinary_rate * multiplier, 2),
    CASE employment_basis WHEN 'casual' THEN 'Casual ordinary hours' ELSE 'Hourly' END,
    '2025-07-01'::date,
    2025
FROM fixture_award_levels
CROSS JOIN fixture_bases
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
    ('a1000000-0000-0000-0000-000000000731', 9, 7001, 'Monday to Friday - 7pm to midnight allowance', 'Hourly', 2.81, '2025-07-01', 2025, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000732', 9, 7002, 'Monday to Friday - midnight to 7am allowance', 'Hourly', 4.22, '2025-07-01', 2025, '{}'::jsonb)
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
    ('a1000000-0000-0000-0000-000000000741', 9, 'evening_after_7pm', 'a1000000-0000-0000-0000-000000000731', 2.81, '19:00', '00:00', '2025-07-01', 2025),
    ('a1000000-0000-0000-0000-000000000742', 9, 'late_night_after_midnight', 'a1000000-0000-0000-0000-000000000732', 4.22, '00:00', '07:00', '2025-07-01', 2025)
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

WITH fixture_classifications (classification_fixed_id, classification, permanent_ordinary_rate, ordinal) AS (
    VALUES
        (242, 'Introductory level', 24.28::numeric, 0),
        (243, 'Level 1', 24.95::numeric, 1),
        (246, 'Level 2', 25.85::numeric, 2),
        (257, 'Level 3', 26.70::numeric, 3),
        (268, 'Level 4', 28.12::numeric, 4),
        (276, 'Level 5', 29.88::numeric, 5),
        (282, 'Level 6', 30.00::numeric, 6)
),
fixture_bases (employment_basis, employee_rate_type_code, basis_ordinal) AS (
    VALUES
        ('permanent'::staff_employment_basis_enum, 'AD', 0),
        ('casual'::staff_employment_basis_enum, 'CA', 1)
),
fixture_penalties (penalty_kind, description, permanent_multiplier, casual_multiplier, penalty_ordinal) AS (
    VALUES
        ('saturday_penalty'::award_penalty_kind_enum, 'Saturday', 1.25, 1.5, 1),
        ('sunday_penalty'::award_penalty_kind_enum, 'Sunday', 1.5, 1.75, 2),
        ('public_holiday_penalty'::award_penalty_kind_enum, 'Public holiday', 2.25, 2.5, 3)
)
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
SELECT
    md5('e2e-fwc-penalty-' || classification_fixed_id::text || '-' || employment_basis::text || '-' || penalty_kind::text)::uuid,
    9,
    classification_fixed_id,
    classification,
    NULL,
    employee_rate_type_code,
    7500 + (ordinal * 10) + (basis_ordinal * 3) + penalty_ordinal,
    description,
    round(permanent_ordinary_rate * CASE employment_basis WHEN 'casual' THEN casual_multiplier ELSE permanent_multiplier END, 2),
    '2025-07-01'::date,
    2025,
    '{}'::jsonb
FROM fixture_classifications
CROSS JOIN fixture_bases
CROSS JOIN fixture_penalties
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

WITH fixture_award_levels (award_level_id, classification_fixed_id, permanent_ordinary_rate) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242, 24.28::numeric),
        ('a1000000-0000-0000-0000-000000000111'::uuid, 243, 24.95::numeric),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246, 25.85::numeric),
        ('a1000000-0000-0000-0000-000000000113'::uuid, 257, 26.70::numeric),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268, 28.12::numeric),
        ('a1000000-0000-0000-0000-000000000115'::uuid, 276, 29.88::numeric),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282, 30.00::numeric)
),
fixture_bases (employment_basis) AS (
    VALUES ('permanent'::staff_employment_basis_enum), ('casual'::staff_employment_basis_enum)
),
fixture_penalties (penalty_kind, permanent_multiplier, casual_multiplier) AS (
    VALUES
        ('saturday_penalty'::award_penalty_kind_enum, 1.25, 1.5),
        ('sunday_penalty'::award_penalty_kind_enum, 1.5, 1.75),
        ('public_holiday_penalty'::award_penalty_kind_enum, 2.25, 2.5)
)
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
SELECT
    md5('e2e-penalty-' || award_level_id::text || '-' || employment_basis::text || '-' || penalty_kind::text)::uuid,
    award_level_id,
    employment_basis,
    penalty_kind,
    md5('e2e-fwc-penalty-' || classification_fixed_id::text || '-' || employment_basis::text || '-' || penalty_kind::text)::uuid,
    round(permanent_ordinary_rate * CASE employment_basis WHEN 'casual' THEN casual_multiplier ELSE permanent_multiplier END, 2),
    '2025-07-01'::date,
    2025
FROM fixture_award_levels
CROSS JOIN fixture_bases
CROSS JOIN fixture_penalties
ON CONFLICT (id) DO UPDATE SET
    award_level_id = EXCLUDED.award_level_id,
    employment_basis = EXCLUDED.employment_basis,
    penalty_kind = EXCLUDED.penalty_kind,
    fwc_mapd_penalty_rate_id = EXCLUDED.fwc_mapd_penalty_rate_id,
    hourly_rate = EXCLUDED.hourly_rate,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    updated_at = NOW();

-- Approval exercises the canonical MA000009 adapter, which validates a complete
-- rate book rather than only the selected classification. Keep all seven
-- supported classifications, both employment bases, four rate kinds, and the
-- two Award-owned time additions in one effective snapshot.
INSERT INTO award_levels (id, award_fixed_id, classification_fixed_id, classification, operative_from, published_year, is_active, raw_json)
VALUES
    ('a1000000-0000-0000-0000-000000000114', 9, 242, 'Introductory', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000111', 9, 243, 'Level 1', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000112', 9, 246, 'Level 2', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000113', 9, 257, 'Level 3', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000121', 9, 268, 'Level 4', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000115', 9, 276, 'Level 5', '2025-07-01', 2025, TRUE, '{}'::jsonb),
    ('a1000000-0000-0000-0000-000000000116', 9, 282, 'Level 6', '2025-07-01', 2025, TRUE, '{}'::jsonb)
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    is_active = EXCLUDED.is_active,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

WITH levels(id, fixed_id, classification) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242, 'Introductory'),
        ('a1000000-0000-0000-0000-000000000111'::uuid, 243, 'Level 1'),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246, 'Level 2'),
        ('a1000000-0000-0000-0000-000000000113'::uuid, 257, 'Level 3'),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268, 'Level 4'),
        ('a1000000-0000-0000-0000-000000000115'::uuid, 276, 'Level 5'),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282, 'Level 6')
), bases(basis, multiplier) AS (VALUES ('permanent'::staff_employment_basis_enum, 1.0::numeric), ('casual'::staff_employment_basis_enum, 1.25::numeric))
INSERT INTO fwc_mapd_pay_rates (id, award_fixed_id, classification_fixed_id, classification, employee_rate_type_code, calculated_rate, calculated_rate_type, operative_from, published_year, raw_json)
SELECT md5('e2e-base-source-' || fixed_id || '-' || basis::text)::uuid, 9, fixed_id, classification,
       CASE basis WHEN 'permanent' THEN 'AD' ELSE 'CA' END,
       (24 + (fixed_id % 10)) * multiplier, 'Hourly', '2025-07-01', 2025, '{}'::jsonb
FROM levels CROSS JOIN bases
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    employee_rate_type_code = EXCLUDED.employee_rate_type_code,
    calculated_rate = EXCLUDED.calculated_rate,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

DELETE FROM award_level_base_rates
WHERE award_level_id IN (
    'a1000000-0000-0000-0000-000000000111', 'a1000000-0000-0000-0000-000000000112',
    'a1000000-0000-0000-0000-000000000113', 'a1000000-0000-0000-0000-000000000121',
    'a1000000-0000-0000-0000-000000000114', 'a1000000-0000-0000-0000-000000000115',
    'a1000000-0000-0000-0000-000000000116'
);
WITH levels(id, fixed_id) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242), ('a1000000-0000-0000-0000-000000000111'::uuid, 243),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246), ('a1000000-0000-0000-0000-000000000113'::uuid, 257),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268), ('a1000000-0000-0000-0000-000000000115'::uuid, 276),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282)
), bases(basis, multiplier) AS (VALUES ('permanent'::staff_employment_basis_enum, 1.0::numeric), ('casual'::staff_employment_basis_enum, 1.25::numeric))
INSERT INTO award_level_base_rates (id, award_level_id, employment_basis, fwc_mapd_pay_rate_id, hourly_rate, rate_label, operative_from, published_year)
SELECT md5('e2e-base-' || fixed_id || '-' || basis::text)::uuid, id, basis,
       md5('e2e-base-source-' || fixed_id || '-' || basis::text)::uuid,
       (24 + (fixed_id % 10)) * multiplier, 'E2E canonical base', '2025-07-01', 2025
FROM levels CROSS JOIN bases;

WITH levels(id, fixed_id, classification) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242, 'Introductory'), ('a1000000-0000-0000-0000-000000000111'::uuid, 243, 'Level 1'),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246, 'Level 2'), ('a1000000-0000-0000-0000-000000000113'::uuid, 257, 'Level 3'),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268, 'Level 4'), ('a1000000-0000-0000-0000-000000000115'::uuid, 276, 'Level 5'),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282, 'Level 6')
), bases(basis, multiplier) AS (VALUES ('permanent'::staff_employment_basis_enum, 1.0::numeric), ('casual'::staff_employment_basis_enum, 1.25::numeric)),
penalties(kind, multiplier, fixed_offset, label) AS (
    VALUES ('saturday_penalty'::award_penalty_kind_enum, 1.25::numeric, 1, 'Saturday'),
           ('sunday_penalty'::award_penalty_kind_enum, 1.50::numeric, 2, 'Sunday'),
           ('public_holiday_penalty'::award_penalty_kind_enum, 2.25::numeric, 3, 'Public holiday')
)
INSERT INTO fwc_mapd_penalty_rates (id, award_fixed_id, classification_fixed_id, classification, employee_rate_type_code, penalty_fixed_id, penalty_description, penalty_calculated_value, operative_from, published_year, raw_json)
SELECT md5('e2e-penalty-source-' || fixed_id || '-' || basis::text || '-' || kind::text)::uuid,
       9, fixed_id, classification, CASE basis WHEN 'permanent' THEN 'AD' ELSE 'CA' END,
       fixed_id * 10 + fixed_offset, label, (24 + (fixed_id % 10)) * bases.multiplier * penalties.multiplier,
       '2025-07-01', 2025, '{}'::jsonb
FROM levels CROSS JOIN bases CROSS JOIN penalties
ON CONFLICT (id) DO UPDATE SET
    award_fixed_id = EXCLUDED.award_fixed_id,
    classification_fixed_id = EXCLUDED.classification_fixed_id,
    classification = EXCLUDED.classification,
    employee_rate_type_code = EXCLUDED.employee_rate_type_code,
    penalty_fixed_id = EXCLUDED.penalty_fixed_id,
    penalty_description = EXCLUDED.penalty_description,
    penalty_calculated_value = EXCLUDED.penalty_calculated_value,
    operative_from = EXCLUDED.operative_from,
    published_year = EXCLUDED.published_year,
    raw_json = EXCLUDED.raw_json,
    updated_at = NOW();

DELETE FROM award_level_penalty_rates
WHERE award_level_id IN (
    'a1000000-0000-0000-0000-000000000111', 'a1000000-0000-0000-0000-000000000112',
    'a1000000-0000-0000-0000-000000000113', 'a1000000-0000-0000-0000-000000000121',
    'a1000000-0000-0000-0000-000000000114', 'a1000000-0000-0000-0000-000000000115',
    'a1000000-0000-0000-0000-000000000116'
);
WITH levels(id, fixed_id) AS (
    VALUES
        ('a1000000-0000-0000-0000-000000000114'::uuid, 242), ('a1000000-0000-0000-0000-000000000111'::uuid, 243),
        ('a1000000-0000-0000-0000-000000000112'::uuid, 246), ('a1000000-0000-0000-0000-000000000113'::uuid, 257),
        ('a1000000-0000-0000-0000-000000000121'::uuid, 268), ('a1000000-0000-0000-0000-000000000115'::uuid, 276),
        ('a1000000-0000-0000-0000-000000000116'::uuid, 282)
), bases(basis, basis_multiplier) AS (VALUES ('permanent'::staff_employment_basis_enum, 1.0::numeric), ('casual'::staff_employment_basis_enum, 1.25::numeric)),
penalties(kind, penalty_multiplier) AS (
    VALUES ('saturday_penalty'::award_penalty_kind_enum, 1.25::numeric),
           ('sunday_penalty'::award_penalty_kind_enum, 1.50::numeric),
           ('public_holiday_penalty'::award_penalty_kind_enum, 2.25::numeric)
)
INSERT INTO award_level_penalty_rates (id, award_level_id, employment_basis, penalty_kind, fwc_mapd_penalty_rate_id, hourly_rate, operative_from, published_year)
SELECT md5('e2e-penalty-' || fixed_id || '-' || basis::text || '-' || kind::text)::uuid,
       id, basis, kind, md5('e2e-penalty-source-' || fixed_id || '-' || basis::text || '-' || kind::text)::uuid,
       (24 + (fixed_id % 10)) * basis_multiplier * penalty_multiplier, '2025-07-01', 2025
FROM levels CROSS JOIN bases CROSS JOIN penalties;

UPDATE fwc_mapd_wage_allowances SET award_fixed_id = 9, operative_from = '2025-07-01', operative_to = NULL
WHERE id IN ('a1000000-0000-0000-0000-000000000731', 'a1000000-0000-0000-0000-000000000732');
UPDATE award_time_penalty_allowances SET award_fixed_id = 9, operative_from = '2025-07-01', operative_to = NULL
WHERE id IN ('a1000000-0000-0000-0000-000000000741', 'a1000000-0000-0000-0000-000000000742');

INSERT INTO fwc_mapd_sync_runs (id, status, requested_award_fixed_ids, synced_award_fixed_ids, fetched_award_count, fetched_classification_count, fetched_pay_rate_count, fetched_penalty_rate_count, fetched_wage_allowance_count, started_at, finished_at)
VALUES ('a1000000-0000-0000-0000-000000000799', 'succeeded', ARRAY[9], ARRAY[9], 1, 7, 14, 42, 2, NOW() - INTERVAL '1 minute', NOW())
ON CONFLICT (id) DO UPDATE SET
    status = EXCLUDED.status,
    requested_award_fixed_ids = EXCLUDED.requested_award_fixed_ids,
    synced_award_fixed_ids = EXCLUDED.synced_award_fixed_ids,
    fetched_award_count = EXCLUDED.fetched_award_count,
    fetched_classification_count = EXCLUDED.fetched_classification_count,
    fetched_pay_rate_count = EXCLUDED.fetched_pay_rate_count,
    fetched_penalty_rate_count = EXCLUDED.fetched_penalty_rate_count,
    fetched_wage_allowance_count = EXCLUDED.fetched_wage_allowance_count,
    started_at = EXCLUDED.started_at,
    finished_at = EXCLUDED.finished_at,
    updated_at = NOW();

INSERT INTO public_holidays (id, jurisdiction, holiday_date, name, is_regional, source, source_id, imported_at)
VALUES ('a1000000-0000-0000-0000-000000000798', 'VIC', '2026-01-01', 'E2E statewide source freshness', FALSE, 'data-vic-e2e', 'e2e-vic-2026', NOW())
ON CONFLICT (id) DO UPDATE SET
    jurisdiction = EXCLUDED.jurisdiction,
    holiday_date = EXCLUDED.holiday_date,
    name = EXCLUDED.name,
    is_regional = EXCLUDED.is_regional,
    source = EXCLUDED.source,
    source_id = EXCLUDED.source_id,
    imported_at = EXCLUDED.imported_at,
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
    pay_assignment_mode,
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'roster_only',
        NULL,
        TRUE
    )
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    user_id = EXCLUDED.user_id,
    first_name = EXCLUDED.first_name,
    last_name = EXCLUDED.last_name,
    preferred_name = EXCLUDED.preferred_name,
    phone = EXCLUDED.phone,
    emergency_contact_name = EXCLUDED.emergency_contact_name,
    emergency_contact_phone = EXCLUDED.emergency_contact_phone,
    ideal_shifts_per_week = EXCLUDED.ideal_shifts_per_week,
    employment_basis = EXCLUDED.employment_basis,
    pay_assignment_mode = EXCLUDED.pay_assignment_mode,
    default_award_level_id = EXCLUDED.default_award_level_id,
    imported_xero_pay_item_id = NULL,
    is_active = EXCLUDED.is_active,
    archived_at = NULL,
    archived_by_user_id = NULL,
    archive_reason = NULL;

INSERT INTO shift_types (id, venue_id, name, sort_order, pay_assignment_mode, override_award_level_id, is_active)
VALUES
    ('a1000000-0000-0000-0000-000000000131', 'a1000000-0000-0000-0000-000000000001', 'Bar', 10, 'award_rate', 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000132', 'a1000000-0000-0000-0000-000000000001', 'Kitchen', 20, 'award_rate', 'a1000000-0000-0000-0000-000000000111', TRUE),
    ('a1000000-0000-0000-0000-000000000133', 'a1000000-0000-0000-0000-000000000001', 'Front of House Supervisor and Closing Coordinator for Private Functions and Special Events', 30, 'award_rate', 'a1000000-0000-0000-0000-000000000113', TRUE),
    ('a1000000-0000-0000-0000-000000000141', 'a1000000-0000-0000-0000-000000000002', 'Beta Shift', 10, 'award_rate', 'a1000000-0000-0000-0000-000000000121', TRUE)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    pay_assignment_mode = EXCLUDED.pay_assignment_mode,
    override_award_level_id = EXCLUDED.override_award_level_id,
    imported_xero_pay_item_id = NULL,
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
    pay_assignment_mode,
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
    pay_assignment_mode = EXCLUDED.pay_assignment_mode,
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
    pay_assignment_mode,
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
        'award_rate',
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
    pay_assignment_mode = EXCLUDED.pay_assignment_mode,
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

INSERT INTO roster_days (id, venue_id, roster_group_id, operational_date, publication_state, is_closed, row_count)
VALUES
    ('a1000000-0000-0000-0000-000000000061', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1), 'draft', FALSE, 4),
    ('a1000000-0000-0000-0000-000000000063', 'a1000000-0000-0000-0000-000000000001', 'a1000000-0000-0000-0000-000000000211', CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 7, 'draft', FALSE, 4),
    ('a1000000-0000-0000-0000-000000000062', 'a1000000-0000-0000-0000-000000000002', 'a1000000-0000-0000-0000-000000000212', CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1), 'draft', FALSE, 4)
ON CONFLICT (id) DO UPDATE SET
    venue_id = EXCLUDED.venue_id,
    roster_group_id = EXCLUDED.roster_group_id,
    operational_date = EXCLUDED.operational_date,
    publication_state = EXCLUDED.publication_state,
    is_closed = EXCLUDED.is_closed,
    row_count = EXCLUDED.row_count;

INSERT INTO roster_lanes (id, roster_day_id, name, sort_order)
VALUES
    ('a1000000-0000-0000-0000-000000000081', 'a1000000-0000-0000-0000-000000000061', 'Early', 0),
    ('a1000000-0000-0000-0000-000000000082', 'a1000000-0000-0000-0000-000000000062', 'Late', 0),
    ('a1000000-0000-0000-0000-000000000083', 'a1000000-0000-0000-0000-000000000063', 'Early', 0)
ON CONFLICT (id) DO UPDATE SET
    roster_day_id = EXCLUDED.roster_day_id,
    name = EXCLUDED.name,
    sort_order = EXCLUDED.sort_order,
    deleted_at = NULL,
    updated_at = NOW();

INSERT INTO roster_slots (id, roster_day_id, staff_id, assignment_state, roster_lane_id, row_index, starts_at, ends_at, timezone, shift_type_id)
VALUES
    (
        'a1000000-0000-0000-0000-000000000071',
        'a1000000-0000-0000-0000-000000000061',
        'a1000000-0000-0000-0000-000000000031',
        'staff',
        'a1000000-0000-0000-0000-000000000081',
        0,
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '17:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        'a1000000-0000-0000-0000-000000000133'
    ),
    (
        'a1000000-0000-0000-0000-000000000072',
        'a1000000-0000-0000-0000-000000000062',
        'a1000000-0000-0000-0000-000000000032',
        'staff',
        'a1000000-0000-0000-0000-000000000082',
        0,
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '17:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        'a1000000-0000-0000-0000-000000000141'
    ),
    (
        'a1000000-0000-0000-0000-000000000073',
        'a1000000-0000-0000-0000-000000000063',
        'a1000000-0000-0000-0000-000000000031',
        'staff',
        'a1000000-0000-0000-0000-000000000083',
        0,
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 7) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 7) + TIME '13:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        'a1000000-0000-0000-0000-000000000133'
    ),
    (
        'a1000000-0000-0000-0000-000000000074',
        'a1000000-0000-0000-0000-000000000063',
        'a1000000-0000-0000-0000-000000000031',
        'staff',
        'a1000000-0000-0000-0000-000000000083',
        1,
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 7) + TIME '13:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 7) + TIME '17:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        'a1000000-0000-0000-0000-000000000133'
    )
ON CONFLICT (id) DO UPDATE SET
    roster_day_id = EXCLUDED.roster_day_id,
    staff_id = EXCLUDED.staff_id,
    assignment_state = EXCLUDED.assignment_state,
    roster_lane_id = EXCLUDED.roster_lane_id,
    row_index = EXCLUDED.row_index,
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    timezone = EXCLUDED.timezone,
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
    starts_at,
    ends_at,
    timezone,
    operational_date,
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
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '08:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '16:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date,
        NULL,
        NULL,
        FALSE,
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000092',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000132',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1) + TIME '10:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1) + TIME '14:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1)::date,
        NULL,
        NULL,
        FALSE,
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000093',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000131',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4) + TIME '19:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5) + TIME '01:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4)::date,
        NULL,
        NULL,
        FALSE,
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000094',
        'a1000000-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000101',
        'a1000000-0000-0000-0000-000000000133',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '11:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date,
        NULL,
        NULL,
        FALSE,
        NULL,
        NULL
    ),
    (
        'a1000000-0000-0000-0000-000000000096',
        'a1000000-0000-0000-0000-000000000001',
        'a1000000-0000-0000-0000-000000000031',
        'a1000000-0000-0000-0000-000000000133',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 2) + TIME '12:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 2) + TIME '15:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 2)::date,
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
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne',
        ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '17:00') AT TIME ZONE 'Australia/Melbourne',
        'Australia/Melbourne',
        (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date,
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
    starts_at = EXCLUDED.starts_at,
    ends_at = EXCLUDED.ends_at,
    timezone = EXCLUDED.timezone,
    operational_date = EXCLUDED.operational_date,
    staff_pay_version_id = EXCLUDED.staff_pay_version_id,
    shift_type_pay_version_id = EXCLUDED.shift_type_pay_version_id,
    is_approved = EXCLUDED.is_approved,
    approved_at = EXCLUDED.approved_at,
    approved_by_user_id = EXCLUDED.approved_by_user_id;

-- Approved payroll fixtures are staged as drafts above, then sealed against
-- exact paid-time/component facts before the approval state is applied.
INSERT INTO timesheet_pay_calculations (
    id, timesheet_entry_id, calculation_version, calculation_source,
    rate_book_version, operational_date, roster_window_start, roster_week_starts_on,
    venue_timezone, holiday_jurisdiction,
    staff_pay_version_id, shift_type_pay_version_id, approved_at,
    approved_by_user_id
)
VALUES
    ('a2000000-0000-0000-0000-000000000091', 'a1000000-0000-0000-0000-000000000091', 'hospitality-award-v1', 'hospitality_award', 'e2e-rate-book', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 1, 'Australia/Melbourne', 'VIC', 'a1000000-0000-0000-0000-000000000302', 'a1000000-0000-0000-0000-000000000311', '2025-01-12 01:00:00+00', 'a0000000-0000-0000-0000-000000000001'),
    ('a2000000-0000-0000-0000-000000000092', 'a1000000-0000-0000-0000-000000000092', 'hospitality-award-v1', 'hospitality_award', 'e2e-rate-book', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1)::date, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 1, 'Australia/Melbourne', 'VIC', 'a1000000-0000-0000-0000-000000000302', 'a1000000-0000-0000-0000-000000000312', '2025-01-12 01:05:00+00', 'a0000000-0000-0000-0000-000000000001'),
    ('a2000000-0000-0000-0000-000000000093', 'a1000000-0000-0000-0000-000000000093', 'hospitality-award-v1', 'hospitality_award', 'e2e-rate-book', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4)::date, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 1, 'Australia/Melbourne', 'VIC', 'a1000000-0000-0000-0000-000000000302', 'a1000000-0000-0000-0000-000000000311', '2025-01-12 01:10:00+00', 'a0000000-0000-0000-0000-000000000001'),
    ('a2000000-0000-0000-0000-000000000094', 'a1000000-0000-0000-0000-000000000094', 'hospitality-award-v1', 'hospitality_award', 'e2e-rate-book', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 1, 'Australia/Melbourne', 'VIC', 'a1000000-0000-0000-0000-000000000301', 'a1000000-0000-0000-0000-000000000313', '2025-01-12 01:15:00+00', 'a0000000-0000-0000-0000-000000000003');

INSERT INTO timesheet_pay_time_segments (
    id, timesheet_pay_calculation_id, ordinal, paid_time_kind,
    starts_at, ends_at, local_date, source_condition
)
VALUES
    ('a2100000-0000-0000-0000-000000000091', 'a2000000-0000-0000-0000-000000000091', 0, 'worked', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '08:00') AT TIME ZONE 'Australia/Melbourne', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '16:00') AT TIME ZONE 'Australia/Melbourne', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 'ordinary'),
    ('a2100000-0000-0000-0000-000000000092', 'a2000000-0000-0000-0000-000000000092', 0, 'worked', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1) + TIME '10:00') AT TIME ZONE 'Australia/Melbourne', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1) + TIME '14:00') AT TIME ZONE 'Australia/Melbourne', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1)::date, 'ordinary'),
    ('a2100000-0000-0000-0000-000000000093', 'a2000000-0000-0000-0000-000000000093', 0, 'worked', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4) + TIME '19:00') AT TIME ZONE 'Australia/Melbourne', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5) + TIME '00:00') AT TIME ZONE 'Australia/Melbourne', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4)::date, 'ordinary'),
    ('a2100000-0000-0000-0000-000000000193', 'a2000000-0000-0000-0000-000000000093', 1, 'worked', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5) + TIME '00:00') AT TIME ZONE 'Australia/Melbourne', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5) + TIME '01:00') AT TIME ZONE 'Australia/Melbourne', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5)::date, 'saturday'),
    ('a2100000-0000-0000-0000-000000000094', 'a2000000-0000-0000-0000-000000000094', 0, 'worked', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '09:00') AT TIME ZONE 'Australia/Melbourne', ((CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1)) + TIME '11:00') AT TIME ZONE 'Australia/Melbourne', (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, 'ordinary');

INSERT INTO timesheet_pay_earnings_components (
    id, timesheet_pay_calculation_id, ordinal, quantity, unit_type,
    rate_per_unit, exact_amount, component_date, xero_mapping_legacy_fallback, source_condition, calculation_source,
    source_rate_identity
)
VALUES
    ('a2200000-0000-0000-0000-000000000091', 'a2000000-0000-0000-0000-000000000091', 0, 8, 'hours', 30, 240, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, TRUE, 'ordinary', 'hospitality_award', 'e2e:ordinary'),
    ('a2200000-0000-0000-0000-000000000092', 'a2000000-0000-0000-0000-000000000092', 0, 4, 'hours', 30, 120, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 1)::date, TRUE, 'ordinary', 'hospitality_award', 'e2e:ordinary'),
    ('a2200000-0000-0000-0000-000000000093', 'a2000000-0000-0000-0000-000000000093', 0, 5, 'hours', 30, 150, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4)::date, TRUE, 'ordinary', 'hospitality_award', 'e2e:ordinary'),
    ('a2200000-0000-0000-0000-000000000193', 'a2000000-0000-0000-0000-000000000093', 1, 1, 'hours', 45, 45, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 5)::date, TRUE, 'saturday', 'hospitality_award', 'e2e:saturday'),
    ('a2200000-0000-0000-0000-000000000293', 'a2000000-0000-0000-0000-000000000093', 2, 5, 'commenced_hours', 3, 15, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1) + 4)::date, TRUE, 'evening_after_7pm_addition', 'hospitality_award', 'e2e:evening'),
    ('a2200000-0000-0000-0000-000000000094', 'a2000000-0000-0000-0000-000000000094', 0, 2, 'hours', 30, 60, (CURRENT_DATE - ((EXTRACT(ISODOW FROM CURRENT_DATE)::INT) - 1))::date, TRUE, 'ordinary', 'hospitality_award', 'e2e:ordinary');

UPDATE timesheet_pay_calculations
SET sealed_at = '2025-01-12 01:20:00+00'
WHERE id IN (
    'a2000000-0000-0000-0000-000000000091',
    'a2000000-0000-0000-0000-000000000092',
    'a2000000-0000-0000-0000-000000000093',
    'a2000000-0000-0000-0000-000000000094'
);

UPDATE timesheet_entries
SET staff_pay_version_id = CASE id
        WHEN 'a1000000-0000-0000-0000-000000000094' THEN 'a1000000-0000-0000-0000-000000000301'::uuid
        ELSE 'a1000000-0000-0000-0000-000000000302'::uuid
    END,
    shift_type_pay_version_id = CASE id
        WHEN 'a1000000-0000-0000-0000-000000000091' THEN 'a1000000-0000-0000-0000-000000000311'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000092' THEN 'a1000000-0000-0000-0000-000000000312'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000093' THEN 'a1000000-0000-0000-0000-000000000311'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000094' THEN 'a1000000-0000-0000-0000-000000000313'::uuid
    END,
    active_pay_calculation_id = CASE id
        WHEN 'a1000000-0000-0000-0000-000000000091' THEN 'a2000000-0000-0000-0000-000000000091'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000092' THEN 'a2000000-0000-0000-0000-000000000092'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000093' THEN 'a2000000-0000-0000-0000-000000000093'::uuid
        WHEN 'a1000000-0000-0000-0000-000000000094' THEN 'a2000000-0000-0000-0000-000000000094'::uuid
    END,
    is_approved = TRUE,
    approved_at = CASE id
        WHEN 'a1000000-0000-0000-0000-000000000091' THEN '2025-01-12 01:00:00+00'::timestamptz
        WHEN 'a1000000-0000-0000-0000-000000000092' THEN '2025-01-12 01:05:00+00'::timestamptz
        WHEN 'a1000000-0000-0000-0000-000000000093' THEN '2025-01-12 01:10:00+00'::timestamptz
        WHEN 'a1000000-0000-0000-0000-000000000094' THEN '2025-01-12 01:15:00+00'::timestamptz
    END,
    approved_by_user_id = CASE id
        WHEN 'a1000000-0000-0000-0000-000000000094' THEN 'a0000000-0000-0000-0000-000000000003'::uuid
        ELSE 'a0000000-0000-0000-0000-000000000001'::uuid
    END
WHERE id IN (
    'a1000000-0000-0000-0000-000000000091',
    'a1000000-0000-0000-0000-000000000092',
    'a1000000-0000-0000-0000-000000000093',
    'a1000000-0000-0000-0000-000000000094'
);
