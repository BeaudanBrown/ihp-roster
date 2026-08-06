-- #334: retain provider-owned Xero vocabulary as TEXT while making every
-- app-owned Xero workflow state a generated PostgreSQL enum.
--
-- This migration is data-preserving and transactional. It validates every
-- existing value before changing any column. An unexpected value aborts the
-- transaction with its table/column/value; operators must classify or repair
-- that value explicitly before retrying.

DO $$
DECLARE
    check_spec RECORD;
    unexpected_values TEXT;
BEGIN
    FOR check_spec IN
        SELECT * FROM (VALUES
            ('xero_sync_runs', 'sync_status', ARRAY['running', 'succeeded', 'failed']::TEXT[]),
            ('xero_sync_runs', 'sync_kind', ARRAY['payroll_reference_data']::TEXT[]),
            ('xero_staff_mappings', 'mapping_status', ARRAY['verified', 'not_applicable', 'stale']::TEXT[]),
            ('xero_earnings_rate_mappings', 'mapping_status', ARRAY['unmapped', 'verified', 'stale']::TEXT[]),
            ('xero_pay_item_account_code_selections', 'selection_status', ARRAY['none', 'verified', 'stale']::TEXT[]),
            ('xero_pay_item_requirement_records', 'requirement_status', ARRAY['proposed', 'matched', 'created', 'ignored', 'stale', 'rate_changed']::TEXT[]),
            ('xero_submission_runs', 'source_kind', ARRAY['approved_timesheets']::TEXT[]),
            ('xero_submission_runs', 'status', ARRAY['previewed', 'blocked', 'pending', 'submitted', 'partially_failed', 'failed', 'superseded']::TEXT[]),
            ('xero_timesheet_preparation_runs', 'status', ARRAY['started', 'preparing', 'needs_reconnect', 'needs_approval', 'blocked', 'resolved', 'ready_for_preview', 'previewed', 'submitted', 'failed', 'cancelled']::TEXT[]),
            ('xero_timesheet_preparation_decisions', 'decision_kind', ARRAY['staff_auto_match', 'staff_manual_mapping', 'staff_not_paid', 'staff_step_approved', 'pay_item_create', 'account_code', 'calendar_selection']::TEXT[]),
            ('xero_timesheet_preparation_decisions', 'decision_status', ARRAY['pending', 'proposed', 'applied', 'blocked', 'resolved', 'dismissed']::TEXT[]),
            ('xero_timesheet_submissions', 'status', ARRAY['blocked', 'pending', 'submitted', 'failed', 'skipped', 'superseded']::TEXT[])
        ) AS checks(table_name, column_name, allowed_values)
    LOOP
        EXECUTE format(
            'SELECT string_agg(format(''%%s (%%s rows)'', invalid_value, invalid_count), '', '' ORDER BY invalid_value) FROM (SELECT %1$I::TEXT AS invalid_value, count(*) AS invalid_count FROM %2$I WHERE NOT (%1$I::TEXT = ANY ($1)) GROUP BY %1$I::TEXT) invalid_values',
            check_spec.column_name,
            check_spec.table_name
        )
        USING check_spec.allowed_values
        INTO unexpected_values;

        IF unexpected_values IS NOT NULL THEN
            RAISE EXCEPTION 'unexpected app-owned Xero workflow value(s) %.%: %; classify or repair before retrying migration',
                check_spec.table_name,
                check_spec.column_name,
                unexpected_values;
        END IF;
    END LOOP;
END
$$;

CREATE TYPE xero_sync_status_enum AS ENUM ('running', 'succeeded', 'failed');
CREATE TYPE xero_sync_kind_enum AS ENUM ('payroll_reference_data');
CREATE TYPE xero_staff_mapping_status_enum AS ENUM ('verified', 'not_applicable', 'stale');
CREATE TYPE xero_earnings_rate_mapping_status_enum AS ENUM ('unmapped', 'verified', 'stale');
CREATE TYPE xero_pay_item_account_code_selection_status_enum AS ENUM ('none', 'verified', 'stale');
CREATE TYPE xero_pay_item_requirement_status_enum AS ENUM ('proposed', 'matched', 'created', 'ignored', 'stale', 'rate_changed');
CREATE TYPE xero_submission_source_kind_enum AS ENUM ('approved_timesheets');
CREATE TYPE xero_submission_run_status_enum AS ENUM ('previewed', 'blocked', 'pending', 'submitted', 'partially_failed', 'failed', 'superseded');
CREATE TYPE xero_timesheet_preparation_run_status_enum AS ENUM ('started', 'preparing', 'needs_reconnect', 'needs_approval', 'blocked', 'resolved', 'ready_for_preview', 'previewed', 'submitted', 'failed', 'cancelled');
CREATE TYPE xero_timesheet_preparation_decision_kind_enum AS ENUM ('staff_auto_match', 'staff_manual_mapping', 'staff_not_paid', 'staff_step_approved', 'pay_item_create', 'account_code', 'calendar_selection');
CREATE TYPE xero_timesheet_preparation_decision_status_enum AS ENUM ('pending', 'proposed', 'applied', 'blocked', 'resolved', 'dismissed');
CREATE TYPE xero_timesheet_submission_status_enum AS ENUM ('blocked', 'pending', 'submitted', 'failed', 'skipped', 'superseded');

ALTER TABLE xero_sync_runs DROP CONSTRAINT IF EXISTS xero_sync_runs_sync_status_check;
ALTER TABLE xero_staff_mappings DROP CONSTRAINT IF EXISTS xero_staff_mappings_mapping_status_check;
ALTER TABLE xero_earnings_rate_mappings DROP CONSTRAINT IF EXISTS xero_earnings_rate_mappings_mapping_status_check;
ALTER TABLE xero_pay_item_requirement_records DROP CONSTRAINT IF EXISTS xero_pay_item_requirement_records_requirement_status_check;
ALTER TABLE xero_submission_runs DROP CONSTRAINT IF EXISTS xero_submission_runs_source_kind_check;
ALTER TABLE xero_submission_runs DROP CONSTRAINT IF EXISTS xero_submission_runs_status_check;
ALTER TABLE xero_timesheet_preparation_runs DROP CONSTRAINT IF EXISTS xero_timesheet_preparation_runs_status_check;
ALTER TABLE xero_timesheet_preparation_decisions DROP CONSTRAINT IF EXISTS xero_timesheet_preparation_decisions_decision_kind_check;
ALTER TABLE xero_timesheet_preparation_decisions DROP CONSTRAINT IF EXISTS xero_timesheet_preparation_decisions_decision_status_check;
ALTER TABLE xero_timesheet_submissions DROP CONSTRAINT IF EXISTS xero_timesheet_submissions_status_check;

-- Partial-index predicates retain their parsed TEXT operators, so rebuild the
-- two predicates around the enum conversion.
DROP INDEX idx_xero_staff_mappings_verified_employee;
DROP INDEX idx_xero_timesheet_submissions_active_remote_period;

ALTER TABLE xero_sync_runs ALTER COLUMN sync_kind DROP DEFAULT;
ALTER TABLE xero_staff_mappings ALTER COLUMN mapping_status DROP DEFAULT;
ALTER TABLE xero_earnings_rate_mappings ALTER COLUMN mapping_status DROP DEFAULT;
ALTER TABLE xero_pay_item_account_code_selections ALTER COLUMN selection_status DROP DEFAULT;
ALTER TABLE xero_pay_item_requirement_records ALTER COLUMN requirement_status DROP DEFAULT;
ALTER TABLE xero_submission_runs ALTER COLUMN source_kind DROP DEFAULT;
ALTER TABLE xero_submission_runs ALTER COLUMN status DROP DEFAULT;
ALTER TABLE xero_timesheet_preparation_runs ALTER COLUMN status DROP DEFAULT;
ALTER TABLE xero_timesheet_preparation_decisions ALTER COLUMN decision_status DROP DEFAULT;
ALTER TABLE xero_timesheet_submissions ALTER COLUMN status DROP DEFAULT;

ALTER TABLE xero_sync_runs
    ALTER COLUMN sync_status TYPE xero_sync_status_enum USING sync_status::TEXT::xero_sync_status_enum,
    ALTER COLUMN sync_kind TYPE xero_sync_kind_enum USING sync_kind::TEXT::xero_sync_kind_enum,
    ALTER COLUMN sync_kind SET DEFAULT 'payroll_reference_data';
ALTER TABLE xero_staff_mappings
    ALTER COLUMN mapping_status TYPE xero_staff_mapping_status_enum USING mapping_status::TEXT::xero_staff_mapping_status_enum,
    ALTER COLUMN mapping_status SET DEFAULT 'not_applicable';
ALTER TABLE xero_earnings_rate_mappings
    ALTER COLUMN mapping_status TYPE xero_earnings_rate_mapping_status_enum USING mapping_status::TEXT::xero_earnings_rate_mapping_status_enum,
    ALTER COLUMN mapping_status SET DEFAULT 'unmapped';
ALTER TABLE xero_pay_item_account_code_selections
    ALTER COLUMN selection_status TYPE xero_pay_item_account_code_selection_status_enum USING selection_status::TEXT::xero_pay_item_account_code_selection_status_enum,
    ALTER COLUMN selection_status SET DEFAULT 'none';
ALTER TABLE xero_pay_item_requirement_records
    ALTER COLUMN requirement_status TYPE xero_pay_item_requirement_status_enum USING requirement_status::TEXT::xero_pay_item_requirement_status_enum,
    ALTER COLUMN requirement_status SET DEFAULT 'proposed';
ALTER TABLE xero_submission_runs
    ALTER COLUMN source_kind TYPE xero_submission_source_kind_enum USING source_kind::TEXT::xero_submission_source_kind_enum,
    ALTER COLUMN source_kind SET DEFAULT 'approved_timesheets',
    ALTER COLUMN status TYPE xero_submission_run_status_enum USING status::TEXT::xero_submission_run_status_enum,
    ALTER COLUMN status SET DEFAULT 'previewed';
ALTER TABLE xero_timesheet_preparation_runs
    ALTER COLUMN status TYPE xero_timesheet_preparation_run_status_enum USING status::TEXT::xero_timesheet_preparation_run_status_enum,
    ALTER COLUMN status SET DEFAULT 'started';
ALTER TABLE xero_timesheet_preparation_decisions
    ALTER COLUMN decision_kind TYPE xero_timesheet_preparation_decision_kind_enum USING decision_kind::TEXT::xero_timesheet_preparation_decision_kind_enum,
    ALTER COLUMN decision_status TYPE xero_timesheet_preparation_decision_status_enum USING decision_status::TEXT::xero_timesheet_preparation_decision_status_enum,
    ALTER COLUMN decision_status SET DEFAULT 'pending';
ALTER TABLE xero_timesheet_submissions
    ALTER COLUMN status TYPE xero_timesheet_submission_status_enum USING status::TEXT::xero_timesheet_submission_status_enum,
    ALTER COLUMN status SET DEFAULT 'pending';

CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee ON xero_staff_mappings (xero_connection_id, xero_employee_id) WHERE mapping_status = 'verified' AND xero_employee_id IS NOT NULL;
CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period ON xero_timesheet_submissions (xero_connection_id, xero_employee_id, pay_period_start, pay_period_end) WHERE status <> 'superseded';
