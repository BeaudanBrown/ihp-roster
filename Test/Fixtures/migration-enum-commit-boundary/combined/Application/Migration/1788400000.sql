-- Original unsafe shape: the pinned IHP runner keeps these statements in one
-- transaction, so PostgreSQL rejects use of the newly added value.
ALTER TYPE xero_staff_mapping_status_enum ADD VALUE IF NOT EXISTS 'unmapped' BEFORE 'verified';

UPDATE xero_staff_mappings
SET status = 'unmapped'
WHERE status = 'not_applicable' AND xero_employee_id IS NULL;

ALTER TABLE xero_staff_mappings
    ALTER COLUMN status SET DEFAULT 'unmapped';
