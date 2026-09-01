-- Existing actorless not_applicable rows are unresolved placeholders. Preserve
-- user-confirmed not-paid decisions while making unmapped the default state.
UPDATE xero_staff_mappings
SET mapping_status = 'unmapped'
WHERE mapping_status = 'not_applicable'
  AND updated_by_user_id IS NULL;

ALTER TABLE xero_staff_mappings
    ALTER COLUMN mapping_status SET DEFAULT 'unmapped';
