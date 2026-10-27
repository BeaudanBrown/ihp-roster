DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM payroll_report_settings
        WHERE id = '66900000-0000-0000-0000-000000000004'
          AND minute_of_day = 570 AND weekday = 3 AND enabled
          AND revision = 4 AND delivery_revision = 7 AND recipient_group_id IS NULL
          AND recipients = ARRAY['legacy@example.invalid']
          AND schedule_activated_at = '2025-01-01T00:00:00Z'
          AND created_at = '2025-01-01T00:00:00Z' AND updated_at = '2025-01-01T00:00:00Z'
    ) THEN RAISE EXCEPTION 'default migration changed legacy schedule'; END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE venue_id = '66900000-0000-0000-0000-000000000001'
          AND recipients = ARRAY['snapshot@example.invalid'] AND template_snapshot = '{"fixture":669}'::jsonb
          AND delivery_revision = 6 AND schedule_activated_at = '2024-12-01T00:00:00Z') <> 4
    THEN RAISE EXCEPTION 'default migration changed immutable snapshots'; END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE venue_id = '66900000-0000-0000-0000-000000000001'
          AND ((origin = 'payroll_report_scheduled' AND status IN ('payroll_report_queued', 'payroll_report_accepted'))
            OR (origin = 'payroll_report_manual' AND status = 'payroll_report_queued')
            OR (origin = 'payroll_report_updated' AND status = 'payroll_report_ambiguous'))) <> 4
    THEN RAISE EXCEPTION 'default migration changed delivery state'; END IF;
    IF (SELECT column_default FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'payroll_report_settings' AND column_name = 'minute_of_day') <> '360'
    THEN RAISE EXCEPTION 'new schedule default is not 06:00'; END IF;
END $$;
