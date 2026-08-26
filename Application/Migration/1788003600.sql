-- GitHub #407: final shared-email cutover reconciliation.
-- Earlier domain migrations retire these rows independently. Repeating the
-- bounded active-state update here makes the final deployment safe when a
-- legacy row was claimed or restored between staged cutovers. Terminal history
-- remains unchanged and no retired producer or runtime handler is reintroduced.
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
WHERE job_kind IN (
    'billing_notification',
    'wage_source_award_drift_notification',
    'roster_notification_delivery',
    'staff_document_rsa_reminder',
    'venue_invitation_delivery',
    'venue_onboarding_invitation_delivery'
)
  AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
