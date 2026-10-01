-- A synthetic legacy schedule deliberately uses a non-default time. Adding
-- group storage must neither convert it nor reinterpret its prepared recipients.
INSERT INTO users (id, email, password_hash) VALUES
('66600000-0000-0000-0000-000000000003', 'migration-666@example.invalid', 'not-a-login-hash');
INSERT INTO venues (id, name) VALUES
('66600000-0000-0000-0000-000000000001', 'Recipient group upgrade fixture');
INSERT INTO payroll_workbook_configurations (id, venue_id, name, created_by_user_id) VALUES
('66600000-0000-0000-0000-000000000002', '66600000-0000-0000-0000-000000000001', 'Fixture template', '66600000-0000-0000-0000-000000000003');
INSERT INTO payroll_report_settings (id, venue_id, configuration_id, recipients, enabled, weekday, minute_of_day,
    revision, delivery_revision, schedule_activated_at, updated_by_user_id, created_at, updated_at) VALUES
('66600000-0000-0000-0000-000000000004', '66600000-0000-0000-0000-000000000001', '66600000-0000-0000-0000-000000000002',
    ARRAY['legacy@example.invalid'], TRUE, 3, 570, 4, 7, '2025-01-01T00:00:00Z', '66600000-0000-0000-0000-000000000003', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');
INSERT INTO payroll_report_runs (venue_id, settings_id, reporting_week, range_end, origin, status, recipients,
    template_snapshot, delivery_revision, schedule_activated_at, scheduled_at, requested_by_user_id)
SELECT settings.venue_id, settings.id, DATE '2025-01-01' + (item.n * 7), DATE '2025-01-07' + (item.n * 7),
    item.origin::payroll_report_origin_enum, item.status::payroll_report_status_enum, ARRAY['snapshot@example.invalid'],
    '{"fixture":666}', 6, '2024-12-01T00:00:00Z', '2025-01-20T00:00:00Z', settings.updated_by_user_id
FROM payroll_report_settings settings
CROSS JOIN (VALUES
    (0, 'payroll_report_scheduled', 'payroll_report_queued'),
    (1, 'payroll_report_scheduled', 'payroll_report_accepted'),
    (2, 'payroll_report_manual', 'payroll_report_queued'),
    (3, 'payroll_report_updated', 'payroll_report_ambiguous')
) AS item(n, origin, status)
WHERE settings.id = '66600000-0000-0000-0000-000000000004';
