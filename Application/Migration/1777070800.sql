ALTER TABLE venues
    ADD COLUMN IF NOT EXISTS closed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS closed_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS retention_until TIMESTAMP WITH TIME ZONE DEFAULT NULL;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deactivated_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deactivation_reason TEXT DEFAULT NULL;

ALTER TABLE venue_memberships
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE staff
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE shift_types
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE report_definitions
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE report_definition_shift_type_filters
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE roster_groups
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE staff_roster_groups
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE slot_names
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE day_names
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE roster_weeks
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archived_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT DEFAULT NULL;

ALTER TABLE roster_slots
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE staff_shift_preferences
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE leave_requests
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE export_jobs
    ADD COLUMN IF NOT EXISTS retention_until TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS purged_file_contents_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS purged_by_user_id UUID DEFAULT NULL;

ALTER TABLE timesheet_entries
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS deleted_by_user_id UUID DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS delete_reason TEXT DEFAULT NULL;

ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_venue_id_user_id_key;
ALTER TABLE report_definitions DROP CONSTRAINT IF EXISTS report_definitions_venue_id_slug_key;
ALTER TABLE roster_groups DROP CONSTRAINT IF EXISTS roster_groups_venue_id_name_key;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_staff_id_roster_group_id_key;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_staff_id_roster_group_id_slot_name_id_weekday_i_key;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_staff_id_roster_group_id_slot_name_id_weekday_index_key;

DROP INDEX IF EXISTS idx_staff_linked_user_per_venue;
DROP INDEX IF EXISTS idx_slot_names_active_name;
DROP INDEX IF EXISTS idx_roster_slots_day;
DROP INDEX IF EXISTS idx_roster_slots_staff;
DROP INDEX IF EXISTS idx_timesheet_entries_venue_staff;
DROP INDEX IF EXISTS idx_timesheet_entries_venue_worked_on;
DROP INDEX IF EXISTS idx_leave_requests_venue_staff;
DROP INDEX IF EXISTS idx_leave_requests_venue_start_date;
DROP INDEX IF EXISTS idx_leave_requests_venue_status_staff_dates;
DROP INDEX IF EXISTS idx_staff_shift_preferences_venue_staff;
DROP INDEX IF EXISTS idx_staff_shift_preferences_staff;
DROP INDEX IF EXISTS idx_staff_shift_preferences_group_day;
DROP INDEX IF EXISTS idx_staff_shift_preferences_group_staff_day_slot;

CREATE UNIQUE INDEX IF NOT EXISTS idx_venue_memberships_active_venue_user ON venue_memberships (venue_id, user_id) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_linked_user_per_venue ON staff (venue_id, user_id) WHERE user_id IS NOT NULL AND is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_report_definitions_active_slug ON report_definitions (venue_id, slug) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_report_definition_shift_type_filters_active ON report_definition_shift_type_filters (report_definition_id, shift_type_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_groups_active_name ON roster_groups (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_roster_groups_active_assignment ON staff_roster_groups (staff_id, roster_group_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_slot_names_active_name ON slot_names (roster_group_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_roster_slots_day ON roster_slots (roster_day_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_roster_slots_staff ON roster_slots (staff_id) WHERE staff_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_timesheet_entries_venue_staff ON timesheet_entries (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_timesheet_entries_venue_worked_on ON timesheet_entries (venue_id, worked_on) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_leave_requests_venue_staff ON leave_requests (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_leave_requests_venue_start_date ON leave_requests (venue_id, start_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_leave_requests_venue_status_staff_dates ON leave_requests (venue_id, status, staff_id, start_date, end_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_venue_staff ON staff_shift_preferences (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_staff ON staff_shift_preferences (staff_id) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_group_day ON staff_shift_preferences (roster_group_id, weekday_index) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_staff_shift_preferences_group_staff_day_slot ON staff_shift_preferences (roster_group_id, staff_id, weekday_index, slot_name_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_staff_shift_preferences_active_unique ON staff_shift_preferences (staff_id, roster_group_id, slot_name_id, weekday_index) WHERE deleted_at IS NULL;

ALTER TABLE venues DROP CONSTRAINT IF EXISTS venues_closed_by_user_id_fk;
ALTER TABLE venues ADD CONSTRAINT venues_closed_by_user_id_fk FOREIGN KEY (closed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_deactivated_by_user_id_fk;
ALTER TABLE users ADD CONSTRAINT users_deactivated_by_user_id_fk FOREIGN KEY (deactivated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_venue_id_fkey;
ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_venue_id_fk;
ALTER TABLE venue_memberships ADD CONSTRAINT venue_memberships_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_user_id_fkey;
ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_user_id_fk;
ALTER TABLE venue_memberships ADD CONSTRAINT venue_memberships_user_id_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_archived_by_user_id_fkey;
ALTER TABLE venue_memberships DROP CONSTRAINT IF EXISTS venue_memberships_archived_by_user_id_fk;
ALTER TABLE venue_memberships ADD CONSTRAINT venue_memberships_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_venue_id_fkey;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_venue_id_fk;
ALTER TABLE staff ADD CONSTRAINT staff_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_user_id_fkey;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_user_id_fk;
ALTER TABLE staff ADD CONSTRAINT staff_user_id_fk FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_archived_by_user_id_fkey;
ALTER TABLE staff DROP CONSTRAINT IF EXISTS staff_archived_by_user_id_fk;
ALTER TABLE staff ADD CONSTRAINT staff_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_venue_id_fkey;
ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_venue_id_fk;
ALTER TABLE shift_types ADD CONSTRAINT shift_types_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_archived_by_user_id_fkey;
ALTER TABLE shift_types DROP CONSTRAINT IF EXISTS shift_types_archived_by_user_id_fk;
ALTER TABLE shift_types ADD CONSTRAINT shift_types_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE report_definitions DROP CONSTRAINT IF EXISTS report_definitions_venue_id_fkey;
ALTER TABLE report_definitions DROP CONSTRAINT IF EXISTS report_definitions_venue_id_fk;
ALTER TABLE report_definitions ADD CONSTRAINT report_definitions_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE report_definitions DROP CONSTRAINT IF EXISTS report_definitions_archived_by_user_id_fkey;
ALTER TABLE report_definitions DROP CONSTRAINT IF EXISTS report_definitions_archived_by_user_id_fk;
ALTER TABLE report_definitions ADD CONSTRAINT report_definitions_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_report_definition_id_fkey;
ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_report_definition_id_fk;
ALTER TABLE report_definition_shift_type_filters ADD CONSTRAINT report_definition_shift_type_filters_report_definition_id_fk FOREIGN KEY (report_definition_id) REFERENCES report_definitions (id) ON DELETE RESTRICT;
ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_shift_type_id_fkey;
ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_shift_type_id_fk;
ALTER TABLE report_definition_shift_type_filters ADD CONSTRAINT report_definition_shift_type_filters_shift_type_id_fk FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT;
ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_deleted_by_user_id_fkey;
ALTER TABLE report_definition_shift_type_filters DROP CONSTRAINT IF EXISTS report_definition_shift_type_filters_deleted_by_user_id_fk;
ALTER TABLE report_definition_shift_type_filters ADD CONSTRAINT report_definition_shift_type_filters_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE roster_groups DROP CONSTRAINT IF EXISTS roster_groups_venue_id_fkey;
ALTER TABLE roster_groups DROP CONSTRAINT IF EXISTS roster_groups_venue_id_fk;
ALTER TABLE roster_groups ADD CONSTRAINT roster_groups_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE roster_groups DROP CONSTRAINT IF EXISTS roster_groups_archived_by_user_id_fkey;
ALTER TABLE roster_groups DROP CONSTRAINT IF EXISTS roster_groups_archived_by_user_id_fk;
ALTER TABLE roster_groups ADD CONSTRAINT roster_groups_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_staff_id_fkey;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_staff_id_fk;
ALTER TABLE staff_roster_groups ADD CONSTRAINT staff_roster_groups_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_roster_group_id_fkey;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_roster_group_id_fk;
ALTER TABLE staff_roster_groups ADD CONSTRAINT staff_roster_groups_roster_group_id_fk FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_deleted_by_user_id_fkey;
ALTER TABLE staff_roster_groups DROP CONSTRAINT IF EXISTS staff_roster_groups_deleted_by_user_id_fk;
ALTER TABLE staff_roster_groups ADD CONSTRAINT staff_roster_groups_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_venue_id_fkey;
ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_venue_id_fk;
ALTER TABLE slot_names ADD CONSTRAINT slot_names_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_roster_group_id_fkey;
ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_roster_group_id_fk;
ALTER TABLE slot_names ADD CONSTRAINT slot_names_roster_group_id_fk FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT;
ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_archived_by_user_id_fkey;
ALTER TABLE slot_names DROP CONSTRAINT IF EXISTS slot_names_archived_by_user_id_fk;
ALTER TABLE slot_names ADD CONSTRAINT slot_names_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_venue_id_fkey;
ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_venue_id_fk;
ALTER TABLE day_names ADD CONSTRAINT day_names_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_archived_by_user_id_fkey;
ALTER TABLE day_names DROP CONSTRAINT IF EXISTS day_names_archived_by_user_id_fk;
ALTER TABLE day_names ADD CONSTRAINT day_names_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_venue_id_fkey;
ALTER TABLE venue_config DROP CONSTRAINT IF EXISTS venue_config_venue_id_fk;
ALTER TABLE venue_config ADD CONSTRAINT venue_config_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;

ALTER TABLE pay_config_snapshots DROP CONSTRAINT IF EXISTS pay_config_snapshots_venue_id_fkey;
ALTER TABLE pay_config_snapshots DROP CONSTRAINT IF EXISTS pay_config_snapshots_venue_id_fk;
ALTER TABLE pay_config_snapshots ADD CONSTRAINT pay_config_snapshots_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE pay_config_snapshots DROP CONSTRAINT IF EXISTS pay_config_snapshots_created_by_user_id_fkey;
ALTER TABLE pay_config_snapshots DROP CONSTRAINT IF EXISTS pay_config_snapshots_created_by_user_id_fk;
ALTER TABLE pay_config_snapshots ADD CONSTRAINT pay_config_snapshots_created_by_user_id_fk FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_venue_id_fkey;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_venue_id_fk;
ALTER TABLE roster_weeks ADD CONSTRAINT roster_weeks_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_roster_group_id_fkey;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_roster_group_id_fk;
ALTER TABLE roster_weeks ADD CONSTRAINT roster_weeks_roster_group_id_fk FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_archived_by_user_id_fkey;
ALTER TABLE roster_weeks DROP CONSTRAINT IF EXISTS roster_weeks_archived_by_user_id_fk;
ALTER TABLE roster_weeks ADD CONSTRAINT roster_weeks_archived_by_user_id_fk FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE roster_days DROP CONSTRAINT IF EXISTS roster_days_roster_week_id_fkey;
ALTER TABLE roster_days DROP CONSTRAINT IF EXISTS roster_days_roster_week_id_fk;
ALTER TABLE roster_days ADD CONSTRAINT roster_days_roster_week_id_fk FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT;

ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_roster_day_id_fkey;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_roster_day_id_fk;
ALTER TABLE roster_slots ADD CONSTRAINT roster_slots_roster_day_id_fk FOREIGN KEY (roster_day_id) REFERENCES roster_days (id) ON DELETE RESTRICT;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_staff_id_fkey;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_staff_id_fk;
ALTER TABLE roster_slots ADD CONSTRAINT roster_slots_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE SET NULL;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_slot_name_id_fkey;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_slot_name_id_fk;
ALTER TABLE roster_slots ADD CONSTRAINT roster_slots_slot_name_id_fk FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE RESTRICT;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_deleted_by_user_id_fkey;
ALTER TABLE roster_slots DROP CONSTRAINT IF EXISTS roster_slots_deleted_by_user_id_fk;
ALTER TABLE roster_slots ADD CONSTRAINT roster_slots_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_venue_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_venue_id_fk;
ALTER TABLE staff_shift_preferences ADD CONSTRAINT staff_shift_preferences_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_staff_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_staff_id_fk;
ALTER TABLE staff_shift_preferences ADD CONSTRAINT staff_shift_preferences_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_roster_group_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_roster_group_id_fk;
ALTER TABLE staff_shift_preferences ADD CONSTRAINT staff_shift_preferences_roster_group_id_fk FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_slot_name_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_slot_name_id_fk;
ALTER TABLE staff_shift_preferences ADD CONSTRAINT staff_shift_preferences_slot_name_id_fk FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE RESTRICT;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_deleted_by_user_id_fkey;
ALTER TABLE staff_shift_preferences DROP CONSTRAINT IF EXISTS staff_shift_preferences_deleted_by_user_id_fk;
ALTER TABLE staff_shift_preferences ADD CONSTRAINT staff_shift_preferences_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_venue_id_fkey;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_venue_id_fk;
ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_staff_id_fkey;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_staff_id_fk;
ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_deleted_by_user_id_fkey;
ALTER TABLE leave_requests DROP CONSTRAINT IF EXISTS leave_requests_deleted_by_user_id_fk;
ALTER TABLE leave_requests ADD CONSTRAINT leave_requests_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_venue_id_fkey;
ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_venue_id_fk;
ALTER TABLE leave_request_events ADD CONSTRAINT leave_request_events_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_leave_request_id_fkey;
ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_leave_request_id_fk;
ALTER TABLE leave_request_events ADD CONSTRAINT leave_request_events_leave_request_id_fk FOREIGN KEY (leave_request_id) REFERENCES leave_requests (id) ON DELETE RESTRICT;
ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_actor_user_id_fkey;
ALTER TABLE leave_request_events DROP CONSTRAINT IF EXISTS leave_request_events_actor_user_id_fk;
ALTER TABLE leave_request_events ADD CONSTRAINT leave_request_events_actor_user_id_fk FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_venue_id_fkey;
ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_venue_id_fk;
ALTER TABLE audit_events ADD CONSTRAINT audit_events_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_actor_user_id_fkey;
ALTER TABLE audit_events DROP CONSTRAINT IF EXISTS audit_events_actor_user_id_fk;
ALTER TABLE audit_events ADD CONSTRAINT audit_events_actor_user_id_fk FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_venue_id_fkey;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_venue_id_fk;
ALTER TABLE export_jobs ADD CONSTRAINT export_jobs_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_requested_by_user_id_fkey;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_requested_by_user_id_fk;
ALTER TABLE export_jobs ADD CONSTRAINT export_jobs_requested_by_user_id_fk FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_downloaded_by_user_id_fkey;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_downloaded_by_user_id_fk;
ALTER TABLE export_jobs ADD CONSTRAINT export_jobs_downloaded_by_user_id_fk FOREIGN KEY (downloaded_by_user_id) REFERENCES users (id) ON DELETE SET NULL;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_purged_by_user_id_fkey;
ALTER TABLE export_jobs DROP CONSTRAINT IF EXISTS export_jobs_purged_by_user_id_fk;
ALTER TABLE export_jobs ADD CONSTRAINT export_jobs_purged_by_user_id_fk FOREIGN KEY (purged_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_venue_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_venue_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_staff_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_staff_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_shift_type_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_shift_type_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_shift_type_id_fk FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_pay_config_snapshot_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_pay_config_snapshot_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_pay_config_snapshot_id_fk FOREIGN KEY (pay_config_snapshot_id) REFERENCES pay_config_snapshots (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_approved_by_user_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_approved_by_user_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_approved_by_user_id_fk FOREIGN KEY (approved_by_user_id) REFERENCES users (id) ON DELETE SET NULL;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_deleted_by_user_id_fkey;
ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_deleted_by_user_id_fk;
ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_deleted_by_user_id_fk FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_venue_id_fkey;
ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_venue_id_fk;
ALTER TABLE timesheet_entry_versions ADD CONSTRAINT timesheet_entry_versions_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_timesheet_entry_id_fkey;
ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_timesheet_entry_id_fk;
ALTER TABLE timesheet_entry_versions ADD CONSTRAINT timesheet_entry_versions_timesheet_entry_id_fk FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT;
ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_actor_user_id_fkey;
ALTER TABLE timesheet_entry_versions DROP CONSTRAINT IF EXISTS timesheet_entry_versions_actor_user_id_fk;
ALTER TABLE timesheet_entry_versions ADD CONSTRAINT timesheet_entry_versions_actor_user_id_fk FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT;

ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_venue_id_fkey;
ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_venue_id_fk;
ALTER TABLE venue_membership_role_events ADD CONSTRAINT venue_membership_role_events_venue_id_fk FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_venue_membership_id_fkey;
ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_venue_membership_id_fk;
ALTER TABLE venue_membership_role_events ADD CONSTRAINT venue_membership_role_events_venue_membership_id_fk FOREIGN KEY (venue_membership_id) REFERENCES venue_memberships (id) ON DELETE RESTRICT;
ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_actor_user_id_fkey;
ALTER TABLE venue_membership_role_events DROP CONSTRAINT IF EXISTS venue_membership_role_events_actor_user_id_fk;
ALTER TABLE venue_membership_role_events ADD CONSTRAINT venue_membership_role_events_actor_user_id_fk FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT;

CREATE OR REPLACE FUNCTION prevent_hard_delete()
RETURNS TRIGGER
AS $$
BEGIN
    IF current_setting('ihp_roster.allow_hard_delete', true) = 'on' THEN
        RETURN OLD;
    END IF;

    RAISE EXCEPTION 'hard delete blocked for protected table %', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_hard_delete_venues ON venues;
CREATE TRIGGER prevent_hard_delete_venues BEFORE DELETE ON venues FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_users ON users;
CREATE TRIGGER prevent_hard_delete_users BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_venue_memberships ON venue_memberships;
CREATE TRIGGER prevent_hard_delete_venue_memberships BEFORE DELETE ON venue_memberships FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_staff ON staff;
CREATE TRIGGER prevent_hard_delete_staff BEFORE DELETE ON staff FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_staff_roster_groups ON staff_roster_groups;
CREATE TRIGGER prevent_hard_delete_staff_roster_groups BEFORE DELETE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_roster_groups ON roster_groups;
CREATE TRIGGER prevent_hard_delete_roster_groups BEFORE DELETE ON roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_slot_names ON slot_names;
CREATE TRIGGER prevent_hard_delete_slot_names BEFORE DELETE ON slot_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_day_names ON day_names;
CREATE TRIGGER prevent_hard_delete_day_names BEFORE DELETE ON day_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_shift_types ON shift_types;
CREATE TRIGGER prevent_hard_delete_shift_types BEFORE DELETE ON shift_types FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_report_definitions ON report_definitions;
CREATE TRIGGER prevent_hard_delete_report_definitions BEFORE DELETE ON report_definitions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_report_definition_shift_type_filters ON report_definition_shift_type_filters;
CREATE TRIGGER prevent_hard_delete_report_definition_shift_type_filters BEFORE DELETE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_venue_config ON venue_config;
CREATE TRIGGER prevent_hard_delete_venue_config BEFORE DELETE ON venue_config FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_pay_config_snapshots ON pay_config_snapshots;
CREATE TRIGGER prevent_hard_delete_pay_config_snapshots BEFORE DELETE ON pay_config_snapshots FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_roster_weeks ON roster_weeks;
CREATE TRIGGER prevent_hard_delete_roster_weeks BEFORE DELETE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_roster_days ON roster_days;
CREATE TRIGGER prevent_hard_delete_roster_days BEFORE DELETE ON roster_days FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_roster_slots ON roster_slots;
CREATE TRIGGER prevent_hard_delete_roster_slots BEFORE DELETE ON roster_slots FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_staff_shift_preferences ON staff_shift_preferences;
CREATE TRIGGER prevent_hard_delete_staff_shift_preferences BEFORE DELETE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_leave_requests ON leave_requests;
CREATE TRIGGER prevent_hard_delete_leave_requests BEFORE DELETE ON leave_requests FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_leave_request_events ON leave_request_events;
CREATE TRIGGER prevent_hard_delete_leave_request_events BEFORE DELETE ON leave_request_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_timesheet_entries ON timesheet_entries;
CREATE TRIGGER prevent_hard_delete_timesheet_entries BEFORE DELETE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_timesheet_entry_versions ON timesheet_entry_versions;
CREATE TRIGGER prevent_hard_delete_timesheet_entry_versions BEFORE DELETE ON timesheet_entry_versions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_venue_membership_role_events ON venue_membership_role_events;
CREATE TRIGGER prevent_hard_delete_venue_membership_role_events BEFORE DELETE ON venue_membership_role_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_audit_events ON audit_events;
CREATE TRIGGER prevent_hard_delete_audit_events BEFORE DELETE ON audit_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
DROP TRIGGER IF EXISTS prevent_hard_delete_export_jobs ON export_jobs;
CREATE TRIGGER prevent_hard_delete_export_jobs BEFORE DELETE ON export_jobs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();

CREATE OR REPLACE FUNCTION calculate_timesheet_pay_range(p_staff_id UUID, p_from_date DATE, p_to_date DATE)
RETURNS JSONB
AS $$
    SELECT COALESCE(
        jsonb_agg(calculate_timesheet_pay(te.id) ORDER BY te.worked_on ASC, te.id ASC),
        jsonb_build_array()
    )
    FROM timesheet_entries te
    WHERE te.staff_id = p_staff_id
        AND te.worked_on >= p_from_date
        AND te.worked_on <= p_to_date
        AND te.deleted_at IS NULL;
$$ LANGUAGE SQL;
