CREATE TABLE IF NOT EXISTS app_jobs (
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
    venue_id UUID DEFAULT NULL,
    related_table TEXT DEFAULT NULL,
    related_id UUID DEFAULT NULL,
    dedupe_key TEXT DEFAULT NULL,
    progress JSONB DEFAULT '{}'::JSONB NOT NULL,
    result JSONB DEFAULT '{}'::JSONB NOT NULL,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_app_jobs_pending ON app_jobs (status, run_at, created_at);
CREATE INDEX IF NOT EXISTS idx_app_jobs_kind_created_at ON app_jobs (job_kind, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_jobs_venue_created_at ON app_jobs (venue_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_app_jobs_active_dedupe
    ON app_jobs (dedupe_key)
    WHERE dedupe_key IS NOT NULL
        AND (
            status = 'job_status_not_started'
            OR status = 'job_status_running'
            OR status = 'job_status_retry'
        );
