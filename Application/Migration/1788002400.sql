-- GitHub #405: venue and onboarding invitations now use email_delivery.
-- Retain terminal history and retire only active legacy transport rows.
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
WHERE job_kind IN ('venue_invitation_delivery', 'venue_onboarding_invitation_delivery')
  AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
