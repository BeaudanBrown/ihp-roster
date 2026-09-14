-- Use the committed enum value only in a later migration revision.
UPDATE xero_staff_mappings
SET status = 'unmapped'
WHERE status = 'not_applicable' AND xero_employee_id IS NULL;

ALTER TABLE xero_staff_mappings
    ALTER COLUMN status SET DEFAULT 'unmapped';
