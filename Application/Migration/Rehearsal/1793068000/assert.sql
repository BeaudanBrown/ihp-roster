DO $$
BEGIN
    IF (SELECT count(*) FROM recipient_groups) <> 0 THEN
        RAISE EXCEPTION 'recipient group migration must not fabricate groups';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM payroll_report_settings
        WHERE id = '66600000-0000-0000-0000-000000000004'
            AND venue_id = '66600000-0000-0000-0000-000000000001'
            AND configuration_id = '66600000-0000-0000-0000-000000000002'
            AND recipient_group_id IS NULL AND recipients = ARRAY['legacy@example.invalid']
            AND enabled AND weekday = 3 AND minute_of_day = 570
            AND revision = 4 AND delivery_revision = 7
            AND schedule_activated_at = '2025-01-01T00:00:00Z'
            AND created_at = '2025-01-01T00:00:00Z' AND updated_at = '2025-01-01T00:00:00Z'
            AND updated_by_user_id = '66600000-0000-0000-0000-000000000003'
    ) THEN
        RAISE EXCEPTION 'recipient group migration altered legacy settings';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id = '66600000-0000-0000-0000-000000000004'
            AND recipients = ARRAY['snapshot@example.invalid']
            AND template_snapshot = '{"fixture":666}'::jsonb AND delivery_revision = 6
            AND schedule_activated_at = '2024-12-01T00:00:00Z'
            AND scheduled_at = '2025-01-20T00:00:00Z'
            AND requested_by_user_id = '66600000-0000-0000-0000-000000000003'
            AND range_end = reporting_week + 6
            AND ((reporting_week = DATE '2025-01-01' AND origin = 'payroll_report_scheduled' AND status = 'payroll_report_queued')
                OR (reporting_week = DATE '2025-01-08' AND origin = 'payroll_report_scheduled' AND status = 'payroll_report_accepted')
                OR (reporting_week = DATE '2025-01-15' AND origin = 'payroll_report_manual' AND status = 'payroll_report_queued')
                OR (reporting_week = DATE '2025-01-22' AND origin = 'payroll_report_updated' AND status = 'payroll_report_ambiguous'))
    ) <> 4 THEN
        RAISE EXCEPTION 'recipient group migration altered prepared or terminal snapshots';
    END IF;
END $$;
