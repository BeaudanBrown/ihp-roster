-- Track Xero provider availability separately from owner-controlled archival.
-- Existing rows remain available unless their last observed provider status was
-- explicitly inactive. Missing rows are reconciled by the next complete sync.
ALTER TABLE xero_employees
    ADD COLUMN provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE xero_earnings_rates
    ADD COLUMN provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE xero_imported_pay_items
    ADD COLUMN provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE xero_accounts
    ADD COLUMN provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE xero_payroll_calendars
    ADD COLUMN provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    ADD COLUMN provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

UPDATE xero_employees
SET provider_available = FALSE,
    provider_unavailable_at = CURRENT_TIMESTAMP
WHERE status IS NOT NULL
  AND upper(btrim(status)) <> 'ACTIVE';

UPDATE xero_earnings_rates
SET provider_available = FALSE,
    provider_unavailable_at = CURRENT_TIMESTAMP
WHERE is_active = FALSE;

UPDATE xero_accounts
SET provider_available = FALSE,
    provider_unavailable_at = CURRENT_TIMESTAMP
WHERE status IS NOT NULL
  AND upper(btrim(status)) <> 'ACTIVE';

UPDATE xero_imported_pay_items imported
SET provider_available = FALSE,
    provider_unavailable_at = CURRENT_TIMESTAMP
FROM xero_earnings_rates rate
WHERE rate.xero_connection_id = imported.xero_connection_id
  AND rate.xero_earnings_rate_id = imported.xero_earnings_rate_id
  AND rate.provider_available = FALSE;

ALTER TABLE xero_employees
    ADD CONSTRAINT xero_employees_provider_availability_check
    CHECK (provider_available = (provider_unavailable_at IS NULL));
ALTER TABLE xero_earnings_rates
    ADD CONSTRAINT xero_earnings_rates_provider_availability_check
    CHECK (provider_available = (provider_unavailable_at IS NULL));
ALTER TABLE xero_imported_pay_items
    ADD CONSTRAINT xero_imported_pay_items_provider_availability_check
    CHECK (provider_available = (provider_unavailable_at IS NULL));
ALTER TABLE xero_accounts
    ADD CONSTRAINT xero_accounts_provider_availability_check
    CHECK (provider_available = (provider_unavailable_at IS NULL));
ALTER TABLE xero_payroll_calendars
    ADD CONSTRAINT xero_payroll_calendars_provider_availability_check
    CHECK (provider_available = (provider_unavailable_at IS NULL));

DROP INDEX idx_xero_employees_venue_name;
CREATE INDEX idx_xero_employees_venue_name ON xero_employees (venue_id, display_name) WHERE provider_available = TRUE;
DROP INDEX idx_xero_earnings_rates_venue_name;
CREATE INDEX idx_xero_earnings_rates_venue_name ON xero_earnings_rates (venue_id, name) WHERE provider_available = TRUE;
DROP INDEX idx_xero_imported_pay_items_venue_active_name;
CREATE INDEX idx_xero_imported_pay_items_venue_active_name ON xero_imported_pay_items (venue_id, name) WHERE archived_at IS NULL AND provider_available = TRUE;
DROP INDEX idx_xero_accounts_venue_type_status;
CREATE INDEX idx_xero_accounts_venue_type_status ON xero_accounts (venue_id, account_type, status) WHERE provider_available = TRUE;
DROP INDEX idx_xero_payroll_calendars_venue_name;
CREATE INDEX idx_xero_payroll_calendars_venue_name ON xero_payroll_calendars (venue_id, name) WHERE provider_available = TRUE;
