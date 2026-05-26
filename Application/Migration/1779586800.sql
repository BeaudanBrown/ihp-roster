CREATE TABLE xero_accounts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_account_id TEXT NOT NULL,
    code TEXT,
    name TEXT NOT NULL,
    account_type TEXT,
    status TEXT,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX idx_xero_accounts_connection_account ON xero_accounts (xero_connection_id, xero_account_id);
CREATE INDEX idx_xero_accounts_connection_code ON xero_accounts (xero_connection_id, code);
CREATE INDEX idx_xero_accounts_venue_type_status ON xero_accounts (venue_id, account_type, status);

CREATE TRIGGER prevent_hard_delete_xero_accounts BEFORE DELETE ON xero_accounts FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER enforce_xero_accounts_venue_integrity BEFORE INSERT OR UPDATE ON xero_accounts FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
