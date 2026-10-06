-- Dedicated IHP queue: eight capture slots per worker process, independent of
-- the existing four AppJob slots. No reports, recipients or existing jobs are
-- deleted or rewritten. Legacy AppJob capture tasks are handed off by the new
-- dispatcher when due; retries of a handoff reuse the same dedicated task.
-- Rollback: leave this additive table intact. An older worker cannot consume
-- these tasks; restore the new worker before future cutoffs. Never reconstruct
-- missed cutoff reports or reset customer data during recovery.
CREATE TABLE daysheet_capture_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL,
    last_error TEXT DEFAULT NULL,
    attempts_count INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by UUID DEFAULT NULL,
    run_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    daysheet_id UUID NOT NULL,
    cutoff_at TIMESTAMP WITH TIME ZONE NOT NULL,
    result JSONB DEFAULT '{}'::JSONB NOT NULL,
    CONSTRAINT daysheet_capture_jobs_cutoff_unique UNIQUE (daysheet_id, cutoff_at),
    CONSTRAINT daysheet_capture_jobs_attempts_nonnegative CHECK (attempts_count >= 0)
);
ALTER TABLE daysheet_capture_jobs ADD CONSTRAINT daysheet_capture_jobs_ref_daysheet FOREIGN KEY (daysheet_id) REFERENCES daysheets (id) ON DELETE RESTRICT;
CREATE INDEX daysheet_capture_jobs_pending ON daysheet_capture_jobs (run_at) WHERE status IN ('job_status_not_started', 'job_status_retry');
