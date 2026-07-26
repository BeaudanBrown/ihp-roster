-- #239: retire the legacy SQL wage calculators only after every approved entry
-- has an immutable active Haskell calculation. This migration deliberately has
-- no repository-managed restoration path.
DO $$
DECLARE
    missing_entry_ids TEXT;
BEGIN
    SELECT string_agg(te.id::TEXT, ', ' ORDER BY te.starts_at, te.id)
      INTO missing_entry_ids
      FROM timesheet_entries te
      LEFT JOIN timesheet_pay_calculations calculation
        ON calculation.id = te.active_pay_calculation_id
     WHERE te.is_approved = TRUE
       AND te.deleted_at IS NULL
       AND (
            calculation.id IS NULL
            OR calculation.sealed_at IS NULL
            OR calculation.timesheet_entry_id <> te.id
            OR calculation.approved_at IS DISTINCT FROM te.approved_at
            OR calculation.approved_by_user_id IS DISTINCT FROM te.approved_by_user_id
            OR calculation.staff_pay_version_id IS DISTINCT FROM te.staff_pay_version_id
            OR calculation.shift_type_pay_version_id IS DISTINCT FROM te.shift_type_pay_version_id
            OR NOT EXISTS (
                SELECT 1
                  FROM timesheet_pay_time_segments segment
                 WHERE segment.timesheet_pay_calculation_id = calculation.id
            )
            OR NOT EXISTS (
                SELECT 1
                  FROM timesheet_pay_earnings_components component
                 WHERE component.timesheet_pay_calculation_id = calculation.id
            )
            OR (
                SELECT COUNT(*) <> COALESCE(MAX(segment.ordinal) + 1, 0)
                  FROM timesheet_pay_time_segments segment
                 WHERE segment.timesheet_pay_calculation_id = calculation.id
            )
            OR (
                SELECT COUNT(*) <> COALESCE(MAX(component.ordinal) + 1, 0)
                  FROM timesheet_pay_earnings_components component
                 WHERE component.timesheet_pay_calculation_id = calculation.id
            )
       );

    IF missing_entry_ids IS NOT NULL THEN
        RAISE EXCEPTION
            'cannot retire SQL wage calculators; approved entries lack immutable Haskell calculations: %',
            missing_entry_ids;
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS calculate_timesheet_pay_range(UUID, DATE, DATE);
DROP FUNCTION IF EXISTS calculate_timesheet_pay(UUID);
