-- Synthetic legacy notification history proves that cutover is additive,
-- source-bounded, and does not replay historical email.
INSERT INTO app_jobs (id, created_at, updated_at, status, job_kind, payload)
VALUES
    ('10000000-0000-0000-0000-000000000001', TIMESTAMPTZ '2026-01-01 00:00:00+00', TIMESTAMPTZ '2026-01-01 00:00:00+00', 'job_status_succeeded', 'email_delivery', '{"mailKind":"wage_source_fwc_mapd_failed"}'::JSONB),
    ('10000000-0000-0000-0000-000000000002', TIMESTAMPTZ '2026-02-01 00:00:00+00', TIMESTAMPTZ '2026-02-01 00:00:00+00', 'job_status_succeeded', 'email_delivery', '{"mailKind":"wage_source_data_vic_public_holidays_stale"}'::JSONB),
    ('10000000-0000-0000-0000-000000000003', TIMESTAMPTZ '2026-03-01 00:00:00+00', TIMESTAMPTZ '2026-03-01 00:00:00+00', 'job_status_succeeded', 'email_delivery', '{"mailKind":"unrelated_fixture"}'::JSONB);
