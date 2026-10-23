INSERT INTO users (id, email, password_hash) VALUES
('66400000-0000-0000-0000-000000000003', 'migration-664@example.invalid', 'not-a-login-hash');
INSERT INTO venues (id, name) VALUES
('66400000-0000-0000-0000-000000000001', 'Changed payroll day fixture'),
('66400000-0000-0000-0000-000000000002', 'Unchanged payroll day fixture');
INSERT INTO venue_config (venue_id, timezone, roster_week_starts_on) VALUES
('66400000-0000-0000-0000-000000000001', 'Australia/Melbourne', 3),
('66400000-0000-0000-0000-000000000002', 'Australia/Melbourne', 0);
INSERT INTO payroll_workbook_configurations (id, venue_id, name, created_by_user_id)
SELECT id, id, 'Fixture template', '66400000-0000-0000-0000-000000000003'
FROM venues WHERE id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002');
INSERT INTO payroll_report_settings (id, venue_id, configuration_id, recipients, enabled, weekday, minute_of_day,
    revision, delivery_revision, schedule_activated_at, updated_by_user_id)
SELECT id, id, id, ARRAY['payroll@example.invalid'], TRUE,
    CASE WHEN id = '66400000-0000-0000-0000-000000000001' THEN 5 ELSE 0 END,
    570, 4, 7, '2025-01-01T00:00:00Z', '66400000-0000-0000-0000-000000000003'
FROM venues WHERE id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002');
INSERT INTO payroll_report_runs (venue_id, settings_id, reporting_week, range_end, origin, status, recipients,
    template_snapshot, delivery_revision, schedule_activated_at, scheduled_at, requested_by_user_id)
SELECT settings.venue_id, settings.id, DATE '2025-01-06' + (item.n * 7), DATE '2025-01-12' + (item.n * 7),
    item.origin::payroll_report_origin_enum, item.status::payroll_report_status_enum, settings.recipients,
    '{"fixture":664}', 7, settings.schedule_activated_at, '2025-01-20T00:00:00Z', settings.updated_by_user_id
FROM payroll_report_settings settings
CROSS JOIN (VALUES
    (0, 'payroll_report_scheduled', 'payroll_report_ready'),
    (1, 'payroll_report_scheduled', 'payroll_report_no_data'),
    (2, 'payroll_report_scheduled', 'payroll_report_queued'),
    (3, 'payroll_report_scheduled', 'payroll_report_accepted'),
    (4, 'payroll_report_manual', 'payroll_report_queued'),
    (5, 'payroll_report_updated', 'payroll_report_queued')
) AS item(n, origin, status)
WHERE settings.id IN ('66400000-0000-0000-0000-000000000001', '66400000-0000-0000-0000-000000000002');
