BEGIN;

CREATE TYPE xero_reference_sync_category_enum AS ENUM (
    'xero_staff',
    'pay_items',
    'payroll_calendars',
    'accounts'
);

CREATE TABLE xero_reference_sync_category_states (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    category xero_reference_sync_category_enum NOT NULL,
    last_success_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(xero_connection_id, category),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);

CREATE INDEX idx_xero_reference_sync_category_states_venue
    ON xero_reference_sync_category_states (venue_id, category, last_success_at DESC);

CREATE TRIGGER prevent_hard_delete_xero_reference_sync_category_states
    BEFORE DELETE ON xero_reference_sync_category_states
    FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();

CREATE TRIGGER enforce_xero_reference_sync_category_states_venue_integrity
    BEFORE INSERT OR UPDATE ON xero_reference_sync_category_states
    FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();

-- Existing aggregate snapshots established all four category snapshots together.
INSERT INTO xero_reference_sync_category_states (
    venue_id,
    xero_connection_id,
    category,
    last_success_at
)
SELECT
    connection.venue_id,
    connection.id,
    category.category,
    connection.last_sync_at
FROM xero_connections connection
CROSS JOIN unnest(enum_range(NULL::xero_reference_sync_category_enum)) AS category(category)
WHERE connection.last_sync_at IS NOT NULL;

COMMIT;
