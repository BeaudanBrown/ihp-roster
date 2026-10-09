DO $$
DECLARE
    rejected BOOLEAN := FALSE;
BEGIN
    IF EXISTS (SELECT 1 FROM venues WHERE id = 'd6350000-0000-0000-0000-000000000001' AND name = 'Daily migration fixture without prior definition storage') THEN
        IF EXISTS (SELECT 1 FROM daysheet_definition_captures WHERE venue_id = 'd6350000-0000-0000-0000-000000000001')
            OR EXISTS (SELECT 1 FROM daysheet_definition_versions WHERE venue_id = 'd6350000-0000-0000-0000-000000000001') THEN
            RAISE EXCEPTION 'upgrade fabricated Daysheet meaning for a pre-definition venue';
        END IF;
        -- No capture existed to preserve in this predecessor. Create only the
        -- post-upgrade scaffolding needed to exercise daily constraints below.
        INSERT INTO daysheet_definition_versions (id, venue_id, version_number, definition, reference_data, published_by) VALUES
            ('d6350000-0000-0000-0000-000000000003', 'd6350000-0000-0000-0000-000000000001', 1, '{"contractVersion":1,"rootFields":[],"recordLists":[],"entryLayout":[],"reports":[]}', '{"lists":[]}', 'd6350000-0000-0000-0000-000000000002');
        INSERT INTO daysheet_definition_captures (id, venue_id, operational_date, timezone, definition_version_id, reference_data, captured_by) VALUES
            ('d6350000-0000-0000-0000-000000000004', 'd6350000-0000-0000-0000-000000000001', '2026-10-01', 'Australia/Melbourne', 'd6350000-0000-0000-0000-000000000003', '{"lists":[]}', 'd6350000-0000-0000-0000-000000000002');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM daysheet_definition_captures WHERE id = 'd6350000-0000-0000-0000-000000000004' AND operational_date = '2026-10-01' AND definition_version_id = 'd6350000-0000-0000-0000-000000000003' AND reference_data = '{"lists":[]}'::JSONB) THEN
        RAISE EXCEPTION 'daily storage migration changed an existing capture';
    END IF;
    IF EXISTS (SELECT 1 FROM daysheets) THEN RAISE EXCEPTION 'migration implicitly created daily business records'; END IF;
    INSERT INTO daysheets (id, venue_id, operational_date, definition_capture_id, saved_data, created_by, last_edited_by) VALUES
        ('d6350000-0000-0000-0000-000000000005', 'd6350000-0000-0000-0000-000000000001', '2026-10-01', 'd6350000-0000-0000-0000-000000000004', '{"version":1,"cells":[],"rows":[],"deleted":[]}', 'd6350000-0000-0000-0000-000000000002', 'd6350000-0000-0000-0000-000000000002');
    UPDATE daysheets SET submitted_at = NOW(), submitted_by = 'd6350000-0000-0000-0000-000000000002', revision = 1 WHERE id = 'd6350000-0000-0000-0000-000000000005';
    -- A submitted row remains updateable; only identity/submission is sealed.
    UPDATE daysheets SET last_edited_at = NOW(), revision = 2 WHERE id = 'd6350000-0000-0000-0000-000000000005';
    BEGIN
        UPDATE daysheets SET submitted_at = NULL, submitted_by = NULL, revision = 3 WHERE id = 'd6350000-0000-0000-0000-000000000005';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'submitted Daysheet could reopen'; END IF;
    rejected := FALSE;
    BEGIN
        UPDATE daysheets SET operational_date = '2026-10-02', revision = 3 WHERE id = 'd6350000-0000-0000-0000-000000000005';
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'daily identity could move to another day'; END IF;
    rejected := FALSE;
    BEGIN
        INSERT INTO daysheets (venue_id, operational_date, definition_capture_id, saved_data, created_by, last_edited_by) VALUES
            ('d6350000-0000-0000-0000-000000000001', '2026-10-02', 'd6350000-0000-0000-0000-000000000004', '{}', 'd6350000-0000-0000-0000-000000000002', 'd6350000-0000-0000-0000-000000000002');
    EXCEPTION WHEN raise_exception THEN rejected := TRUE;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'a capture could be used for a different Operational day'; END IF;
END;
$$;
