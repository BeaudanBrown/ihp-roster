-- Your database schema. Use the Schema Designer at http://localhost:8001/ to add some tables.
CREATE TYPE venue_status_enum AS ENUM ('active', 'inactive');
CREATE TYPE venue_role_enum AS ENUM ('worker', 'manager', 'venue_admin', 'venue_owner');
CREATE TYPE platform_role_enum AS ENUM ('super_admin');
CREATE TYPE invitation_status_enum AS ENUM ('pending', 'accepted', 'revoked');
CREATE TYPE invitation_delivery_status_enum AS ENUM ('queued', 'sent', 'failed');
CREATE TYPE leave_request_status_enum AS ENUM ('pending', 'approved', 'denied');
CREATE TYPE leave_request_event_type_enum AS ENUM ('created', 'approved', 'denied', 'deleted');
CREATE TYPE entry_version_action_enum AS ENUM ('created', 'updated', 'approved', 'unapproved', 'approval_reset', 'deleted');
CREATE TYPE venue_membership_role_event_type_enum AS ENUM ('assigned', 'changed');

CREATE TABLE venues (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    status venue_status_enum DEFAULT 'active' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    user_role TEXT DEFAULT 'staff' NOT NULL,
    platform_role platform_role_enum DEFAULT NULL,
    is_profile_completed BOOLEAN DEFAULT FALSE NOT NULL,
    email_verified_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((user_role = 'staff') OR (user_role = 'manager') OR (user_role = 'admin'))
);
CREATE TABLE email_verification_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    token TEXT NOT NULL,
    sent_to_email TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    consumed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(token),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE TABLE passkeys (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    credential_id BYTEA NOT NULL,
    public_key BYTEA NOT NULL,
    sign_count BIGINT DEFAULT 0 NOT NULL,
    name TEXT DEFAULT 'Passkey' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_used_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(credential_id),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE TABLE venue_memberships (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    user_id UUID NOT NULL,
    venue_role venue_role_enum DEFAULT 'worker' NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, user_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
);
CREATE TABLE venue_invitations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    invited_by_user_id UUID,
    accepted_by_user_id UUID,
    email TEXT NOT NULL,
    invite_role venue_role_enum DEFAULT 'worker' NOT NULL,
    status invitation_status_enum DEFAULT 'pending' NOT NULL,
    delivery_status invitation_delivery_status_enum DEFAULT 'queued' NOT NULL,
    delivery_error TEXT DEFAULT NULL,
    delivered_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    accepted_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (invited_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE TABLE venue_onboarding_invitations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    invited_by_user_id UUID,
    accepted_by_user_id UUID,
    email TEXT NOT NULL,
    status invitation_status_enum DEFAULT 'pending' NOT NULL,
    delivery_status invitation_delivery_status_enum DEFAULT 'queued' NOT NULL,
    delivery_error TEXT DEFAULT NULL,
    delivered_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    accepted_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (invited_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE TABLE staff (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    user_id UUID,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    preferred_name TEXT DEFAULT NULL,
    phone TEXT NOT NULL,
    emergency_contact_name TEXT NOT NULL,
    emergency_contact_phone TEXT NOT NULL,
    ideal_shifts_per_week INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE TABLE pay_levels (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    base_rate NUMERIC(10,2) DEFAULT 0 NOT NULL,
    evening_penalty NUMERIC(10,2) DEFAULT 0 NOT NULL,
    after_12_penalty NUMERIC(10,2) DEFAULT 0 NOT NULL,
    weekday_multiplier NUMERIC(10,3) DEFAULT 1.000 NOT NULL,
    saturday_multiplier NUMERIC(10,3) DEFAULT 1.000 NOT NULL,
    sunday_multiplier NUMERIC(10,3) DEFAULT 1.000 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE
);
CREATE TABLE shift_types (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    default_pay_level_id UUID NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (default_pay_level_id) REFERENCES pay_levels (id) ON DELETE RESTRICT
);
CREATE TABLE report_definitions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    slug TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    engine TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, slug),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    CHECK ((engine = 'staff_pay_csv') OR (engine = 'hourly_breakdown_zip'))
);
CREATE TABLE report_definition_shift_type_filters (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    report_definition_id UUID NOT NULL,
    shift_type_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(report_definition_id, shift_type_id),
    FOREIGN KEY (report_definition_id) REFERENCES report_definitions (id) ON DELETE CASCADE,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE CASCADE
);
CREATE TABLE roster_groups (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    is_default BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, name),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE
);
CREATE TABLE staff_roster_groups (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    staff_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(staff_id, roster_group_id),
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE CASCADE
);
CREATE TABLE slot_names (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE CASCADE
);
CREATE TABLE day_names (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    weekday_index INT NOT NULL,
    name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, weekday_index),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE
);
CREATE TABLE pay_level_day_rules (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    shift_type_id UUID NOT NULL,
    day_name_id UUID NOT NULL,
    pay_level_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(shift_type_id, day_name_id),
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE CASCADE,
    FOREIGN KEY (day_name_id) REFERENCES day_names (id) ON DELETE RESTRICT,
    FOREIGN KEY (pay_level_id) REFERENCES pay_levels (id) ON DELETE CASCADE
);
CREATE TABLE venue_config (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    timezone TEXT NOT NULL,
    roster_week_starts_on INT NOT NULL,
    week_offset_epoch DATE NOT NULL,
    late_to_early_min_start_gap_minutes INT DEFAULT 0 NOT NULL,
    staff_timesheet_edit_window_days INT DEFAULT 7 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE
);
CREATE TABLE pay_config_snapshots (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    version_number INT NOT NULL,
    version_label TEXT NOT NULL,
    created_by_user_id UUID NOT NULL,
    snapshot JSONB DEFAULT '{}'::JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, version_number),
    UNIQUE(venue_id, version_label),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE fwc_mapd_sync_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    status TEXT NOT NULL,
    requested_award_fixed_ids INT[] DEFAULT '{}' NOT NULL,
    synced_award_fixed_ids INT[] DEFAULT '{}' NOT NULL,
    fetched_award_count INT DEFAULT 0 NOT NULL,
    fetched_classification_count INT DEFAULT 0 NOT NULL,
    fetched_pay_rate_count INT DEFAULT 0 NOT NULL,
    error_message TEXT DEFAULT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((status = 'running') OR (status = 'succeeded') OR (status = 'failed'))
);
CREATE TABLE fwc_mapd_awards (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    award_id INT NOT NULL,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    award_operative_from DATE DEFAULT NULL,
    award_operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
CREATE TABLE fwc_mapd_classifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT NOT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_fixed_id INT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    clauses JSONB DEFAULT '[]'::JSONB NOT NULL,
    next_down_classification_fixed_id INT DEFAULT NULL,
    next_up_classification_fixed_id INT DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
CREATE TABLE fwc_mapd_pay_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT DEFAULT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    employee_rate_type_code TEXT DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    base_rate NUMERIC(12,4) DEFAULT NULL,
    base_rate_type TEXT DEFAULT NULL,
    calculated_pay_rate_id TEXT DEFAULT NULL,
    calculated_rate NUMERIC(12,4) DEFAULT NULL,
    calculated_rate_type TEXT DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    version_number INT DEFAULT NULL,
    last_modified_datetime TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);
CREATE TABLE app_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL,
    last_error TEXT DEFAULT NULL,
    attempts_count INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by UUID DEFAULT NULL,
    run_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    job_kind TEXT NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    payload_schema_version INT DEFAULT 1 NOT NULL,
    requested_by_user_id UUID DEFAULT NULL,
    venue_id UUID DEFAULT NULL,
    related_table TEXT DEFAULT NULL,
    related_id UUID DEFAULT NULL,
    dedupe_key TEXT DEFAULT NULL,
    progress JSONB DEFAULT '{}'::JSONB NOT NULL,
    result JSONB DEFAULT '{}'::JSONB NOT NULL,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE SET NULL
);
CREATE TABLE roster_weeks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    week_offset INT NOT NULL,
    is_live BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_group_id, week_offset),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE CASCADE
);
CREATE TABLE roster_days (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_week_id UUID NOT NULL,
    day_offset INT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_week_id, day_offset),
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE CASCADE
);
CREATE TABLE roster_slots (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_day_id UUID NOT NULL,
    staff_id UUID,
    slot_name_id UUID NOT NULL,
    slot_sort_order INT DEFAULT 0 NOT NULL,
    row_index INT NOT NULL,
    start_time TIME,
    duration_minutes INT,
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK (note IS NULL OR char_length(note) <= 2),
    FOREIGN KEY (roster_day_id) REFERENCES roster_days (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE SET NULL,
    FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE RESTRICT
);
CREATE TABLE staff_availability (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    weekday_index INT,
    specific_date DATE,
    is_available BOOLEAN NOT NULL,
    note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE
);
CREATE TABLE staff_shift_preferences (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    slot_name_id UUID NOT NULL,
    weekday_index INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(staff_id, roster_group_id, slot_name_id, weekday_index),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE CASCADE,
    FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE CASCADE
);
CREATE TABLE leave_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status leave_request_status_enum DEFAULT 'pending' NOT NULL,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE
);
CREATE TABLE leave_request_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    leave_request_id UUID NOT NULL,
    actor_user_id UUID NOT NULL,
    event_type leave_request_event_type_enum NOT NULL,
    previous_status leave_request_status_enum,
    new_status leave_request_status_enum,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE audit_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    actor_user_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    target_table TEXT NOT NULL,
    target_id UUID NOT NULL,
    source_channel TEXT DEFAULT 'web' NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE export_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    requested_by_user_id UUID NOT NULL,
    export_type TEXT NOT NULL,
    status TEXT DEFAULT 'pending' NOT NULL,
    schema_version INT DEFAULT 1 NOT NULL,
    pay_config_snapshot_version TEXT,
    range_start DATE,
    range_end DATE,
    scope JSONB DEFAULT '{}'::JSONB NOT NULL,
    delivery_method TEXT DEFAULT 'browser_download' NOT NULL,
    destination_metadata JSONB DEFAULT '{}'::JSONB NOT NULL,
    generated_file_id UUID DEFAULT uuid_generate_v4() NOT NULL,
    file_name TEXT,
    content_type TEXT,
    file_encoding TEXT DEFAULT 'utf8' NOT NULL,
    file_contents TEXT,
    download_token UUID DEFAULT uuid_generate_v4() NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    downloaded_at TIMESTAMP WITH TIME ZONE,
    downloaded_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (downloaded_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE TABLE timesheet_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    shift_type_id UUID NOT NULL,
    worked_on DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    had_break BOOLEAN DEFAULT FALSE NOT NULL,
    break_start_time TIME,
    break_end_time TIME,
    break_minutes INT DEFAULT 0 NOT NULL,
    pay_config_snapshot_id UUID,
    is_approved BOOLEAN DEFAULT FALSE NOT NULL,
    approved_at TIMESTAMP WITH TIME ZONE,
    approved_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE CASCADE,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT,
    FOREIGN KEY (pay_config_snapshot_id) REFERENCES pay_config_snapshots (id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_by_user_id) REFERENCES users (id) ON DELETE SET NULL
);
CREATE TABLE timesheet_entry_versions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    timesheet_entry_id UUID NOT NULL,
    actor_user_id UUID NOT NULL,
    version_action entry_version_action_enum NOT NULL,
    snapshot JSONB DEFAULT '{}'::JSONB NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE venue_membership_role_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    venue_membership_id UUID NOT NULL,
    actor_user_id UUID NOT NULL,
    event_type venue_membership_role_event_type_enum NOT NULL,
    previous_role venue_role_enum,
    new_role venue_role_enum NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- Composite indexes for common venue-scoped access paths
CREATE INDEX idx_venue_memberships_venue_user ON venue_memberships (venue_id, user_id);
CREATE INDEX idx_venue_memberships_user_active ON venue_memberships (user_id, is_active);
CREATE UNIQUE INDEX idx_users_email_lower ON users (LOWER(email));
CREATE INDEX idx_passkeys_user_id ON passkeys (user_id);
CREATE INDEX idx_venue_invitations_venue_status ON venue_invitations (venue_id, status);
CREATE INDEX idx_venue_invitations_email_status ON venue_invitations (email, status);
CREATE INDEX idx_venue_onboarding_invitations_email_status ON venue_onboarding_invitations (email, status);
CREATE INDEX idx_staff_venue ON staff (venue_id);
CREATE UNIQUE INDEX idx_staff_linked_user_per_venue ON staff (venue_id, user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_report_definitions_venue_sort ON report_definitions (venue_id, sort_order ASC, created_at ASC);
CREATE INDEX idx_report_definition_shift_type_filters_definition ON report_definition_shift_type_filters (report_definition_id);
CREATE INDEX idx_staff_roster_groups_group_staff ON staff_roster_groups (roster_group_id, staff_id);
CREATE INDEX idx_slot_names_group_sort ON slot_names (roster_group_id, sort_order ASC, created_at ASC);
CREATE UNIQUE INDEX idx_slot_names_active_name ON slot_names (roster_group_id, name) WHERE is_active = TRUE;
CREATE INDEX idx_roster_weeks_venue_offset ON roster_weeks (venue_id, week_offset);
CREATE INDEX idx_roster_slots_day ON roster_slots (roster_day_id);
CREATE INDEX idx_roster_slots_staff ON roster_slots (staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX idx_pay_config_snapshots_venue_version ON pay_config_snapshots (venue_id, version_number DESC);
CREATE INDEX idx_fwc_mapd_sync_runs_started_at ON fwc_mapd_sync_runs (started_at DESC);
CREATE INDEX idx_fwc_mapd_awards_fixed_id ON fwc_mapd_awards (award_fixed_id, award_operative_to);
CREATE INDEX idx_fwc_mapd_awards_code ON fwc_mapd_awards (code);
CREATE INDEX idx_fwc_mapd_classifications_award_current ON fwc_mapd_classifications (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_fwc_mapd_pay_rates_award_current ON fwc_mapd_pay_rates (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_app_jobs_pending ON app_jobs (status, run_at, created_at);
CREATE INDEX idx_app_jobs_kind_created_at ON app_jobs (job_kind, created_at DESC);
CREATE INDEX idx_app_jobs_venue_created_at ON app_jobs (venue_id, created_at DESC);
CREATE UNIQUE INDEX idx_app_jobs_active_dedupe ON app_jobs (dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('job_status_not_started', 'job_status_running', 'job_status_retry');
CREATE INDEX idx_timesheet_entries_venue_staff ON timesheet_entries (venue_id, staff_id);
CREATE INDEX idx_timesheet_entries_venue_worked_on ON timesheet_entries (venue_id, worked_on);
CREATE INDEX idx_timesheet_entries_snapshot ON timesheet_entries (pay_config_snapshot_id);
CREATE INDEX idx_timesheet_entry_versions_entry_created_at ON timesheet_entry_versions (timesheet_entry_id, created_at DESC);
CREATE INDEX idx_leave_requests_venue_staff ON leave_requests (venue_id, staff_id);
CREATE INDEX idx_leave_requests_venue_start_date ON leave_requests (venue_id, start_date);
CREATE INDEX idx_leave_request_events_request_created_at ON leave_request_events (leave_request_id, created_at DESC);
CREATE INDEX idx_staff_availability_venue ON staff_availability (venue_id);
CREATE INDEX idx_staff_shift_preferences_venue_staff ON staff_shift_preferences (venue_id, staff_id);
CREATE INDEX idx_staff_shift_preferences_staff ON staff_shift_preferences (staff_id);
CREATE INDEX idx_staff_shift_preferences_group_day ON staff_shift_preferences (roster_group_id, weekday_index);
CREATE INDEX idx_audit_events_venue_created_at ON audit_events (venue_id, created_at DESC);
CREATE INDEX idx_audit_events_target ON audit_events (target_table, target_id);
CREATE INDEX idx_export_jobs_venue_created_at ON export_jobs (venue_id, created_at DESC);
CREATE INDEX idx_venue_membership_role_events_membership_created_at ON venue_membership_role_events (venue_membership_id, created_at DESC);
CREATE UNIQUE INDEX idx_export_jobs_generated_file_id ON export_jobs (generated_file_id);
CREATE UNIQUE INDEX idx_export_jobs_download_token ON export_jobs (download_token);

CREATE OR REPLACE FUNCTION resolve_effective_pay_level(p_staff_id UUID, p_shift_type_id UUID, p_day_of_week INT)
RETURNS UUID
AS $$
    SELECT
        COALESCE(
            (
                SELECT pldr.pay_level_id
                FROM pay_level_day_rules pldr
                JOIN day_names dn ON dn.id = pldr.day_name_id
                WHERE pldr.shift_type_id = p_shift_type_id
                    AND dn.weekday_index = p_day_of_week
                LIMIT 1
            ),
            (
                SELECT st.default_pay_level_id
                FROM shift_types st
                WHERE st.id = p_shift_type_id
                LIMIT 1
            )
        );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION resolve_effective_pay_level_snapshot(p_snapshot JSONB, p_shift_type_id UUID, p_day_of_week INT)
RETURNS UUID
AS $$
    SELECT
        COALESCE(
            (
                SELECT COALESCE(
                    (
                        SELECT (rule ->> 'payLevelId')::UUID
                        FROM jsonb_array_elements(COALESCE(p_snapshot -> 'payLevelDayRules', '[]'::JSONB)) rule
                        WHERE (rule ->> 'shiftTypeId')::UUID = p_shift_type_id
                            AND COALESCE(
                                (rule ->> 'weekdayIndex')::INT,
                                (
                                    SELECT (day_name ->> 'weekdayIndex')::INT
                                    FROM jsonb_array_elements(COALESCE(p_snapshot -> 'dayNames', '[]'::JSONB)) day_name
                                    WHERE (rule ->> 'dayNameId') = (day_name ->> 'id')
                                    LIMIT 1
                                )
                            ) = p_day_of_week
                        LIMIT 1
                    ),
                    (shift_type ->> 'defaultPayLevelId')::UUID
                )
                FROM jsonb_array_elements(COALESCE(p_snapshot -> 'shiftTypes', '[]'::JSONB)) shift_type
                WHERE (shift_type ->> 'id')::UUID = p_shift_type_id
                LIMIT 1
            ),
            p_shift_type_id
        );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION calculate_timesheet_pay(p_entry_id UUID)
RETURNS JSONB
AS $$
    WITH entry_data AS (
        SELECT
            te.*,
            pcs.version_label AS pay_config_snapshot_version,
            pcs.snapshot AS pay_config_snapshot
        FROM timesheet_entries te
        LEFT JOIN pay_config_snapshots pcs ON pcs.id = te.pay_config_snapshot_id
        WHERE te.id = p_entry_id
        LIMIT 1
    ),
    resolved AS (
        SELECT
            e.id,
            e.staff_id,
            e.shift_type_id,
            e.worked_on,
            e.start_time,
            e.end_time,
            e.break_minutes,
            e.pay_config_snapshot_id,
            e.pay_config_snapshot_version,
            e.pay_config_snapshot,
            (EXTRACT(EPOCH FROM e.start_time) / 60)::INT AS start_minute_of_day,
            (
                CASE
                    WHEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                        THEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT + 1440
                    ELSE (EXTRACT(EPOCH FROM e.end_time) / 60)::INT
                END
            ) AS end_minute_of_day,
            GREATEST(
                (
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.end_time) / 60)::INT
                    END
                ) - (EXTRACT(EPOCH FROM e.start_time) / 60)::INT - e.break_minutes,
                0
            ) AS paid_minutes,
            CASE
                WHEN e.pay_config_snapshot_id IS NOT NULL THEN
                    resolve_effective_pay_level_snapshot(
                        e.pay_config_snapshot,
                        e.shift_type_id,
                        EXTRACT(DOW FROM e.worked_on)::INT
                    )
                ELSE
                    resolve_effective_pay_level(
                        e.staff_id,
                        e.shift_type_id,
                        EXTRACT(DOW FROM e.worked_on)::INT
                    )
            END AS pay_level_id
        FROM entry_data e
    ),
    labelled AS (
        SELECT
            r.*,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT shift_type ->> 'name'
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'shiftTypes', '[]'::JSONB)) shift_type
                        WHERE (shift_type ->> 'id')::UUID = r.shift_type_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT st.name
                        FROM shift_types st
                        WHERE st.id = r.shift_type_id
                        LIMIT 1
                    )
            END AS shift_type_name,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT pay_level ->> 'name'
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.name
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS pay_level_name,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'baseRate')::NUMERIC(10,2), 0)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.base_rate
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS base_rate,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'eveningPenalty')::NUMERIC(10,2), 0)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.evening_penalty
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS evening_penalty,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'after12Penalty')::NUMERIC(10,2), 0)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.after_12_penalty
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS after_12_penalty,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'weekdayMultiplier')::NUMERIC(10,3), 1)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.weekday_multiplier
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS weekday_multiplier,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'saturdayMultiplier')::NUMERIC(10,3), 1)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.saturday_multiplier
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS saturday_multiplier,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT COALESCE((pay_level ->> 'sundayMultiplier')::NUMERIC(10,3), 1)
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'payLevels', '[]'::JSONB)) pay_level
                        WHERE (pay_level ->> 'id')::UUID = r.pay_level_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT pl.sunday_multiplier
                        FROM pay_levels pl
                        WHERE pl.id = r.pay_level_id
                        LIMIT 1
                    )
            END AS sunday_multiplier
        FROM resolved r
    ),
    paid_window AS (
        SELECT
            r.*,
            LEAST(r.start_minute_of_day + r.paid_minutes, 1860) AS paid_end_minute_of_day
        FROM labelled r
    ),
    segment_windows AS (
        SELECT *
        FROM (
            VALUES
                ('after_midnight'::TEXT, 0, 420, 1),
                ('ordinary'::TEXT, 420, 1140, 2),
                ('evening'::TEXT, 1140, 1440, 3)
        ) AS windows(segment_name, window_start_minute, window_end_minute, sort_index)
    ),
    segment_rows AS (
        SELECT
            pw.id,
            pw.staff_id,
            pw.worked_on,
            pw.break_minutes,
            pw.paid_minutes,
            pw.shift_type_id,
            pw.shift_type_name,
            pw.pay_level_id,
            pw.pay_level_name,
            pw.pay_config_snapshot_id,
            pw.pay_config_snapshot_version,
            pw.pay_config_snapshot,
            sw.segment_name,
            CASE
                WHEN EXTRACT(DOW FROM pw.worked_on)::INT = 6 THEN pw.saturday_multiplier
                WHEN EXTRACT(DOW FROM pw.worked_on)::INT = 0 THEN pw.sunday_multiplier
                ELSE pw.weekday_multiplier
            END AS day_rule_multiplier,
            CASE
                WHEN EXTRACT(DOW FROM pw.worked_on)::INT IN (0, 6) THEN
                    CASE
                        WHEN EXTRACT(DOW FROM pw.worked_on)::INT = 6 THEN pw.saturday_multiplier
                        ELSE pw.sunday_multiplier
                    END
                ELSE 1.0::NUMERIC(10,3)
            END AS weekend_multiplier,
            GREATEST(
                LEAST(pw.paid_end_minute_of_day, sw.window_end_minute)
                - GREATEST(pw.start_minute_of_day, sw.window_start_minute),
                0
            )::INT AS segment_minutes,
            pw.base_rate,
            CASE
                WHEN EXTRACT(DOW FROM pw.worked_on)::INT IN (0, 6) THEN
                    pw.base_rate
                        * CASE
                            WHEN EXTRACT(DOW FROM pw.worked_on)::INT = 6 THEN pw.saturday_multiplier
                            ELSE pw.sunday_multiplier
                          END
                WHEN sw.segment_name = 'evening' THEN (pw.base_rate * pw.weekday_multiplier) + pw.evening_penalty
                WHEN sw.segment_name = 'after_midnight' THEN (pw.base_rate * pw.weekday_multiplier) + pw.after_12_penalty
                ELSE pw.base_rate * pw.weekday_multiplier
            END AS segment_hourly_rate,
            sw.sort_index
        FROM paid_window pw
        CROSS JOIN segment_windows sw
    ),
    segment_json AS (
        SELECT
            sr.id,
            COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'segment', sr.segment_name,
                        'minutes', sr.segment_minutes,
                        'shiftTypeId', sr.shift_type_id,
                        'shiftTypeName', sr.shift_type_name,
                        'payLevelId', sr.pay_level_id,
                        'payLevelName', sr.pay_level_name,
                        'dayRuleMultiplier', sr.day_rule_multiplier,
                        'weekendMultiplier', sr.weekend_multiplier,
                        'multiplier', sr.day_rule_multiplier,
                        'baseRate', sr.base_rate,
                        'amount', ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2)
                    )
                    ORDER BY sr.sort_index ASC
                ) FILTER (WHERE sr.segment_minutes > 0),
                jsonb_build_array()
            ) AS segments
        FROM segment_rows sr
        GROUP BY sr.id
    ),
    segment_totals AS (
        SELECT
            sr.id,
            COALESCE(
                SUM(ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2))
                    FILTER (WHERE sr.segment_minutes > 0),
                0::NUMERIC(12,2)
            ) AS total_amount
        FROM segment_rows sr
        GROUP BY sr.id
    ),
    payload AS (
        SELECT jsonb_build_object(
            'entryId', pw.id,
            'staffId', pw.staff_id,
            'workedOn', pw.worked_on,
            'shiftTypeId', pw.shift_type_id,
            'shiftTypeName', pw.shift_type_name,
            'payLevelId', pw.pay_level_id,
            'payLevelName', pw.pay_level_name,
            'payConfigSnapshotId', pw.pay_config_snapshot_id,
            'payConfigSnapshotVersion', pw.pay_config_snapshot_version,
            'breakMinutes', pw.break_minutes,
            'paidMinutes', pw.paid_minutes,
            'segments', sj.segments,
            'totals', jsonb_build_object(
                'paidMinutes', pw.paid_minutes,
                'totalAmount', st.total_amount
            )
        ) AS pay_json
        FROM paid_window pw
        LEFT JOIN segment_json sj ON sj.id = pw.id
        LEFT JOIN segment_totals st ON st.id = pw.id
    )
    SELECT COALESCE(
        (SELECT pay_json FROM payload),
        jsonb_build_object(
            'entryId', p_entry_id,
            'error', 'timesheet_entry_not_found',
            'segments', jsonb_build_array(),
            'totals', jsonb_build_object('paidMinutes', 0, 'totalAmount', 0)
        )
    );
$$ LANGUAGE SQL;

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
        AND te.worked_on <= p_to_date;
$$ LANGUAGE SQL;
