WITH
parameters AS (
    SELECT :'stale_before'::TIMESTAMPTZ AS stale_before
),
run_submission_counts AS (
    SELECT
        runs.id,
        runs.status,
        runs.created_at,
        COUNT(submissions.id)::BIGINT AS submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'pending')::BIGINT AS pending_submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'submitted')::BIGINT AS submitted_submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'failed')::BIGINT AS failed_submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'blocked')::BIGINT AS blocked_submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'skipped')::BIGINT AS skipped_submission_count,
        COUNT(*) FILTER (WHERE submissions.status = 'superseded')::BIGINT AS superseded_submission_count
    FROM xero_submission_runs AS runs
    LEFT JOIN xero_timesheet_submissions AS submissions
        ON submissions.xero_submission_run_id = runs.id
    GROUP BY runs.id, runs.status, runs.created_at
),
run_shapes AS (
    SELECT
        status::TEXT AS run_status,
        submission_count,
        pending_submission_count,
        submitted_submission_count,
        failed_submission_count,
        blocked_submission_count,
        skipped_submission_count,
        superseded_submission_count,
        COUNT(*)::BIGINT AS run_count,
        MIN(created_at) AS oldest_created_at,
        MAX(created_at) AS newest_created_at
    FROM run_submission_counts
    GROUP BY
        status,
        submission_count,
        pending_submission_count,
        submitted_submission_count,
        failed_submission_count,
        blocked_submission_count,
        skipped_submission_count,
        superseded_submission_count
),
submission_states AS (
    SELECT
        status::TEXT AS submission_status,
        COUNT(*)::BIGINT AS row_count,
        MIN(created_at) AS oldest_created_at,
        MAX(created_at) AS newest_created_at
    FROM xero_timesheet_submissions
    GROUP BY status
),
stale_empty_pending AS (
    SELECT counts.*
    FROM run_submission_counts AS counts
    CROSS JOIN parameters
    WHERE counts.status = 'pending'
        AND counts.submission_count = 0
        AND counts.created_at < parameters.stale_before
),
active_duplicates AS (
    SELECT
        xero_connection_id,
        xero_employee_id,
        pay_period_start,
        pay_period_end,
        COUNT(*)::BIGINT AS row_count
    FROM xero_timesheet_submissions
    WHERE status <> 'superseded'
    GROUP BY xero_connection_id, xero_employee_id, pay_period_start, pay_period_end
    HAVING COUNT(*) > 1
)
SELECT JSONB_PRETTY(JSONB_BUILD_OBJECT(
    'capture', JSONB_BUILD_OBJECT(
        'capturedAt', CURRENT_TIMESTAMP,
        'database', CURRENT_DATABASE(),
        'databaseUser', CURRENT_USER,
        'serverAddress', COALESCE(INET_SERVER_ADDR()::TEXT, 'local-socket'),
        'serverPort', INET_SERVER_PORT(),
        'serverVersion', CURRENT_SETTING('server_version'),
        'transactionReadOnly', CURRENT_SETTING('transaction_read_only'),
        'staleBefore', (SELECT stale_before FROM parameters)
    ),
    'staleEmptyPendingRuns', JSONB_BUILD_OBJECT(
        'count', (SELECT COUNT(*) FROM stale_empty_pending),
        'oldestCreatedAt', (SELECT MIN(created_at) FROM stale_empty_pending),
        'newestCreatedAt', (SELECT MAX(created_at) FROM stale_empty_pending),
        'runIds', COALESCE((
            SELECT JSONB_AGG(id ORDER BY created_at, id)
            FROM stale_empty_pending
        ), '[]'::JSONB)
    ),
    'runShapes', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(shape) ORDER BY shape.run_status, shape.submission_count, shape.pending_submission_count)
        FROM run_shapes AS shape
    ), '[]'::JSONB),
    'submissionStates', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(state) ORDER BY state.submission_status)
        FROM submission_states AS state
    ), '[]'::JSONB),
    'invariants', JSONB_BUILD_OBJECT(
        'activeRemotePeriodDuplicateGroups', (SELECT COUNT(*) FROM active_duplicates),
        'emptyPendingRunsAtAnyAge', (
            SELECT COUNT(*)
            FROM run_submission_counts
            WHERE status = 'pending' AND submission_count = 0
        ),
        'pendingRunsWithoutPendingSubmissions', (
            SELECT COUNT(*)
            FROM run_submission_counts
            WHERE status = 'pending' AND pending_submission_count = 0
        ),
        'supersededSubmissionHistoryRows', (
            SELECT COUNT(*)
            FROM xero_timesheet_submissions
            WHERE status = 'superseded'
        )
    )
));
