INSERT INTO venues (id, name) VALUES ('d6380000-0000-0000-0000-000000000001', 'Recipient migration fixture');
INSERT INTO users (id, email, password_hash) VALUES ('d6380000-0000-0000-0000-000000000002', 'recipient-owner@example.test', 'synthetic');
INSERT INTO daysheet_definition_versions (id, venue_id, version_number, definition, reference_data, published_by) VALUES
    ('d6380000-0000-0000-0000-000000000003', 'd6380000-0000-0000-0000-000000000001', 1, '{}', '{}', 'd6380000-0000-0000-0000-000000000002');
INSERT INTO app_jobs (id, job_kind, payload_schema_version, payload, dedupe_key) VALUES
    ('d6380000-0000-0000-0000-000000000004', 'email_delivery', 1, '{"mailKind":"venue_invitation_v1","recipientAccountId":"d6380000-0000-0000-0000-000000000099","recipientAddress":"legacy@example.test","domainReferenceId":"d6380000-0000-0000-0000-000000000099"}', 'retained-legacy-dedupe-fixture');
