ALTER TABLE shift_types
    ADD COLUMN colour_key TEXT DEFAULT 'default' NOT NULL;

ALTER TABLE shift_types
    DROP CONSTRAINT IF EXISTS shift_types_colour_key_check;

ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_colour_key_check
    CHECK (colour_key = 'default' OR colour_key = 'palette-1' OR colour_key = 'palette-2' OR colour_key = 'palette-3' OR colour_key = 'palette-4' OR colour_key = 'palette-5' OR colour_key = 'palette-6' OR colour_key = 'palette-7' OR colour_key = 'palette-8' OR colour_key = 'palette-9' OR colour_key = 'palette-10');

WITH ranked_active_shift_types AS (
    SELECT
        id,
        row_number() OVER (PARTITION BY venue_id ORDER BY sort_order ASC, created_at ASC, id ASC) AS active_rank
    FROM shift_types
    WHERE is_active = TRUE
      AND archived_at IS NULL
)
UPDATE shift_types
SET colour_key = CASE ranked_active_shift_types.active_rank
    WHEN 1 THEN 'palette-1'
    WHEN 2 THEN 'palette-2'
    WHEN 3 THEN 'palette-3'
    WHEN 4 THEN 'palette-4'
    WHEN 5 THEN 'palette-5'
    WHEN 6 THEN 'palette-6'
    WHEN 7 THEN 'palette-7'
    WHEN 8 THEN 'palette-8'
    WHEN 9 THEN 'palette-9'
    WHEN 10 THEN 'palette-10'
    ELSE 'default'
END
FROM ranked_active_shift_types
WHERE shift_types.id = ranked_active_shift_types.id;
