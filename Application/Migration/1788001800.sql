-- GitHub #404: roster and RSA mail now use the shared email_delivery pipeline.
-- Retain terminal history while preventing active legacy jobs from churning a
-- runtime that no longer has handlers for their job kinds.
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
WHERE job_kind IN ('roster_notification_delivery', 'staff_document_rsa_reminder')
  AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
