-- Add append-only, connection-scoped Xero routing for components approved before
-- their provider earnings mapping was available. Existing sealed wage facts are
-- not changed or backfilled; bindings are created lazily during preparation.
CREATE TABLE timesheet_pay_component_xero_bindings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    timesheet_pay_earnings_component_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    local_bucket_key TEXT NOT NULL,
    xero_earnings_rate_id TEXT NOT NULL,
    resolution_source TEXT NOT NULL,
    resolved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (timesheet_pay_earnings_component_id) REFERENCES timesheet_pay_earnings_components (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (char_length(btrim(local_bucket_key)) > 0),
    CHECK (char_length(btrim(xero_earnings_rate_id)) > 0),
    CHECK (resolution_source = 'verified_mapping' OR resolution_source = 'managed_pay_item' OR resolution_source = 'imported_pay_item'),
    UNIQUE (timesheet_pay_earnings_component_id, xero_connection_id)
);

CREATE INDEX idx_timesheet_pay_component_xero_bindings_connection ON timesheet_pay_component_xero_bindings (xero_connection_id);

CREATE OR REPLACE FUNCTION enforce_timesheet_pay_component_xero_binding_immutability()
RETURNS TRIGGER
AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'late Xero component bindings are immutable';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM timesheet_pay_earnings_components component
        JOIN timesheet_pay_calculations calculation ON calculation.id = component.timesheet_pay_calculation_id
        JOIN timesheet_entries entry ON entry.id = calculation.timesheet_entry_id
        JOIN xero_connections connection ON connection.id = NEW.xero_connection_id AND connection.venue_id = entry.venue_id
        WHERE component.id = NEW.timesheet_pay_earnings_component_id
            AND component.xero_local_bucket_key IS NULL
            AND component.xero_earnings_rate_id IS NULL
            AND component.xero_mapping_legacy_fallback = FALSE
            AND calculation.sealed_at IS NOT NULL
            AND entry.is_approved = TRUE
            AND entry.active_pay_calculation_id = calculation.id
    ) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'late Xero binding requires an active sealed component without approval-time routing';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_timesheet_pay_component_xero_bindings_immutable
    BEFORE INSERT OR UPDATE OR DELETE ON timesheet_pay_component_xero_bindings
    FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_pay_component_xero_binding_immutability();
