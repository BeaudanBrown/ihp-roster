-- Verify preservation and actual omitted-column inserts, not SQL source text.
BEGIN;
DO $$
DECLARE
    actual_count INT;
    i INT;
BEGIN
    IF (SELECT array_agg(row_count ORDER BY operational_date) FROM roster_days WHERE roster_group_id = '96000000-0000-0000-0000-000000000003') IS DISTINCT FROM ARRAY[4,0,7] THEN
        RAISE EXCEPTION 'two-row migration changed existing roster day counts';
    END IF;
    FOR i IN 0..2 LOOP
        SELECT row_count INTO actual_count FROM roster_template_days
        WHERE roster_template_id = md5('two-row-rehearsal-template-' || i)::uuid;
        IF actual_count IS DISTINCT FROM (CASE i WHEN 0 THEN 4 WHEN 1 THEN 0 ELSE 7 END) THEN
            RAISE EXCEPTION 'two-row migration changed existing template day counts';
        END IF;
    END LOOP;

    INSERT INTO roster_days (venue_id, roster_group_id, operational_date)
    VALUES ('96000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000003', DATE '2026-09-24')
    RETURNING row_count INTO actual_count;
    IF actual_count IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'new roster day does not default to two rows';
    END IF;

    INSERT INTO roster_templates (id, roster_group_id, name, scale, completion_id, created_by_user_id)
    VALUES ('96000000-0000-0000-0000-000000000004', '96000000-0000-0000-0000-000000000003', 'New default', 'day', '96000000-0000-0000-0000-000000000005', '96000000-0000-0000-0000-000000000002');
    INSERT INTO roster_template_days (roster_template_id, day_index)
    VALUES ('96000000-0000-0000-0000-000000000004', 0)
    RETURNING row_count INTO actual_count;
    IF actual_count IS DISTINCT FROM 2 THEN
        RAISE EXCEPTION 'new template day does not default to two rows';
    END IF;
    INSERT INTO roster_template_columns (roster_template_id, name)
    VALUES ('96000000-0000-0000-0000-000000000004', 'Only');
    INSERT INTO roster_template_completions (id, roster_template_id)
    VALUES ('96000000-0000-0000-0000-000000000005', '96000000-0000-0000-0000-000000000004');
    SET CONSTRAINTS ALL IMMEDIATE;
END;
$$;
ROLLBACK;
