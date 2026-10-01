-- Immutable report-generation snapshots and their delivery lifecycle.
CREATE TYPE payroll_report_origin_enum AS ENUM ('payroll_report_scheduled', 'payroll_report_manual', 'payroll_report_updated');
CREATE TYPE payroll_report_status_enum AS ENUM ('payroll_report_ready', 'payroll_report_no_data', 'payroll_report_failed', 'payroll_report_missed', 'payroll_report_cancelled', 'payroll_report_queued', 'payroll_report_accepted', 'payroll_report_bounced', 'payroll_report_ambiguous', 'payroll_report_disabled');
CREATE TABLE payroll_report_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    settings_id UUID NOT NULL,
    export_job_id UUID,
    reporting_week DATE NOT NULL,
    range_end DATE NOT NULL,
    origin payroll_report_origin_enum NOT NULL,
    status payroll_report_status_enum NOT NULL,
    recipients TEXT[] NOT NULL,
    template_snapshot JSONB NOT NULL,
    excluded_entry_count INT DEFAULT 0 NOT NULL,
    approved_entry_count INT DEFAULT 0 NOT NULL,
    delivery_revision INT NOT NULL,
    schedule_activated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    requested_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (settings_id) REFERENCES payroll_report_settings (id) ON DELETE RESTRICT,
    FOREIGN KEY (export_job_id) REFERENCES export_jobs (id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((excluded_entry_count >= 0) AND (approved_entry_count >= 0)),
    CHECK (range_end >= reporting_week),
    CHECK ((cardinality(recipients) > 0) AND (cardinality(recipients) <= 50)),
    CHECK ((origin <> 'payroll_report_scheduled') OR (scheduled_at IS NOT NULL))
);
CREATE UNIQUE INDEX payroll_report_runs_scheduled_week_idx ON payroll_report_runs (venue_id, reporting_week) WHERE origin = 'payroll_report_scheduled';
CREATE INDEX payroll_report_runs_venue_week_idx ON payroll_report_runs (venue_id, reporting_week, created_at);
