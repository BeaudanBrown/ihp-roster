DO $$
DECLARE
    enum_labels TEXT[];
    inserted_default xero_staff_mapping_status_enum;
BEGIN
    SELECT array_agg(enumlabel ORDER BY enumsortorder)
    INTO enum_labels
    FROM pg_enum
    WHERE enumtypid = 'xero_staff_mapping_status_enum'::regtype;

    IF enum_labels <> ARRAY['not_applicable', 'unmapped', 'verified'] THEN
        RAISE EXCEPTION 'enum_commit_boundary_order_assertion failed';
    END IF;

    INSERT INTO xero_staff_mappings (id, xero_employee_id)
    VALUES (4, NULL)
    RETURNING status INTO inserted_default;
    IF inserted_default <> 'unmapped' THEN
        RAISE EXCEPTION 'enum_commit_boundary_default_assertion failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM xero_staff_mappings
        WHERE id = 1 AND status = 'unmapped'
    ) THEN
        RAISE EXCEPTION 'enum_commit_boundary_actorless_backfill_assertion failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM xero_staff_mappings
        WHERE id = 2 AND status = 'not_applicable'
    ) THEN
        RAISE EXCEPTION 'enum_commit_boundary_confirmed_retention_assertion failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM xero_staff_mappings
        WHERE id = 3 AND status = 'verified'
    ) THEN
        RAISE EXCEPTION 'enum_commit_boundary_verified_retention_assertion failed';
    END IF;

    IF (
        SELECT count(*) FROM schema_migrations
        WHERE revision IN (1788399999, 1788400000, 1788400001)
    ) <> 3 THEN
        RAISE EXCEPTION 'enum_commit_boundary_revision_recording_assertion failed';
    END IF;
END
$$;
