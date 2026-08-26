-- Email delivery dedupe is permanent across every terminal AppJob status.
-- No existing rows use the new email_delivery kind before this rollout.
CREATE UNIQUE INDEX idx_app_jobs_email_delivery_dedupe
    ON app_jobs (dedupe_key)
    WHERE job_kind = 'email_delivery' AND dedupe_key IS NOT NULL;
