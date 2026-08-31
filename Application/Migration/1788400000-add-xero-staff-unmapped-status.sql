-- Existing not_applicable rows without an actor are unresolved placeholders.
-- Give them an explicit state while preserving user-confirmed not-paid decisions.
-- The enum addition commits independently because PostgreSQL cannot alter an enum
-- inside IHP's migration transaction; IF NOT EXISTS makes a retry safe if later
-- statements fail after the enum value has committed.
COMMIT;
ALTER TYPE xero_staff_mapping_status_enum ADD VALUE IF NOT EXISTS 'unmapped' BEFORE 'verified';
BEGIN;

UPDATE xero_staff_mappings
SET mapping_status = 'unmapped'
WHERE mapping_status = 'not_applicable'
  AND updated_by_user_id IS NULL;

ALTER TABLE xero_staff_mappings
    ALTER COLUMN mapping_status SET DEFAULT 'unmapped';
