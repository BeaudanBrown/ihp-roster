ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_weekday_index_unique;
ALTER TABLE pay_level_day_rules DROP CONSTRAINT IF EXISTS pay_level_day_rules_unique;
ALTER TABLE roster_days DROP CONSTRAINT IF EXISTS roster_days_unique;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_week_offset_unique;
ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_is_singleton_unique;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_staff_id_fk;
ALTER TABLE pay_level_day_rules DROP CONSTRAINT IF EXISTS pay_level_day_rules_day_name_id_fk;
ALTER TABLE pay_level_day_rules DROP CONSTRAINT IF EXISTS pay_level_day_rules_pay_level_id_fk;
ALTER TABLE roster_days DROP CONSTRAINT IF EXISTS roster_days_roster_week_id_fk;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_roster_day_id_fk;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_shift_type_id_fk;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_slot_name_id_fk;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_staff_id_fk;
ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_default_pay_level_id_fk;
ALTER TABLE staff_availability DROP CONSTRAINT IF EXISTS staff_availability_staff_id_fk;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_user_id_fk;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_approved_by_user_id_fk;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_staff_id_fk;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role'
    ) AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_role_valid') THEN
        ALTER TABLE users ADD CONSTRAINT users_role_valid CHECK (role IN ('staff', 'manager', 'admin'));
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'leave_requests' AND column_name = 'status'
    ) AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'leave_requests_status_valid') THEN
        ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_status_valid CHECK (status IN ('pending', 'approved', 'denied'));
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'timesheet_entries' AND column_name = 'is_approved'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'timesheet_entries' AND column_name = 'approved_at'
    ) AND EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'timesheet_entries' AND column_name = 'approved_by_user_id'
    ) AND NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'timesheet_entries_approval_consistency') THEN
        ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_approval_consistency CHECK (((NOT is_approved) AND approved_at IS NULL AND approved_by_user_id IS NULL) OR (is_approved AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL));
    END IF;
END
$$;
