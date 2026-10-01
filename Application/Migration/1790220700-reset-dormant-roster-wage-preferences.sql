UPDATE user_preferences AS preferences
SET show_wage_estimates = FALSE,
    updated_at = NOW()
WHERE preferences.show_wage_estimates = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM users
      WHERE users.id = preferences.user_id
        AND users.platform_role = 'super_admin'
  )
  AND NOT EXISTS (
      SELECT 1
      FROM venue_memberships
      WHERE venue_memberships.user_id = preferences.user_id
        AND venue_memberships.venue_role IN ('venue_admin', 'venue_owner')
        AND venue_memberships.is_active = TRUE
        AND venue_memberships.archived_at IS NULL
  );
