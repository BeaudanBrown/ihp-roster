-- Pending Xero writes previously represented uncertain provider outcomes indefinitely.
-- Fresh preparation is now the only retry path; retain every request/source audit row
-- while making any pre-deployment pending reservation recoverable.
UPDATE xero_timesheet_submissions
SET
    status = 'failed',
    response_payload_json = response_payload_json || jsonb_build_object(
        'recoveryMessage', 'Bepis could not confirm whether Xero received this timesheet because the submission was interrupted. Check Xero, then start a fresh preparation to retry.',
        'outcome', 'uncertain'
    ),
    last_error =
        'Bepis could not confirm whether Xero received this timesheet because the submission was interrupted. Check Xero, then start a fresh preparation to retry.'
        || CASE
            WHEN last_error IS NULL OR btrim(last_error) = '' THEN ''
            ELSE ' Prior provider error: ' || last_error
        END,
    submitted_at = COALESCE(submitted_at, NOW()),
    updated_at = NOW()
WHERE status = 'pending';

UPDATE xero_submission_runs AS run
SET
    status = CASE
        WHEN NOT EXISTS (
            SELECT 1
            FROM xero_timesheet_submissions AS submission
            WHERE submission.xero_submission_run_id = run.id
              AND submission.status <> 'superseded'
        ) THEN 'superseded'::xero_submission_run_status_enum
        WHEN NOT EXISTS (
            SELECT 1
            FROM xero_timesheet_submissions AS submission
            WHERE submission.xero_submission_run_id = run.id
              AND submission.status <> 'superseded'
              AND submission.status <> 'submitted'
        ) THEN 'submitted'::xero_submission_run_status_enum
        WHEN NOT EXISTS (
            SELECT 1
            FROM xero_timesheet_submissions AS submission
            WHERE submission.xero_submission_run_id = run.id
              AND submission.status <> 'superseded'
              AND submission.status <> 'blocked'
        ) THEN 'blocked'::xero_submission_run_status_enum
        WHEN NOT EXISTS (
            SELECT 1
            FROM xero_timesheet_submissions AS submission
            WHERE submission.xero_submission_run_id = run.id
              AND submission.status <> 'superseded'
              AND submission.status <> 'failed'
        ) THEN 'failed'::xero_submission_run_status_enum
        ELSE 'partially_failed'::xero_submission_run_status_enum
    END,
    completed_at = COALESCE(completed_at, NOW()),
    error_summary = COALESCE(error_summary, 'One or more Xero submission outcomes were uncertain. Check Xero, then start a fresh preparation to retry.'),
    updated_at = NOW()
WHERE run.status = 'pending';
