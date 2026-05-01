-- Seed local dev Xero mappings that are tedious to recreate manually.
-- This file intentionally avoids token/tenant data and only links deterministic
-- local records to synced Xero reference data when that reference data exists.

WITH xero_matched_staff(first_name, last_name) AS (
    VALUES
        ('Alice', 'Front'),
        ('Bob', 'Both'),
        ('James', 'Lebron'),
        ('Oliver', 'Grey'),
        ('Odette', 'Garrison'),
        ('Sally', 'Martin'),
        ('Tracy', 'Green')
),
candidate_staff AS (
    SELECT
        connection.venue_id,
        connection.id AS xero_connection_id,
        staff.id AS staff_id,
        staff.first_name,
        staff.last_name,
        connection.connected_by_user_id
    FROM xero_connections connection
    JOIN staff
        ON staff.venue_id = connection.venue_id
    JOIN xero_matched_staff
        ON xero_matched_staff.first_name = staff.first_name
        AND xero_matched_staff.last_name = staff.last_name
    WHERE connection.connection_status = 'active'
),
ranked_employee_matches AS (
    SELECT
        candidate_staff.*,
        employee.xero_employee_id,
        employee.display_name AS xero_employee_name,
        employee.email AS xero_employee_email,
        COUNT(*) OVER (PARTITION BY candidate_staff.xero_connection_id, candidate_staff.staff_id) AS match_count,
        ROW_NUMBER() OVER (
            PARTITION BY candidate_staff.xero_connection_id, candidate_staff.staff_id
            ORDER BY
                CASE WHEN employee.status = 'ACTIVE' THEN 0 ELSE 1 END,
                employee.synced_at DESC,
                employee.xero_employee_id
        ) AS match_rank
    FROM candidate_staff
    JOIN xero_employees employee
        ON employee.xero_connection_id = candidate_staff.xero_connection_id
        AND LOWER(employee.display_name) = LOWER(candidate_staff.first_name || ' ' || candidate_staff.last_name)
        AND COALESCE(employee.raw_payload->>'source', '') <> 'seed-dev'
),
matched_staff AS (
    SELECT *
    FROM ranked_employee_matches
    WHERE match_count = 1
        AND match_rank = 1
)
INSERT INTO xero_staff_mappings (
    venue_id,
    staff_id,
    xero_connection_id,
    xero_employee_id,
    xero_employee_name,
    xero_employee_email,
    mapping_status,
    last_verified_at,
    created_by_user_id,
    updated_by_user_id
)
SELECT
    venue_id,
    staff_id,
    xero_connection_id,
    xero_employee_id,
    xero_employee_name,
    xero_employee_email,
    'verified',
    NOW(),
    connected_by_user_id,
    connected_by_user_id
FROM matched_staff
ON CONFLICT (staff_id, xero_connection_id)
DO UPDATE SET
    xero_employee_id = EXCLUDED.xero_employee_id,
    xero_employee_name = EXCLUDED.xero_employee_name,
    xero_employee_email = EXCLUDED.xero_employee_email,
    mapping_status = EXCLUDED.mapping_status,
    last_verified_at = EXCLUDED.last_verified_at,
    updated_by_user_id = EXCLUDED.updated_by_user_id,
    updated_at = NOW();

WITH desired_mappings(requirement_key, display_name, penalty_kind) AS (
    VALUES
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:ordinary', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Ordinary', NULL),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:evening_after_7pm', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Evening After 7pm Loading', 'evening_after_7pm'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:late_night_after_midnight', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Late Night After Midnight Loading', 'late_night_after_midnight'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:public_holiday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Public Holiday Penalty', 'public_holiday_penalty'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:saturday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Saturday Penalty', 'saturday_penalty'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:sunday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Sunday Penalty', 'sunday_penalty')
),
matched_rates AS (
    SELECT
        connection.venue_id,
        connection.id AS xero_connection_id,
        desired.requirement_key,
        desired.display_name,
        desired.penalty_kind,
        rate.xero_earnings_rate_id,
        rate.name AS xero_earnings_rate_name,
        rate.rate_type AS xero_earnings_rate_rate_type
    FROM desired_mappings desired
    JOIN xero_connections connection ON TRUE
    JOIN xero_earnings_rates rate
        ON rate.xero_connection_id = connection.id
        AND rate.name = desired.display_name
        AND rate.is_active = TRUE
)
INSERT INTO xero_pay_item_requirement_records (
    venue_id,
    xero_connection_id,
    requirement_key,
    display_name,
    penalty_kind,
    earnings_type,
    rate_type,
    source_description,
    requirement_status,
    xero_earnings_rate_id,
    xero_earnings_rate_name,
    xero_earnings_rate_rate_type,
    last_verified_at
)
SELECT
    venue_id,
    xero_connection_id,
    requirement_key,
    display_name,
    penalty_kind,
    'ORDINARYTIMEEARNINGS',
    'RATEPERUNIT',
    'Seeded dev mapping for the local Xero sandbox pay item.',
    'matched',
    xero_earnings_rate_id,
    xero_earnings_rate_name,
    xero_earnings_rate_rate_type,
    NOW()
FROM matched_rates
ON CONFLICT (xero_connection_id, requirement_key)
DO UPDATE SET
    display_name = EXCLUDED.display_name,
    penalty_kind = EXCLUDED.penalty_kind,
    earnings_type = EXCLUDED.earnings_type,
    rate_type = EXCLUDED.rate_type,
    source_description = EXCLUDED.source_description,
    requirement_status = EXCLUDED.requirement_status,
    xero_earnings_rate_id = EXCLUDED.xero_earnings_rate_id,
    xero_earnings_rate_name = EXCLUDED.xero_earnings_rate_name,
    xero_earnings_rate_rate_type = EXCLUDED.xero_earnings_rate_rate_type,
    last_verified_at = EXCLUDED.last_verified_at,
    updated_at = NOW();

WITH desired_mappings(requirement_key, display_name) AS (
    VALUES
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:ordinary', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Ordinary'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:evening_after_7pm', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Evening After 7pm Loading'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:late_night_after_midnight', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Late Night After Midnight Loading'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:public_holiday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Public Holiday Penalty'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:saturday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Saturday Penalty'),
        ('xero:pay-item:classification:246:basis:casual:effective:2025-07-01:penalty:sunday_penalty', 'Bepis - HIGA - CAS - 1-July-2025 - Level 2 - Sunday Penalty')
),
matched_rates AS (
    SELECT
        connection.venue_id,
        connection.id AS xero_connection_id,
        desired.requirement_key,
        regexp_replace(desired.display_name, '^Bepis - ', '') AS local_bucket_label,
        rate.xero_earnings_rate_id,
        rate.name AS xero_earnings_rate_name
    FROM desired_mappings desired
    JOIN xero_connections connection ON TRUE
    JOIN xero_earnings_rates rate
        ON rate.xero_connection_id = connection.id
        AND rate.name = desired.display_name
        AND rate.is_active = TRUE
)
INSERT INTO xero_earnings_rate_mappings (
    venue_id,
    xero_connection_id,
    local_bucket_key,
    local_bucket_label,
    xero_earnings_rate_id,
    xero_earnings_rate_name,
    mapping_status,
    last_verified_at
)
SELECT
    venue_id,
    xero_connection_id,
    requirement_key,
    local_bucket_label,
    xero_earnings_rate_id,
    xero_earnings_rate_name,
    'verified',
    NOW()
FROM matched_rates
ON CONFLICT (xero_connection_id, local_bucket_key)
DO UPDATE SET
    local_bucket_label = EXCLUDED.local_bucket_label,
    xero_earnings_rate_id = EXCLUDED.xero_earnings_rate_id,
    xero_earnings_rate_name = EXCLUDED.xero_earnings_rate_name,
    mapping_status = EXCLUDED.mapping_status,
    last_verified_at = EXCLUDED.last_verified_at,
    updated_at = NOW();
