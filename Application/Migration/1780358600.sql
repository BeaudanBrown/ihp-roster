ALTER TABLE xero_timesheet_preparation_runs
    ALTER COLUMN selected_payroll_calendar_id DROP NOT NULL,
    ALTER COLUMN selected_period_key DROP NOT NULL,
    ALTER COLUMN pay_period_start DROP NOT NULL,
    ALTER COLUMN pay_period_end DROP NOT NULL;
