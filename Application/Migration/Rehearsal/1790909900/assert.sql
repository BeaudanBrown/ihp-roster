DO $$
DECLARE
    rejected BOOLEAN := FALSE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app_jobs WHERE id = 'd6380000-0000-0000-0000-000000000004' AND payload_schema_version = 1 AND dedupe_key = 'retained-legacy-dedupe-fixture' AND payload = '{"mailKind":"venue_invitation_v1","recipientAccountId":"d6380000-0000-0000-0000-000000000099","recipientAddress":"legacy@example.test","domainReferenceId":"d6380000-0000-0000-0000-000000000099"}'::JSONB) THEN
        RAISE EXCEPTION 'external recipient migration rewrote legacy envelope or permanent dedupe identity';
    END IF;
    -- Recipient constraint scaffolding when the predecessor predates definitions.
    -- Legacy job preservation above is required in both rehearsal modes.
    INSERT INTO daysheet_definition_versions (id, venue_id, version_number, definition, reference_data, published_by) VALUES
        ('d6380000-0000-0000-0000-000000000003', 'd6380000-0000-0000-0000-000000000001', 1, '{}', '{}', 'd6380000-0000-0000-0000-000000000002')
        ON CONFLICT (id) DO NOTHING;
    INSERT INTO daysheet_report_recipients (id, venue_id, report_id, definition_version_id, address, created_by) VALUES
        ('d6380000-0000-0000-0000-000000000010', 'd6380000-0000-0000-0000-000000000001', 'd6380000-0000-0000-0000-000000000005', 'd6380000-0000-0000-0000-000000000003', 'external@example.test', 'd6380000-0000-0000-0000-000000000002');
    UPDATE daysheet_report_recipients SET removed_at = NOW(), removed_by = 'd6380000-0000-0000-0000-000000000002' WHERE id = 'd6380000-0000-0000-0000-000000000010';
    INSERT INTO daysheet_report_recipients (id, venue_id, report_id, definition_version_id, address, created_by) VALUES
        ('d6380000-0000-0000-0000-000000000011', 'd6380000-0000-0000-0000-000000000001', 'd6380000-0000-0000-0000-000000000005', 'd6380000-0000-0000-0000-000000000003', 'external@example.test', 'd6380000-0000-0000-0000-000000000002');
    BEGIN
        UPDATE daysheet_report_recipients SET removed_at = NULL, removed_by = NULL WHERE id = 'd6380000-0000-0000-0000-000000000010';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'removed recipient identity could be restored'; END IF;
    rejected := FALSE;
    BEGIN
        UPDATE daysheet_report_recipients SET address = 'changed@example.test' WHERE id = 'd6380000-0000-0000-0000-000000000011';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'recipient destination identity could be rewritten'; END IF;
    IF (SELECT count(*) FROM users WHERE email = 'external@example.test') <> 0 THEN
        RAISE EXCEPTION 'external recipient migration fabricated an account';
    END IF;
END;
$$;
