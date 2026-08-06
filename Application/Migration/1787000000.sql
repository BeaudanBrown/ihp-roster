-- #338: make the persisted feedback category and shift-type colour key use
-- generated PostgreSQL enum authority. This migration preserves every row and
-- validates all live values before creating or converting either type.

DO $$
DECLARE
    unexpected_feedback TEXT;
    unexpected_colours TEXT;
BEGIN
    SELECT string_agg(format('%L (%s rows)', feedback_type, value_count), ', ' ORDER BY feedback_type)
    INTO unexpected_feedback
    FROM (
        SELECT feedback_type, count(*) AS value_count
        FROM user_feedback_items
        WHERE feedback_type NOT IN ('bug', 'suggestion', 'other')
        GROUP BY feedback_type
    ) unexpected;

    SELECT string_agg(format('%L (%s rows)', colour_key, value_count), ', ' ORDER BY colour_key)
    INTO unexpected_colours
    FROM (
        SELECT colour_key, count(*) AS value_count
        FROM shift_types
        WHERE colour_key NOT IN ('', 'palette-1', 'palette-2', 'palette-3', 'palette-4', 'palette-5', 'palette-6', 'palette-7', 'palette-8', 'palette-9', 'palette-10')
        GROUP BY colour_key
    ) unexpected;

    IF unexpected_feedback IS NOT NULL OR unexpected_colours IS NOT NULL THEN
        RAISE EXCEPTION 'typed authority enum migration blocked; user_feedback_items.feedback_type: %; shift_types.colour_key: %',
            coalesce(unexpected_feedback, '<clean>'),
            coalesce(unexpected_colours, '<clean>');
    END IF;
END
$$;

CREATE TYPE feedback_type_enum AS ENUM ('bug', 'suggestion', 'other');
CREATE TYPE shift_type_colour_key_enum AS ENUM ('no_colour', 'palette_1', 'palette_2', 'palette_3', 'palette_4', 'palette_5', 'palette_6', 'palette_7', 'palette_8', 'palette_9', 'palette_10');

ALTER TABLE user_feedback_items
    DROP CONSTRAINT user_feedback_items_feedback_type_check;
ALTER TABLE shift_types
    DROP CONSTRAINT shift_types_colour_key_check;

ALTER TABLE user_feedback_items
    ALTER COLUMN feedback_type DROP DEFAULT,
    ALTER COLUMN feedback_type TYPE feedback_type_enum USING feedback_type::feedback_type_enum,
    ALTER COLUMN feedback_type SET DEFAULT 'bug'::feedback_type_enum;

ALTER TABLE shift_types
    ALTER COLUMN colour_key DROP DEFAULT,
    ALTER COLUMN colour_key TYPE shift_type_colour_key_enum
        USING (CASE colour_key
            WHEN '' THEN 'no_colour'
            WHEN 'palette-1' THEN 'palette_1'
            WHEN 'palette-2' THEN 'palette_2'
            WHEN 'palette-3' THEN 'palette_3'
            WHEN 'palette-4' THEN 'palette_4'
            WHEN 'palette-5' THEN 'palette_5'
            WHEN 'palette-6' THEN 'palette_6'
            WHEN 'palette-7' THEN 'palette_7'
            WHEN 'palette-8' THEN 'palette_8'
            WHEN 'palette-9' THEN 'palette_9'
            WHEN 'palette-10' THEN 'palette_10'
        END)::shift_type_colour_key_enum,
    ALTER COLUMN colour_key SET DEFAULT 'no_colour'::shift_type_colour_key_enum;
