CREATE INDEX IF NOT EXISTS idx_leave_requests_venue_status_staff_dates
    ON leave_requests (venue_id, status, staff_id, start_date, end_date);

CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_group_staff_day_slot
    ON staff_shift_preferences (roster_group_id, staff_id, weekday_index, slot_name_id);
