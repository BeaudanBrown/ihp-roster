CREATE TABLE IF NOT EXISTS xero_reference_sync_leases (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    tenant_id TEXT NOT NULL UNIQUE,
    app_job_id UUID DEFAULT NULL,
    lease_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    next_request_not_before TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (app_job_id) REFERENCES app_jobs (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_xero_reference_sync_leases_expiry
    ON xero_reference_sync_leases (lease_expires_at);
