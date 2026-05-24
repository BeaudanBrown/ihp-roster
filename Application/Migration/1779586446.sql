ALTER TABLE shift_types
    ALTER COLUMN colour_key SET DEFAULT '';

ALTER TABLE shift_types
    DROP CONSTRAINT IF EXISTS shift_types_colour_key_check;

UPDATE shift_types
SET colour_key = '';

ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_colour_key_check
    CHECK (colour_key = '' OR colour_key = 'palette-1' OR colour_key = 'palette-2' OR colour_key = 'palette-3' OR colour_key = 'palette-4' OR colour_key = 'palette-5' OR colour_key = 'palette-6' OR colour_key = 'palette-7' OR colour_key = 'palette-8' OR colour_key = 'palette-9' OR colour_key = 'palette-10');
