-- Structural DB authority only. Application lifecycle tests own typed payloads.
DO $$
DECLARE
    rejected BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM venues WHERE id = 'd6320000-0000-0000-0000-000000000001' AND name = 'Daysheet preservation fixture')
       OR NOT EXISTS (SELECT 1 FROM users WHERE id = 'd6320000-0000-0000-0000-000000000003' AND password_hash = 'synthetic') THEN
        RAISE EXCEPTION 'Daysheet additive migration changed predecessor customer records';
    END IF;
    INSERT INTO daysheet_definition_versions (id, venue_id, version_number, definition, reference_data, published_by) VALUES
        ('d6320000-0000-0000-0000-000000000010', 'd6320000-0000-0000-0000-000000000001', 1, '{"fixtureVersion":1}', '{"fixtureMeaning":"old"}', 'd6320000-0000-0000-0000-000000000003'),
        ('d6320000-0000-0000-0000-000000000011', 'd6320000-0000-0000-0000-000000000001', 2, '{"fixtureVersion":2}', '{"fixtureMeaning":"new"}', 'd6320000-0000-0000-0000-000000000003');
    INSERT INTO daysheet_configurations (venue_id, published_version_id, reference_data) VALUES
        ('d6320000-0000-0000-0000-000000000001', 'd6320000-0000-0000-0000-000000000010', '{"fixtureMeaning":"old"}');
    INSERT INTO daysheet_definition_captures (id, venue_id, operational_date, timezone, definition_version_id, reference_data, captured_by) VALUES
        ('d6320000-0000-0000-0000-000000000020', 'd6320000-0000-0000-0000-000000000001', '2026-10-01', 'Australia/Melbourne', 'd6320000-0000-0000-0000-000000000010', '{"fixtureMeaning":"old"}', 'd6320000-0000-0000-0000-000000000003');
    INSERT INTO daysheet_definition_drafts (venue_id, base_revision, definition, reference_data, updated_by) VALUES
        ('d6320000-0000-0000-0000-000000000001', 0, '{"fixtureVersion":2}', '{"fixtureMeaning":"staged"}', 'd6320000-0000-0000-0000-000000000003');
    IF (SELECT reference_data FROM daysheet_configurations WHERE venue_id = 'd6320000-0000-0000-0000-000000000001') <> '{"fixtureMeaning":"old"}'::JSONB THEN
        RAISE EXCEPTION 'staged Daysheet reference corrections changed live reference data';
    END IF;
    UPDATE daysheet_configurations SET published_version_id = 'd6320000-0000-0000-0000-000000000011', revision = 1, reference_data = '{"fixtureMeaning":"new"}' WHERE venue_id = 'd6320000-0000-0000-0000-000000000001';
    IF NOT EXISTS (SELECT 1 FROM daysheet_definition_captures WHERE id = 'd6320000-0000-0000-0000-000000000020' AND definition_version_id = 'd6320000-0000-0000-0000-000000000010' AND reference_data = '{"fixtureMeaning":"old"}'::JSONB) THEN
        RAISE EXCEPTION 'later Daysheet publication changed historical capture meaning';
    END IF;
    rejected := FALSE;
    BEGIN
        UPDATE daysheet_definition_versions SET definition = '{}' WHERE id = 'd6320000-0000-0000-0000-000000000010';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'published Daysheet definition accepted mutation'; END IF;
    rejected := FALSE;
    BEGIN
        DELETE FROM daysheet_definition_captures WHERE id = 'd6320000-0000-0000-0000-000000000020';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'historical Daysheet capture accepted deletion'; END IF;
    rejected := FALSE;
    BEGIN
        UPDATE daysheet_definition_captures SET reference_data = '{}' WHERE id = 'd6320000-0000-0000-0000-000000000020';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'historical Daysheet capture accepted mutation'; END IF;
    rejected := FALSE;
    BEGIN
        INSERT INTO daysheet_configurations (venue_id, published_version_id) VALUES ('d6320000-0000-0000-0000-000000000002', 'd6320000-0000-0000-0000-000000000010');
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'cross-venue Daysheet version accepted'; END IF;
    rejected := FALSE;
    BEGIN
        INSERT INTO daysheet_definition_captures (venue_id, operational_date, timezone, definition_version_id, reference_data, captured_by) VALUES
            ('d6320000-0000-0000-0000-000000000001', '2026-10-01', 'Australia/Melbourne', 'd6320000-0000-0000-0000-000000000011', '{}', 'd6320000-0000-0000-0000-000000000003');
    EXCEPTION WHEN unique_violation THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'duplicate venue/day capture accepted'; END IF;
END;
$$;
