INSERT INTO venues (id, name) VALUES ('d6350000-0000-0000-0000-000000000001', 'Daily migration fixture');
INSERT INTO users (id, email, password_hash) VALUES ('d6350000-0000-0000-0000-000000000002', 'daily-owner@example.test', 'synthetic');
INSERT INTO daysheet_definition_versions (id, venue_id, version_number, definition, reference_data, published_by) VALUES
    ('d6350000-0000-0000-0000-000000000003', 'd6350000-0000-0000-0000-000000000001', 1, '{"contractVersion":1,"rootFields":[],"recordLists":[],"entryLayout":[],"reports":[]}', '{"lists":[]}', 'd6350000-0000-0000-0000-000000000002');
INSERT INTO daysheet_definition_captures (id, venue_id, operational_date, timezone, definition_version_id, reference_data, captured_by) VALUES
    ('d6350000-0000-0000-0000-000000000004', 'd6350000-0000-0000-0000-000000000001', '2026-10-01', 'Australia/Melbourne', 'd6350000-0000-0000-0000-000000000003', '{"lists":[]}', 'd6350000-0000-0000-0000-000000000002');
