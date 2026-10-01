DO $$
BEGIN
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id = '66700000-0000-0000-0000-000000000004'
            AND venue_id = '66700000-0000-0000-0000-000000000001'
            AND configuration_id IS NULL AND recipient_group_id IS NULL AND recipient_group_revision IS NULL
            AND recipients = ARRAY['frozen@example.invalid']
            AND template_snapshot = '{"definitionKey":"saved-66700000-0000-0000-0000-000000000002","fixture":667}'::jsonb
            AND delivery_revision = 6 AND schedule_activated_at = '2024-12-01T00:00:00Z'
            AND scheduled_at = '2025-01-20T00:00:00Z'
            AND requested_by_user_id = '66700000-0000-0000-0000-000000000003'
            AND range_end = reporting_week + 6
            AND ((reporting_week = DATE '2025-01-01' AND origin = 'payroll_report_scheduled' AND status = 'payroll_report_queued')
                OR (reporting_week = DATE '2025-01-08' AND origin = 'payroll_report_scheduled' AND status = 'payroll_report_accepted')
                OR (reporting_week = DATE '2025-01-15' AND origin = 'payroll_report_manual' AND status = 'payroll_report_queued')
                OR (reporting_week = DATE '2025-01-22' AND origin = 'payroll_report_updated' AND status = 'payroll_report_ambiguous'))
    ) <> 4 THEN
        RAISE EXCEPTION 'standalone report migration changed legacy linkage or frozen provenance';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM payroll_report_settings
        WHERE id = '66700000-0000-0000-0000-000000000004'
            AND enabled AND minute_of_day = 570 AND revision = 4 AND delivery_revision = 7
            AND recipients = ARRAY['legacy@example.invalid'] AND recipient_group_id IS NULL)
    THEN
        RAISE EXCEPTION 'standalone report migration changed automatic settings';
    END IF;
END $$;
