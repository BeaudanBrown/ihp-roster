DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM payroll_report_settings
        WHERE id = '66400000-0000-0000-0000-000000000001'
          AND weekday = 3 AND revision = 5 AND schedule_activated_at > '2025-01-01T00:00:00Z') THEN
        RAISE EXCEPTION 'Changed schedule was not aligned and restarted';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM payroll_report_settings
        WHERE id = '66400000-0000-0000-0000-000000000002'
          AND weekday = 0 AND revision = 4 AND schedule_activated_at = '2025-01-01T00:00:00Z') THEN
        RAISE EXCEPTION 'Already aligned schedule was modified';
    END IF;
    IF (SELECT count(*) FROM payroll_report_settings
        WHERE id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002')
          AND configuration_id = venue_id AND recipients = ARRAY['payroll@example.invalid']
          AND enabled AND minute_of_day = 570 AND delivery_revision = 7
          AND updated_by_user_id = '66400000-0000-0000-0000-000000000003') <> 2 THEN
        RAISE EXCEPTION 'Settings payload was not preserved';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id = '66400000-0000-0000-0000-000000000001'
          AND status = 'payroll_report_cancelled' AND origin = 'payroll_report_scheduled') <> 3 THEN
        RAISE EXCEPTION 'Pending automatic sends were not cancelled';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002')
          AND origin <> 'payroll_report_scheduled' AND status = 'payroll_report_queued') <> 4 THEN
        RAISE EXCEPTION 'Explicit manual or updated sends changed';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002')
          AND status = 'payroll_report_accepted') <> 2 THEN
        RAISE EXCEPTION 'Terminal history changed';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id = '66400000-0000-0000-0000-000000000002'
          AND status IN ('payroll_report_ready', 'payroll_report_no_data', 'payroll_report_queued')) <> 5 THEN
        RAISE EXCEPTION 'Unchanged schedule runs changed';
    END IF;
    IF (SELECT count(*) FROM payroll_report_runs
        WHERE settings_id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002')
          AND recipients = ARRAY['payroll@example.invalid'] AND template_snapshot = '{"fixture":664}'::jsonb
          AND delivery_revision = 7 AND schedule_activated_at = '2025-01-01T00:00:00Z'
          AND range_end = reporting_week + 6) <> 12 THEN
        RAISE EXCEPTION 'Immutable run snapshots were not preserved';
    END IF;
END $$;
