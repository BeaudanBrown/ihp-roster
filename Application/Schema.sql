-- Your database schema. Use the Schema Designer at http://localhost:8001/ to add some tables.
CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL
);
CREATE TABLE app_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL,
    last_error TEXT DEFAULT NULL,
    attempts_count INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by UUID DEFAULT NULL,
    run_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    job_kind TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    payload_schema_version INT DEFAULT 1 NOT NULL,
    requested_by_user_id UUID DEFAULT NULL,
    tenant_id UUID DEFAULT NULL,
    related_table TEXT DEFAULT NULL,
    related_id UUID DEFAULT NULL,
    dedupe_key TEXT DEFAULT NULL,
    progress JSONB DEFAULT '{}'::JSONB NOT NULL,
    result JSONB DEFAULT '{}'::JSONB NOT NULL,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);

CREATE INDEX idx_app_jobs_pending ON app_jobs (status, run_at, created_at);
CREATE INDEX idx_app_jobs_kind_created_at ON app_jobs (job_kind, created_at DESC);
CREATE INDEX idx_app_jobs_tenant_created_at ON app_jobs (tenant_id, created_at DESC);
CREATE UNIQUE INDEX idx_app_jobs_active_dedupe ON app_jobs (dedupe_key) WHERE dedupe_key IS NOT NULL AND (status = 'job_status_not_started' OR status = 'job_status_running' OR status = 'job_status_retry');
