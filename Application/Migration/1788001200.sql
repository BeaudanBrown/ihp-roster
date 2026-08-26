ALTER TABLE billing_events
    ADD COLUMN notification_snapshot JSONB DEFAULT '[]'::JSONB NOT NULL;

ALTER TABLE billing_events
    ADD CONSTRAINT billing_events_notification_snapshot_array
    CHECK (jsonb_typeof(notification_snapshot) = 'array');

-- Hard-cutover safety: active legacy transport jobs must never deliver after the
-- shared email pipeline becomes authoritative. Terminal history is retained.
UPDATE app_jobs
SET status = 'job_status_succeeded',
    result = result || jsonb_build_object(
        'deliveryStatus', 'retired_during_email_pipeline_migration',
        'retiredJobKind', job_kind
    ),
    last_error = NULL,
    locked_at = NULL,
    locked_by = NULL,
    updated_at = NOW()
WHERE job_kind IN ('billing_notification', 'wage_source_award_drift_notification')
  AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
