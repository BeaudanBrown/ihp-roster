ALTER TABLE user_preferences
    ADD COLUMN timesheet_wage_display_mode wage_display_mode_enum DEFAULT 'hidden' NOT NULL;

-- Preserve only choices that were previously reachable by an authorized role.
-- A global preference is retained when at least one active membership had an
-- eligible role, or for active founder-support accounts. Dormant Manager and
-- Supervisor booleans do not become newly visible pay authority.
UPDATE user_preferences AS preferences
SET timesheet_wage_display_mode = 'visible_timesheets'
WHERE preferences.show_timesheet_wage_estimates = TRUE
  AND (
      EXISTS (
          SELECT 1
          FROM venue_memberships AS memberships
          WHERE memberships.user_id = preferences.user_id
            AND memberships.is_active = TRUE
            AND memberships.archived_at IS NULL
            AND memberships.venue_role IN ('worker', 'venue_admin', 'venue_owner')
      )
      OR EXISTS (
          SELECT 1
          FROM users
          WHERE users.id = preferences.user_id
            AND users.platform_role = 'super_admin'
            AND users.deactivated_at IS NULL
      )
  );
