# Xero Workflow Enum Migration (#334)

## Scope

Migration `1786000000.sql` converts selected app-owned Xero workflow columns
from constrained `TEXT` to PostgreSQL enums without rewriting, deleting, or
merging customer rows. Provider-owned employee, account, pay-run, and timesheet
statuses remain `TEXT` for forward compatibility.

## Before deployment

1. Take and verify a restorable database backup.
2. Run the migration's preflight inventory query (the `DO` block) against the
   target database during the deployment window.
3. If it reports `unexpected app-owned Xero workflow value`, stop. Do not add an
   enum case or rewrite the row until the value's provenance and intended
   workflow meaning are reviewed. Record the affected table, column, value, and
   count in the deployment incident/change record.
4. Confirm no older application process will write these columns during the
   migration transaction.

The migration is transactional. A preflight or cast failure rolls back all type,
constraint, default, and column changes automatically.

## Recovery after deployment

Prefer restoring the application/database backup together if the deployed code
cannot operate safely. A schema-only rollback is data-preserving but requires an
application version that understands the same literal set. In one transaction:

```sql
BEGIN;
-- Predicate expressions are typed, so remove them before changing the
-- referenced enum columns back to TEXT.
DROP INDEX idx_xero_staff_mappings_verified_employee;
DROP INDEX idx_xero_timesheet_submissions_active_remote_period;

-- PostgreSQL does not apply the column USING expression to defaults.
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
    ALTER COLUMN sync_status TYPE TEXT USING sync_status::TEXT,
    ALTER COLUMN sync_kind TYPE TEXT USING sync_kind::TEXT;
ALTER TABLE xero_staff_mappings
    ALTER COLUMN mapping_status TYPE TEXT USING mapping_status::TEXT;
ALTER TABLE xero_earnings_rate_mappings
    ALTER COLUMN mapping_status TYPE TEXT USING mapping_status::TEXT;
ALTER TABLE xero_pay_item_account_code_selections
    ALTER COLUMN selection_status TYPE TEXT USING selection_status::TEXT;
ALTER TABLE xero_pay_item_requirement_records
    ALTER COLUMN requirement_status TYPE TEXT USING requirement_status::TEXT;
ALTER TABLE xero_submission_runs
    ALTER COLUMN source_kind TYPE TEXT USING source_kind::TEXT,
    ALTER COLUMN status TYPE TEXT USING status::TEXT;
ALTER TABLE xero_timesheet_preparation_runs
    ALTER COLUMN status TYPE TEXT USING status::TEXT;
ALTER TABLE xero_timesheet_preparation_decisions
    ALTER COLUMN decision_kind TYPE TEXT USING decision_kind::TEXT,
    ALTER COLUMN decision_status TYPE TEXT USING decision_status::TEXT;
ALTER TABLE xero_timesheet_submissions
    ALTER COLUMN status TYPE TEXT USING status::TEXT;

ALTER TABLE xero_sync_runs ALTER COLUMN sync_kind SET DEFAULT 'payroll_reference_data';
ALTER TABLE xero_staff_mappings ALTER COLUMN mapping_status SET DEFAULT 'not_applicable';
ALTER TABLE xero_earnings_rate_mappings ALTER COLUMN mapping_status SET DEFAULT 'unmapped';
ALTER TABLE xero_pay_item_account_code_selections ALTER COLUMN selection_status SET DEFAULT 'none';
ALTER TABLE xero_pay_item_requirement_records ALTER COLUMN requirement_status SET DEFAULT 'proposed';
ALTER TABLE xero_submission_runs ALTER COLUMN source_kind SET DEFAULT 'approved_timesheets';
ALTER TABLE xero_submission_runs ALTER COLUMN status SET DEFAULT 'previewed';
ALTER TABLE xero_timesheet_preparation_runs ALTER COLUMN status SET DEFAULT 'started';
ALTER TABLE xero_timesheet_preparation_decisions ALTER COLUMN decision_status SET DEFAULT 'pending';
ALTER TABLE xero_timesheet_submissions ALTER COLUMN status SET DEFAULT 'pending';

ALTER TABLE xero_sync_runs
    ADD CONSTRAINT xero_sync_runs_sync_status_check CHECK (sync_status IN ('running', 'succeeded', 'failed'));
ALTER TABLE xero_staff_mappings
    ADD CONSTRAINT xero_staff_mappings_mapping_status_check CHECK (mapping_status IN ('verified', 'not_applicable', 'stale'));
ALTER TABLE xero_earnings_rate_mappings
    ADD CONSTRAINT xero_earnings_rate_mappings_mapping_status_check CHECK (mapping_status IN ('unmapped', 'verified', 'stale'));
ALTER TABLE xero_pay_item_requirement_records
    ADD CONSTRAINT xero_pay_item_requirement_records_requirement_status_check CHECK (requirement_status IN ('proposed', 'matched', 'created', 'ignored', 'stale', 'rate_changed'));
ALTER TABLE xero_submission_runs
    ADD CONSTRAINT xero_submission_runs_source_kind_check CHECK (source_kind = 'approved_timesheets'),
    ADD CONSTRAINT xero_submission_runs_status_check CHECK (status IN ('previewed', 'blocked', 'pending', 'submitted', 'partially_failed', 'failed', 'superseded'));
ALTER TABLE xero_timesheet_preparation_runs
    ADD CONSTRAINT xero_timesheet_preparation_runs_status_check CHECK (status IN ('started', 'preparing', 'needs_reconnect', 'needs_approval', 'blocked', 'resolved', 'ready_for_preview', 'previewed', 'submitted', 'failed', 'cancelled'));
ALTER TABLE xero_timesheet_preparation_decisions
    ADD CONSTRAINT xero_timesheet_preparation_decisions_decision_kind_check CHECK (decision_kind IN ('staff_auto_match', 'staff_manual_mapping', 'staff_not_paid', 'staff_step_approved', 'pay_item_create', 'account_code', 'calendar_selection')),
    ADD CONSTRAINT xero_timesheet_preparation_decisions_decision_status_check CHECK (decision_status IN ('pending', 'proposed', 'applied', 'blocked', 'resolved', 'dismissed'));
ALTER TABLE xero_timesheet_submissions
    ADD CONSTRAINT xero_timesheet_submissions_status_check CHECK (status IN ('blocked', 'pending', 'submitted', 'failed', 'skipped', 'superseded'));

CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee ON xero_staff_mappings (xero_connection_id, xero_employee_id) WHERE mapping_status = 'verified' AND xero_employee_id IS NOT NULL;
CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period ON xero_timesheet_submissions (xero_connection_id, xero_employee_id, pay_period_start, pay_period_end) WHERE status <> 'superseded';
COMMIT;
```

Keep the enum types until all typed application versions are retired. Dropping
types is optional cleanup, not recovery, and requires a separate approval after
confirming no columns or prepared statements reference them.
