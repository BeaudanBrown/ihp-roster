ALTER TABLE xero_staff_mappings
    ADD COLUMN IF NOT EXISTS reference_refreshed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Existing mappings predate mapping-specific refresh demand tracking. Their
-- venue connection snapshot is the best safe baseline; newly created mappings
-- remain NULL and request one refresh when they become payroll-eligible.
UPDATE xero_staff_mappings AS mapping
SET reference_refreshed_at = connection.last_sync_at
FROM xero_connections AS connection
WHERE mapping.xero_connection_id = connection.id
  AND mapping.reference_refreshed_at IS NULL
  AND connection.last_sync_at IS NOT NULL;
