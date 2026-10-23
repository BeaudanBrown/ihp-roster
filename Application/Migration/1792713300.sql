-- Align legacy configurable report days with the roster calendar. Preserve
-- recipients, templates, manual sends and history; restart changed schedules
-- in the future, invalidating automatic snapshots through schedule_activated_at.
WITH aligned AS (
    UPDATE payroll_report_settings AS settings
    SET weekday = config.roster_week_starts_on,
        revision = settings.revision + 1,
        schedule_activated_at = NOW(),
        updated_at = NOW()
    FROM venue_config AS config
    WHERE settings.venue_id = config.venue_id
      AND settings.weekday <> config.roster_week_starts_on
    RETURNING settings.id
)
UPDATE payroll_report_runs AS run
SET status = 'payroll_report_cancelled', updated_at = NOW()
FROM aligned
WHERE run.settings_id = aligned.id
  AND run.origin = 'payroll_report_scheduled'
  AND run.status IN ('payroll_report_ready', 'payroll_report_no_data', 'payroll_report_queued');
