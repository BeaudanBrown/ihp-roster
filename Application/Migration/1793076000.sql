-- New schedules start at 06:00 venue-local. This default-only change must not
-- retime existing settings, activate automation, or touch delivery snapshots.
ALTER TABLE payroll_report_settings ALTER COLUMN minute_of_day SET DEFAULT 360;
