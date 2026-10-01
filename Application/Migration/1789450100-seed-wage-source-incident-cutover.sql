-- A prior wage-source notification proves the condition was already surfaced.
-- Seed a cutover sentinel without copying payloads or recipient data so the first
-- reconciliation after deployment cannot blindly re-alert historical problems.
INSERT INTO operational_incidents (
    category,
    scope_key,
    stable_identity,
    affected_source,
    first_observed_at,
    last_observed_at,
    opened_at,
    state,
    severity,
    impact_key,
    impact_rank,
    symptom_codes,
    safe_metadata,
    occurrence_count
)
SELECT
    'wage_source',
    'global',
    source_identity,
    source_identity,
    MIN(created_at),
    MAX(created_at),
    MIN(created_at),
    'open',
    'warning',
    'legacy_notified_cutover',
    100,
    '["legacy_notification_history"]'::JSONB,
    jsonb_build_object('cutover', 'legacy_email_delivery_history'),
    1
FROM (
    SELECT
        created_at,
        CASE
            WHEN payload->>'mailKind' LIKE 'wage_source_fwc_mapd_%' THEN 'fwc_mapd'
            WHEN payload->>'mailKind' LIKE 'wage_source_data_vic_public_holidays_%' THEN 'data_vic_public_holidays'
            ELSE NULL
        END AS source_identity
    FROM app_jobs
    WHERE job_kind = 'email_delivery'
) historical
WHERE source_identity IS NOT NULL
GROUP BY source_identity
ON CONFLICT (category, scope_key, stable_identity) DO NOTHING;
