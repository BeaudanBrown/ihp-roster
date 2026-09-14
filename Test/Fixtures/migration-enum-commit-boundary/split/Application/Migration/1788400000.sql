-- The enum addition owns a revision so the pinned IHP runner commits it before
-- any statement uses the new value.
ALTER TYPE xero_staff_mapping_status_enum ADD VALUE IF NOT EXISTS 'unmapped' BEFORE 'verified';
