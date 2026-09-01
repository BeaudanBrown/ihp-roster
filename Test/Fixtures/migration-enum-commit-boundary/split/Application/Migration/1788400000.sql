-- Comments and explicit transaction control do not make an enum-add revision mixed.
BEGIN;
ALTER/* inline comment */TYPE xero_staff_mapping_status_enum ADD VALUE IF NOT EXISTS 'unmapped' BEFORE 'verified';
COMMIT;
