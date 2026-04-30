-- Seed local dev Xero pay-item mappings that are tedious to recreate manually.
-- This file intentionally avoids token/tenant data and only links deterministic
-- local requirement keys to synced Xero earnings-rate names when they exist.

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
