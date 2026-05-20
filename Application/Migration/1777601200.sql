ALTER TABLE xero_submission_runs
    ADD COLUMN IF NOT EXISTS xero_timesheet_preparation_run_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS selected_payroll_calendar_id TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS selected_payroll_calendar_name TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS selected_period_key TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS payment_date DATE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS xero_pay_run_id TEXT DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS xero_pay_run_status TEXT DEFAULT NULL;

ALTER TABLE xero_submission_runs
    ADD CONSTRAINT xero_submission_runs_preparation_run_id_fk
    FOREIGN KEY (xero_timesheet_preparation_run_id) REFERENCES xero_timesheet_preparation_runs (id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_xero_submission_runs_preparation
    ON xero_submission_runs (xero_timesheet_preparation_run_id)
    WHERE xero_timesheet_preparation_run_id IS NOT NULL;
