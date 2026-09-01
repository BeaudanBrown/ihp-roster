-- Add the enum value in its own migration transaction. PostgreSQL requires a
-- new enum value to be committed before a later transaction can use it.
ALTER TYPE xero_staff_mapping_status_enum
    ADD VALUE 'unmapped' BEFORE 'verified';
