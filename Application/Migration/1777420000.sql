ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_ideal_shifts_per_week_check;
ALTER TABLE staff
    ADD CONSTRAINT staff_ideal_shifts_per_week_check
    CHECK (ideal_shifts_per_week >= 0 AND ideal_shifts_per_week <= 7);

ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_weekday_index_check;
ALTER TABLE day_names
    ADD CONSTRAINT day_names_weekday_index_check
    CHECK (weekday_index >= 0 AND weekday_index <= 6);

ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_roster_week_starts_on_check;
ALTER TABLE venue_config
    ADD CONSTRAINT venue_config_roster_week_starts_on_check
    CHECK (roster_week_starts_on >= 0 AND roster_week_starts_on <= 6);

ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_late_to_early_gap_check;
ALTER TABLE venue_config
    ADD CONSTRAINT venue_config_late_to_early_gap_check
    CHECK (late_to_early_min_start_gap_minutes >= 0);

ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_timesheet_edit_window_check;
ALTER TABLE venue_config
    ADD CONSTRAINT venue_config_timesheet_edit_window_check
    CHECK (staff_timesheet_edit_window_days >= 0);

ALTER TABLE roster_days DROP CONSTRAINT IF EXISTS roster_days_day_offset_check;
ALTER TABLE roster_days
    ADD CONSTRAINT roster_days_day_offset_check
    CHECK (day_offset >= 0 AND day_offset <= 6);

ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_row_index_check;
ALTER TABLE roster_slots
    ADD CONSTRAINT roster_slots_row_index_check
    CHECK (row_index >= 0);

ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_slot_sort_order_check;
ALTER TABLE roster_slots
    ADD CONSTRAINT roster_slots_slot_sort_order_check
    CHECK (slot_sort_order >= 0);

ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_duration_minutes_check;
ALTER TABLE roster_slots
    ADD CONSTRAINT roster_slots_duration_minutes_check
    CHECK (duration_minutes IS NULL OR duration_minutes >= 0);

ALTER TABLE staff_availability DROP CONSTRAINT IF EXISTS staff_availability_key_shape_check;
ALTER TABLE staff_availability
    ADD CONSTRAINT staff_availability_key_shape_check
    CHECK (((weekday_index IS NOT NULL) AND (specific_date IS NULL)) OR ((weekday_index IS NULL) AND (specific_date IS NOT NULL)));

ALTER TABLE staff_availability DROP CONSTRAINT IF EXISTS staff_availability_weekday_index_check;
ALTER TABLE staff_availability
    ADD CONSTRAINT staff_availability_weekday_index_check
    CHECK (weekday_index IS NULL OR (weekday_index >= 0 AND weekday_index <= 6));

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_weekday_index_check;
ALTER TABLE staff_shift_preferences
    ADD CONSTRAINT staff_shift_preferences_weekday_index_check
    CHECK (weekday_index >= 0 AND weekday_index <= 6);

ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_date_range_check;
ALTER TABLE leave_requests
    ADD CONSTRAINT leave_requests_date_range_check
    CHECK (end_date > start_date);

ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_break_minutes_check;
ALTER TABLE timesheet_entries
    ADD CONSTRAINT timesheet_entries_break_minutes_check
    CHECK (break_minutes >= 0);

ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_break_shape_check;
ALTER TABLE timesheet_entries
    ADD CONSTRAINT timesheet_entries_break_shape_check
    CHECK (((had_break = FALSE) AND break_start_time IS NULL AND break_end_time IS NULL AND break_minutes = 0) OR ((had_break = TRUE) AND break_start_time IS NOT NULL AND break_end_time IS NOT NULL AND break_minutes > 0));

ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_approval_shape_check;
ALTER TABLE timesheet_entries
    ADD CONSTRAINT timesheet_entries_approval_shape_check
    CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND pay_config_snapshot_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND pay_config_snapshot_id IS NOT NULL));

CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_slots_active_cell
    ON roster_slots (roster_day_id, row_index, slot_name_id)
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_groups_one_active_default
    ON roster_groups (venue_id)
    WHERE is_default = TRUE
      AND is_active = TRUE
      AND archived_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_shift_types_active_name
    ON shift_types (venue_id, name)
    WHERE is_active = TRUE
      AND archived_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_availability_active_weekday
    ON staff_availability (staff_id, weekday_index)
    WHERE weekday_index IS NOT NULL
      AND deleted_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_availability_active_date
    ON staff_availability (staff_id, specific_date)
    WHERE specific_date IS NOT NULL
      AND deleted_at IS NULL;
