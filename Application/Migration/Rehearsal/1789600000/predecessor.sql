-- Synthetic rows cover the old omitted default, zero, and a custom row count.
BEGIN;
INSERT INTO venues (id, name)
VALUES ('96000000-0000-0000-0000-000000000001', 'Two-row default rehearsal');
INSERT INTO users (id, email, password_hash)
VALUES ('96000000-0000-0000-0000-000000000002', 'two-row-rehearsal@example.invalid', 'not-a-password');
INSERT INTO roster_groups (id, venue_id, name)
VALUES ('96000000-0000-0000-0000-000000000003', '96000000-0000-0000-0000-000000000001', 'Rehearsal');

DO $$
DECLARE
    i INT;
    template_id UUID;
    completion_id UUID;
BEGIN
    FOR i IN 0..2 LOOP
        template_id := md5('two-row-rehearsal-template-' || i)::uuid;
        completion_id := md5('two-row-rehearsal-completion-' || i)::uuid;
        INSERT INTO roster_templates (id, roster_group_id, name, scale, completion_id, created_by_user_id)
        VALUES (template_id, '96000000-0000-0000-0000-000000000003', 'Rehearsal ' || i, 'day', completion_id, '96000000-0000-0000-0000-000000000002');
        IF i = 0 THEN
            INSERT INTO roster_days (venue_id, roster_group_id, operational_date)
            VALUES ('96000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000003', DATE '2026-09-21');
            INSERT INTO roster_template_days (roster_template_id, day_index) VALUES (template_id, 0);
        ELSE
            INSERT INTO roster_days (venue_id, roster_group_id, operational_date, row_count)
            VALUES ('96000000-0000-0000-0000-000000000001', '96000000-0000-0000-0000-000000000003', DATE '2026-09-21' + i, CASE i WHEN 1 THEN 0 ELSE 7 END);
            INSERT INTO roster_template_days (roster_template_id, day_index, row_count)
            VALUES (template_id, 0, CASE i WHEN 1 THEN 0 ELSE 7 END);
        END IF;
        INSERT INTO roster_template_columns (roster_template_id, name) VALUES (template_id, 'Only');
        INSERT INTO roster_template_completions (id, roster_template_id) VALUES (completion_id, template_id);
    END LOOP;
    IF (SELECT array_agg(row_count ORDER BY operational_date) FROM roster_days WHERE roster_group_id = '96000000-0000-0000-0000-000000000003') IS DISTINCT FROM ARRAY[4,0,7] THEN
        RAISE EXCEPTION 'two-row rehearsal requires predecessor default four';
    END IF;
END;
$$;
COMMIT;
