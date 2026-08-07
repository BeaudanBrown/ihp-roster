LOCK TABLE xero_submission_runs IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE xero_timesheet_submissions IN SHARE ROW EXCLUSIVE MODE;

SET LOCAL "bepis.remediation_expected_count" TO :'expected_count';
SET LOCAL "bepis.remediation_stale_before" TO :'stale_before';

DO $$
DECLARE
    expected_count BIGINT := CURRENT_SETTING('bepis.remediation_expected_count')::BIGINT;
    target_count BIGINT;
    invalid_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO target_count
    FROM xero_reconciliation_remediation_targets;

    IF target_count <> expected_count THEN
        RAISE EXCEPTION 'target count % does not match reviewed expected count %', target_count, expected_count;
    END IF;
    IF target_count = 0 THEN
        RAISE EXCEPTION 'refusing an empty remediation target set';
    END IF;

    SELECT COUNT(*) INTO invalid_count
    FROM xero_reconciliation_remediation_targets AS targets
    LEFT JOIN xero_submission_runs AS runs ON runs.id = targets.id
    WHERE runs.id IS NULL
        OR runs.status <> 'pending'
        OR runs.created_at >= CURRENT_SETTING('bepis.remediation_stale_before')::TIMESTAMPTZ
        OR runs.completed_at IS NOT NULL
        OR runs.error_summary IS NOT NULL
        OR EXISTS (
            SELECT 1
            FROM xero_timesheet_submissions AS submissions
            WHERE submissions.xero_submission_run_id = targets.id
        );

    IF invalid_count <> 0 THEN
        RAISE EXCEPTION '% reviewed targets are missing or no longer untouched stale empty pending runs', invalid_count;
    END IF;
END
$$;

WITH updated AS (
    UPDATE xero_submission_runs AS runs
    SET
        status = 'failed',
        completed_at = CURRENT_TIMESTAMP,
        error_summary = 'Historical empty pending Xero submission run reconciled under issue #357.',
        updated_at = CURRENT_TIMESTAMP
    FROM xero_reconciliation_remediation_targets AS targets
    WHERE runs.id = targets.id
    RETURNING runs.id
)
SELECT JSONB_PRETTY(JSONB_BUILD_OBJECT(
    'mode', CASE WHEN :'apply'::BOOLEAN THEN 'applied' ELSE 'dry-run' END,
    'database', CURRENT_DATABASE(),
    'executedAt', CURRENT_TIMESTAMP,
    'updatedCount', COUNT(*),
    'updatedRunIds', COALESCE(JSONB_AGG(id ORDER BY id), '[]'::JSONB)
))
FROM updated;

\if :apply
COMMIT;
\else
ROLLBACK;
\endif
