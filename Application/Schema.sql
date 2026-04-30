-- Your database schema. Use the Schema Designer at http://localhost:8001/ to add some tables.
--
-- Schema navigation map:
-- - schema-nav: enum-types - shared status/role/action enums. Some finite
--   domains intentionally remain TEXT + explicit OR checks for IHP parser
--   compatibility; hardening belongs in ir-caf4.
-- - schema-nav: identity-and-access - venues, users, email verification,
--   passkeys, memberships, invitations, and onboarding.
-- - schema-nav: staff-profiles - venue staff profile and employment defaults.
-- - schema-nav: venue-config - shift types and venue-level defaults.
-- - schema-nav: reporting-config - report definitions and shift-type filters.
-- - schema-nav: roster-group-config - roster groups, staff group assignments,
--   and slot/day names.
-- - schema-nav: pay-reference - pay snapshots, FWC MAPD imports, award levels,
--   rates, allowances, and public holidays.
-- - schema-nav: async-jobs - durable app jobs and progress/result payloads.
-- - schema-nav: roster-planning - roster weeks, days, slots, and staff shift
--   preferences.
-- - schema-nav: leave-timesheets-audit - leave requests, audit trail, and
--   export jobs.
-- - schema-nav: xero - OAuth connections, reference sync rows, mappings, and
--   pay item setup.
-- - schema-nav: timesheets - timesheet entries and version history.
-- - schema-nav: xero-submissions - Xero submission runs and submitted entries.
-- - schema-nav: indexes - composite, partial, uniqueness, and lookup indexes.
-- - schema-nav: retention-triggers - hard-delete guards for retained tables.
-- - schema-nav: tenant-integrity-triggers - cross-table venue consistency.
-- - schema-nav: pay-sql-functions - SQL pay calculation helpers.

-- schema-nav: enum-types
CREATE TYPE venue_status_enum AS ENUM ('active', 'inactive');
CREATE TYPE venue_role_enum AS ENUM ('worker', 'manager', 'venue_admin', 'venue_owner');
CREATE TYPE platform_role_enum AS ENUM ('super_admin');
CREATE TYPE invitation_status_enum AS ENUM ('pending', 'accepted', 'revoked');
CREATE TYPE invitation_delivery_status_enum AS ENUM ('queued', 'sent', 'failed');
CREATE TYPE leave_request_status_enum AS ENUM ('pending', 'approved', 'denied');
CREATE TYPE leave_request_event_type_enum AS ENUM ('created', 'approved', 'denied', 'deleted');
CREATE TYPE entry_version_action_enum AS ENUM ('created', 'updated', 'approved', 'unapproved', 'approval_reset', 'deleted');
CREATE TYPE venue_membership_role_event_type_enum AS ENUM ('assigned', 'changed');
CREATE TYPE staff_employment_basis_enum AS ENUM ('permanent', 'casual');
CREATE TYPE award_penalty_kind_enum AS ENUM ('evening_after_7pm', 'late_night_after_midnight', 'saturday_penalty', 'sunday_penalty', 'public_holiday_penalty', 'delayed_meal_break_weekday', 'delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday');

-- schema-nav: identity-and-access
CREATE TABLE venues (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    status venue_status_enum DEFAULT 'active' NOT NULL,
    closed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    closed_by_user_id UUID DEFAULT NULL,
    retention_until TIMESTAMP WITH TIME ZONE DEFAULT NULL,
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
    deactivated_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deactivated_by_user_id UUID DEFAULT NULL,
    deactivation_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((user_role = 'staff') OR (user_role = 'manager') OR (user_role = 'admin'))
);
ALTER TABLE venues
    ADD CONSTRAINT venues_closed_by_user_id_fk
    FOREIGN KEY (closed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE users
    ADD CONSTRAINT users_deactivated_by_user_id_fk
    FOREIGN KEY (deactivated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT;
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
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
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

-- schema-nav: staff-profiles
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
    employment_basis staff_employment_basis_enum DEFAULT 'casual' NOT NULL,
    default_award_level_id UUID DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((ideal_shifts_per_week >= 0) AND (ideal_shifts_per_week <= 7))
);

-- schema-nav: venue-config
CREATE TABLE shift_types (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    override_award_level_id UUID DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: reporting-config
CREATE TABLE report_definitions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    slug TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    engine TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((engine = 'staff_pay_csv') OR (engine = 'hourly_breakdown_zip') OR (engine = 'payroll_earnings_csv'))
);
CREATE TABLE report_definition_shift_type_filters (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    report_definition_id UUID NOT NULL,
    shift_type_id UUID NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (report_definition_id) REFERENCES report_definitions (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: roster-group-config
CREATE TABLE roster_groups (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    is_default BOOLEAN DEFAULT FALSE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE staff_roster_groups (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    staff_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE slot_names (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE day_names (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    weekday_index INT NOT NULL,
    name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id, weekday_index),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((weekday_index >= 0) AND (weekday_index <= 6))
);
CREATE TABLE venue_config (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    timezone TEXT NOT NULL,
    roster_week_starts_on INT NOT NULL,
    week_offset_epoch DATE NOT NULL,
    late_to_early_min_start_gap_minutes INT DEFAULT 0 NOT NULL,
    staff_timesheet_edit_window_days INT DEFAULT 7 NOT NULL,
    public_holiday_jurisdiction TEXT DEFAULT 'VIC' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((roster_week_starts_on >= 0) AND (roster_week_starts_on <= 6)),
    CHECK (late_to_early_min_start_gap_minutes >= 0),
    CHECK (staff_timesheet_edit_window_days >= 0)
);

-- schema-nav: pay-reference
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
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
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
    fetched_penalty_rate_count INT DEFAULT 0 NOT NULL,
    fetched_wage_allowance_count INT DEFAULT 0 NOT NULL,
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
CREATE TABLE fwc_mapd_penalty_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT DEFAULT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    employee_rate_type_code TEXT DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    penalty_fixed_id INT DEFAULT NULL,
    penalty_description TEXT DEFAULT NULL,
    penalty_text TEXT DEFAULT NULL,
    rate NUMERIC(12,4) DEFAULT NULL,
    penalty_rate_unit TEXT DEFAULT NULL,
    penalty_calculated_value NUMERIC(12,4) DEFAULT NULL,
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
CREATE TABLE fwc_mapd_wage_allowances (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    wage_allowance_fixed_id INT DEFAULT NULL,
    clause_fixed_id INT DEFAULT NULL,
    clauses TEXT DEFAULT NULL,
    allowance TEXT DEFAULT NULL,
    allowance_type TEXT DEFAULT NULL,
    is_all_purpose BOOLEAN DEFAULT NULL,
    rate NUMERIC(12,4) DEFAULT NULL,
    base_rate NUMERIC(12,4) DEFAULT NULL,
    base_pay_rate_id TEXT DEFAULT NULL,
    rate_unit TEXT DEFAULT NULL,
    allowance_amount NUMERIC(12,4) DEFAULT NULL,
    payment_frequency TEXT DEFAULT NULL,
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
CREATE TABLE award_levels (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    classification_fixed_id INT NOT NULL,
    classification TEXT NOT NULL,
    classification_level TEXT DEFAULT NULL,
    parent_classification_name TEXT DEFAULT NULL,
    clause_description TEXT DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    raw_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_fixed_id, classification_fixed_id)
);
ALTER TABLE staff
    ADD CONSTRAINT staff_default_award_level_id_fk
    FOREIGN KEY (default_award_level_id) REFERENCES award_levels (id) ON DELETE SET NULL;
ALTER TABLE shift_types
    ADD CONSTRAINT shift_types_override_award_level_id_fk
    FOREIGN KEY (override_award_level_id) REFERENCES award_levels (id) ON DELETE SET NULL;
CREATE TABLE award_level_base_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_level_id UUID NOT NULL,
    employment_basis staff_employment_basis_enum NOT NULL,
    fwc_mapd_pay_rate_id UUID NOT NULL,
    hourly_rate NUMERIC(12,4) NOT NULL,
    rate_label TEXT NOT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_level_id, employment_basis, operative_from, operative_to),
    FOREIGN KEY (award_level_id) REFERENCES award_levels (id) ON DELETE CASCADE,
    FOREIGN KEY (fwc_mapd_pay_rate_id) REFERENCES fwc_mapd_pay_rates (id) ON DELETE CASCADE
);
CREATE TABLE award_level_penalty_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_level_id UUID NOT NULL,
    employment_basis staff_employment_basis_enum NOT NULL,
    penalty_kind award_penalty_kind_enum NOT NULL,
    fwc_mapd_penalty_rate_id UUID NOT NULL,
    hourly_rate NUMERIC(12,4) NOT NULL,
    starts_at_time TIME DEFAULT NULL,
    ends_at_time TIME DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_level_id, employment_basis, penalty_kind, operative_from, operative_to),
    FOREIGN KEY (award_level_id) REFERENCES award_levels (id) ON DELETE CASCADE,
    FOREIGN KEY (fwc_mapd_penalty_rate_id) REFERENCES fwc_mapd_penalty_rates (id) ON DELETE CASCADE
);
CREATE TABLE award_time_penalty_allowances (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    award_fixed_id INT NOT NULL,
    penalty_kind award_penalty_kind_enum NOT NULL,
    fwc_mapd_wage_allowance_id UUID NOT NULL,
    rate_percent NUMERIC(12,4) DEFAULT NULL,
    hourly_amount NUMERIC(12,4) NOT NULL,
    starts_at_time TIME DEFAULT NULL,
    ends_at_time TIME DEFAULT NULL,
    operative_from DATE DEFAULT NULL,
    operative_to DATE DEFAULT NULL,
    published_year INT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(award_fixed_id, penalty_kind, operative_from, operative_to),
    FOREIGN KEY (fwc_mapd_wage_allowance_id) REFERENCES fwc_mapd_wage_allowances (id) ON DELETE CASCADE
);
CREATE TABLE public_holidays (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    jurisdiction TEXT NOT NULL,
    holiday_date DATE NOT NULL,
    name TEXT NOT NULL,
    region TEXT DEFAULT NULL,
    is_regional BOOLEAN DEFAULT FALSE NOT NULL,
    source TEXT DEFAULT NULL,
    source_id TEXT DEFAULT NULL,
    source_url TEXT DEFAULT NULL,
    description TEXT DEFAULT NULL,
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(jurisdiction, holiday_date, name, region)
);

-- schema-nav: async-jobs
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

-- schema-nav: roster-planning
CREATE TABLE roster_weeks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    week_offset INT NOT NULL,
    is_live BOOLEAN DEFAULT FALSE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_group_id, week_offset),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE roster_days (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_week_id UUID NOT NULL,
    day_offset INT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_week_id, day_offset),
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    CHECK ((day_offset >= 0) AND (day_offset <= 6))
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
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK (note IS NULL OR char_length(note) <= 2),
    CHECK (row_index >= 0),
    CHECK (slot_sort_order >= 0),
    CHECK (duration_minutes IS NULL OR duration_minutes >= 0),
    FOREIGN KEY (roster_day_id) REFERENCES roster_days (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE SET NULL,
    FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE staff_shift_preferences (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    slot_name_id UUID NOT NULL,
    weekday_index INT NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (slot_name_id) REFERENCES slot_names (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((weekday_index >= 0) AND (weekday_index <= 6))
);

-- schema-nav: leave-timesheets-audit
CREATE TABLE leave_requests (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status leave_request_status_enum DEFAULT 'pending' NOT NULL,
    notes TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (end_date > start_date)
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
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (leave_request_id) REFERENCES leave_requests (id) ON DELETE RESTRICT,
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
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
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
    retention_until TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    purged_file_contents_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    purged_by_user_id UUID DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (downloaded_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (purged_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: xero
CREATE TABLE xero_connections (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    tenant_id TEXT NOT NULL,
    tenant_name TEXT,
    xero_connection_remote_id TEXT,
    connection_status TEXT DEFAULT 'active' NOT NULL,
    scopes TEXT NOT NULL,
    encrypted_refresh_token TEXT NOT NULL,
    encrypted_access_token TEXT,
    access_token_expires_at TIMESTAMP WITH TIME ZONE,
    last_refreshed_at TIMESTAMP WITH TIME ZONE,
    last_sync_at TIMESTAMP WITH TIME ZONE,
    last_error TEXT,
    connected_by_user_id UUID,
    connected_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    disconnected_by_user_id UUID,
    disconnected_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (connected_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (disconnected_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((connection_status = 'active') OR (connection_status = 'disconnected') OR (connection_status = 'reauthorization_required') OR (connection_status = 'error'))
);
CREATE TABLE xero_oauth_states (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    user_id UUID NOT NULL,
    state_token TEXT NOT NULL,
    requested_scopes TEXT NOT NULL,
    redirect_uri TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    consumed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE RESTRICT,
    UNIQUE(state_token)
);
CREATE TABLE xero_sync_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    sync_status TEXT NOT NULL,
    sync_kind TEXT DEFAULT 'payroll_reference_data' NOT NULL,
    employees_count INT DEFAULT 0 NOT NULL,
    earnings_rates_count INT DEFAULT 0 NOT NULL,
    payroll_calendars_count INT DEFAULT 0 NOT NULL,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK ((sync_status = 'running') OR (sync_status = 'succeeded') OR (sync_status = 'failed'))
);
CREATE TABLE xero_employees (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_employee_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    email TEXT,
    status TEXT,
    payroll_calendar_id TEXT,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);
CREATE TABLE xero_earnings_rates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_earnings_rate_id TEXT NOT NULL,
    name TEXT NOT NULL,
    earnings_type TEXT,
    rate_type TEXT,
    account_code TEXT,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);
CREATE TABLE xero_payroll_calendars (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_payroll_calendar_id TEXT NOT NULL,
    name TEXT NOT NULL,
    calendar_type TEXT,
    start_date DATE,
    payment_date DATE,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);
CREATE TABLE xero_staff_mappings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_employee_id TEXT,
    xero_employee_name TEXT,
    xero_employee_email TEXT,
    mapping_status TEXT DEFAULT 'not_applicable' NOT NULL,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((mapping_status = 'verified') OR (mapping_status = 'not_applicable') OR (mapping_status = 'stale'))
);
CREATE TABLE xero_earnings_rate_mappings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    local_bucket_key TEXT NOT NULL,
    local_bucket_label TEXT NOT NULL,
    xero_earnings_rate_id TEXT,
    xero_earnings_rate_name TEXT,
    mapping_status TEXT DEFAULT 'unmapped' NOT NULL,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((mapping_status = 'unmapped') OR (mapping_status = 'verified') OR (mapping_status = 'stale'))
);
CREATE TABLE xero_payroll_calendar_selections (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_payroll_calendar_id TEXT,
    xero_payroll_calendar_name TEXT,
    calendar_status TEXT DEFAULT 'none' NOT NULL,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE xero_pay_item_account_code_selections (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    account_code TEXT,
    selection_status TEXT DEFAULT 'none' NOT NULL,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE xero_pay_item_requirement_records (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    requirement_key TEXT NOT NULL,
    display_name TEXT NOT NULL,
    penalty_kind TEXT,
    earnings_type TEXT DEFAULT 'ORDINARYTIMEEARNINGS' NOT NULL,
    rate_type TEXT NOT NULL,
    multiplier NUMERIC(12,4),
    rate_per_unit NUMERIC(12,4),
    source_description TEXT NOT NULL,
    requirement_status TEXT DEFAULT 'proposed' NOT NULL,
    xero_earnings_rate_id TEXT,
    xero_earnings_rate_name TEXT,
    xero_earnings_rate_rate_type TEXT,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (requirement_status = 'proposed' OR requirement_status = 'matched' OR requirement_status = 'created' OR requirement_status = 'ignored' OR requirement_status = 'stale' OR requirement_status = 'rate_changed')
);

-- schema-nav: timesheets
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
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT,
    FOREIGN KEY (pay_config_snapshot_id) REFERENCES pay_config_snapshots (id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (break_minutes >= 0),
    CHECK (((had_break = FALSE) AND break_start_time IS NULL AND break_end_time IS NULL AND break_minutes = 0) OR ((had_break = TRUE) AND break_start_time IS NOT NULL AND break_end_time IS NOT NULL AND break_minutes > 0)),
    CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND pay_config_snapshot_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND pay_config_snapshot_id IS NOT NULL))
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
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: xero-submissions
CREATE TABLE xero_submission_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    submitted_by_user_id UUID NOT NULL,
    pay_period_start DATE NOT NULL,
    pay_period_end DATE NOT NULL,
    source_kind TEXT DEFAULT 'approved_timesheets' NOT NULL,
    status TEXT DEFAULT 'previewed' NOT NULL,
    preview_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    readiness_snapshot_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    xero_duplicate_check_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    completed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    error_summary TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (submitted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (source_kind = 'approved_timesheets'),
    CHECK (status = 'previewed' OR status = 'blocked' OR status = 'pending' OR status = 'submitted' OR status = 'partially_failed' OR status = 'failed' OR status = 'superseded'),
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_timesheet_submissions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    xero_submission_run_id UUID NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    xero_employee_id TEXT NOT NULL,
    pay_period_start DATE NOT NULL,
    pay_period_end DATE NOT NULL,
    status TEXT DEFAULT 'pending' NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    response_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    xero_timesheet_id TEXT DEFAULT NULL,
    xero_timesheet_status TEXT DEFAULT NULL,
    xero_updated_date_utc TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    attempt_count INT DEFAULT 0 NOT NULL,
    last_error TEXT DEFAULT NULL,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (xero_submission_run_id) REFERENCES xero_submission_runs (id) ON DELETE RESTRICT,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    CHECK (status = 'blocked' OR status = 'pending' OR status = 'submitted' OR status = 'failed' OR status = 'skipped' OR status = 'superseded'),
    CHECK (char_length(idempotency_key) <= 128),
    CHECK (attempt_count >= 0),
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_timesheet_submission_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    xero_timesheet_submission_id UUID NOT NULL,
    timesheet_entry_id UUID NOT NULL,
    pay_config_snapshot_id UUID NOT NULL,
    entry_updated_at_at_preview TIMESTAMP WITH TIME ZONE NOT NULL,
    entry_approved_at_at_preview TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (xero_timesheet_submission_id) REFERENCES xero_timesheet_submissions (id) ON DELETE RESTRICT,
    FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT,
    FOREIGN KEY (pay_config_snapshot_id) REFERENCES pay_config_snapshots (id) ON DELETE RESTRICT
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
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (venue_membership_id) REFERENCES venue_memberships (id) ON DELETE RESTRICT,
    FOREIGN KEY (actor_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: indexes
-- Composite indexes for common venue-scoped access paths
CREATE INDEX idx_venue_memberships_venue_user ON venue_memberships (venue_id, user_id);
CREATE INDEX idx_venue_memberships_user_active ON venue_memberships (user_id, is_active);
CREATE UNIQUE INDEX idx_venue_memberships_active_venue_user ON venue_memberships (venue_id, user_id) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_users_email_lower ON users (LOWER(email));
CREATE INDEX idx_passkeys_user_id ON passkeys (user_id);
CREATE INDEX idx_venue_invitations_venue_status ON venue_invitations (venue_id, status);
CREATE INDEX idx_venue_invitations_email_status ON venue_invitations (email, status);
CREATE INDEX idx_venue_onboarding_invitations_email_status ON venue_onboarding_invitations (email, status);
CREATE INDEX idx_staff_venue ON staff (venue_id);
CREATE INDEX idx_staff_default_award_level ON staff (default_award_level_id) WHERE default_award_level_id IS NOT NULL;
CREATE UNIQUE INDEX idx_staff_linked_user_per_venue ON staff (venue_id, user_id) WHERE user_id IS NOT NULL AND is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_report_definitions_venue_sort ON report_definitions (venue_id, sort_order ASC, created_at ASC);
CREATE UNIQUE INDEX idx_report_definitions_active_slug ON report_definitions (venue_id, slug) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_report_definition_shift_type_filters_definition ON report_definition_shift_type_filters (report_definition_id);
CREATE UNIQUE INDEX idx_report_definition_shift_type_filters_active ON report_definition_shift_type_filters (report_definition_id, shift_type_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_groups_active_name ON roster_groups (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_roster_groups_one_active_default ON roster_groups (venue_id) WHERE is_default = TRUE AND is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_staff_roster_groups_active_assignment ON staff_roster_groups (staff_id, roster_group_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_roster_groups_group_staff ON staff_roster_groups (roster_group_id, staff_id);
CREATE INDEX idx_slot_names_group_sort ON slot_names (roster_group_id, sort_order ASC, created_at ASC);
CREATE UNIQUE INDEX idx_slot_names_active_name ON slot_names (roster_group_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_shift_types_active_name ON shift_types (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_roster_weeks_venue_offset ON roster_weeks (venue_id, week_offset);
CREATE INDEX idx_roster_slots_day ON roster_slots (roster_day_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_roster_slots_staff ON roster_slots (staff_id) WHERE staff_id IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_slots_active_cell ON roster_slots (roster_day_id, row_index, slot_name_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_pay_config_snapshots_venue_version ON pay_config_snapshots (venue_id, version_number DESC);
CREATE INDEX idx_fwc_mapd_sync_runs_started_at ON fwc_mapd_sync_runs (started_at DESC);
CREATE INDEX idx_fwc_mapd_awards_fixed_id ON fwc_mapd_awards (award_fixed_id, award_operative_to);
CREATE INDEX idx_fwc_mapd_awards_code ON fwc_mapd_awards (code);
CREATE INDEX idx_fwc_mapd_classifications_award_current ON fwc_mapd_classifications (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_fwc_mapd_pay_rates_award_current ON fwc_mapd_pay_rates (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_fwc_mapd_penalty_rates_award_current ON fwc_mapd_penalty_rates (award_fixed_id, operative_to, classification_fixed_id);
CREATE INDEX idx_fwc_mapd_wage_allowances_award_current ON fwc_mapd_wage_allowances (award_fixed_id, operative_to, wage_allowance_fixed_id);
CREATE INDEX idx_award_levels_classification ON award_levels (award_fixed_id, classification_fixed_id, is_active);
CREATE INDEX idx_award_level_base_rates_lookup ON award_level_base_rates (award_level_id, employment_basis, operative_from, operative_to);
CREATE INDEX idx_award_level_penalty_rates_lookup ON award_level_penalty_rates (award_level_id, employment_basis, penalty_kind, operative_from, operative_to);
CREATE INDEX idx_award_time_penalty_allowances_lookup ON award_time_penalty_allowances (award_fixed_id, penalty_kind, operative_from, operative_to);
CREATE INDEX idx_public_holidays_lookup ON public_holidays (jurisdiction, holiday_date);
CREATE INDEX idx_app_jobs_pending ON app_jobs (status, run_at, created_at);
CREATE INDEX idx_app_jobs_kind_created_at ON app_jobs (job_kind, created_at DESC);
CREATE INDEX idx_app_jobs_venue_created_at ON app_jobs (venue_id, created_at DESC);
CREATE UNIQUE INDEX idx_app_jobs_active_dedupe ON app_jobs (dedupe_key) WHERE dedupe_key IS NOT NULL AND (status = 'job_status_not_started' OR status = 'job_status_running' OR status = 'job_status_retry');
CREATE INDEX idx_timesheet_entries_venue_staff ON timesheet_entries (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_timesheet_entries_venue_worked_on ON timesheet_entries (venue_id, worked_on) WHERE deleted_at IS NULL;
CREATE INDEX idx_timesheet_entries_snapshot ON timesheet_entries (pay_config_snapshot_id);
CREATE INDEX idx_timesheet_entry_versions_entry_created_at ON timesheet_entry_versions (timesheet_entry_id, created_at DESC);
CREATE INDEX idx_leave_requests_venue_staff ON leave_requests (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_requests_venue_start_date ON leave_requests (venue_id, start_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_requests_venue_status_staff_dates ON leave_requests (venue_id, status, staff_id, start_date, end_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_request_events_request_created_at ON leave_request_events (leave_request_id, created_at DESC);
CREATE INDEX idx_staff_shift_preferences_venue_staff ON staff_shift_preferences (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_shift_preferences_staff ON staff_shift_preferences (staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_shift_preferences_group_day ON staff_shift_preferences (roster_group_id, weekday_index) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_shift_preferences_group_staff_day_slot ON staff_shift_preferences (roster_group_id, staff_id, weekday_index, slot_name_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_staff_shift_preferences_active_unique ON staff_shift_preferences (staff_id, roster_group_id, slot_name_id, weekday_index) WHERE deleted_at IS NULL;
CREATE INDEX idx_audit_events_venue_created_at ON audit_events (venue_id, created_at DESC);
CREATE INDEX idx_audit_events_target ON audit_events (target_table, target_id);
CREATE INDEX idx_export_jobs_venue_created_at ON export_jobs (venue_id, created_at DESC);
CREATE INDEX idx_venue_membership_role_events_membership_created_at ON venue_membership_role_events (venue_membership_id, created_at DESC);
CREATE UNIQUE INDEX idx_export_jobs_generated_file_id ON export_jobs (generated_file_id);
CREATE UNIQUE INDEX idx_export_jobs_download_token ON export_jobs (download_token);
CREATE INDEX idx_xero_connections_venue_created_at ON xero_connections (venue_id, created_at DESC);
CREATE INDEX idx_xero_connections_remote_id ON xero_connections (xero_connection_remote_id);
CREATE UNIQUE INDEX idx_xero_connections_active_venue ON xero_connections (venue_id) WHERE connection_status = 'active';
CREATE INDEX idx_xero_oauth_states_token ON xero_oauth_states (state_token);
CREATE INDEX idx_xero_oauth_states_venue_user_created_at ON xero_oauth_states (venue_id, user_id, created_at DESC);
CREATE INDEX idx_xero_sync_runs_venue_started_at ON xero_sync_runs (venue_id, started_at DESC);
CREATE UNIQUE INDEX idx_xero_employees_connection_employee ON xero_employees (xero_connection_id, xero_employee_id);
CREATE INDEX idx_xero_employees_venue_name ON xero_employees (venue_id, display_name);
CREATE UNIQUE INDEX idx_xero_earnings_rates_connection_rate ON xero_earnings_rates (xero_connection_id, xero_earnings_rate_id);
CREATE INDEX idx_xero_earnings_rates_venue_name ON xero_earnings_rates (venue_id, name);
CREATE UNIQUE INDEX idx_xero_payroll_calendars_connection_calendar ON xero_payroll_calendars (xero_connection_id, xero_payroll_calendar_id);
CREATE INDEX idx_xero_payroll_calendars_venue_name ON xero_payroll_calendars (venue_id, name);
CREATE UNIQUE INDEX idx_xero_staff_mappings_staff_connection ON xero_staff_mappings (staff_id, xero_connection_id);
CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee ON xero_staff_mappings (xero_connection_id, xero_employee_id) WHERE mapping_status = 'verified' AND xero_employee_id IS NOT NULL;
CREATE INDEX idx_xero_staff_mappings_venue_status ON xero_staff_mappings (venue_id, mapping_status);
CREATE UNIQUE INDEX idx_xero_earnings_rate_mappings_bucket_connection ON xero_earnings_rate_mappings (xero_connection_id, local_bucket_key);
CREATE INDEX idx_xero_earnings_rate_mappings_venue_status ON xero_earnings_rate_mappings (venue_id, mapping_status);
CREATE UNIQUE INDEX idx_xero_payroll_calendar_selections_connection ON xero_payroll_calendar_selections (xero_connection_id);
CREATE INDEX idx_xero_payroll_calendar_selections_venue_status ON xero_payroll_calendar_selections (venue_id, calendar_status);
CREATE UNIQUE INDEX idx_xero_pay_item_account_code_selections_connection ON xero_pay_item_account_code_selections (xero_connection_id);
CREATE UNIQUE INDEX idx_xero_pay_item_requirement_records_connection_key ON xero_pay_item_requirement_records (xero_connection_id, requirement_key);
CREATE INDEX idx_xero_pay_item_requirement_records_venue_status ON xero_pay_item_requirement_records (venue_id, requirement_status);
CREATE INDEX idx_xero_submission_runs_connection_period ON xero_submission_runs (xero_connection_id, pay_period_start, pay_period_end);
CREATE INDEX idx_xero_timesheet_submissions_run ON xero_timesheet_submissions (xero_submission_run_id);
CREATE INDEX idx_xero_timesheet_submissions_staff_period ON xero_timesheet_submissions (staff_id, pay_period_start, pay_period_end);
CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period ON xero_timesheet_submissions (xero_connection_id, xero_employee_id, pay_period_start, pay_period_end) WHERE status <> 'superseded';
CREATE INDEX idx_xero_timesheet_submission_entries_submission ON xero_timesheet_submission_entries (xero_timesheet_submission_id);
CREATE UNIQUE INDEX idx_xero_timesheet_submission_entries_unique_entry ON xero_timesheet_submission_entries (xero_timesheet_submission_id, timesheet_entry_id);

-- schema-nav: retention-triggers
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

CREATE TRIGGER prevent_hard_delete_venues BEFORE DELETE ON venues FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_users BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_venue_memberships BEFORE DELETE ON venue_memberships FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff BEFORE DELETE ON staff FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff_roster_groups BEFORE DELETE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_roster_groups BEFORE DELETE ON roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_slot_names BEFORE DELETE ON slot_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_day_names BEFORE DELETE ON day_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_shift_types BEFORE DELETE ON shift_types FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_report_definitions BEFORE DELETE ON report_definitions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_report_definition_shift_type_filters BEFORE DELETE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_venue_config BEFORE DELETE ON venue_config FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_pay_config_snapshots BEFORE DELETE ON pay_config_snapshots FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_roster_weeks BEFORE DELETE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_roster_days BEFORE DELETE ON roster_days FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_roster_slots BEFORE DELETE ON roster_slots FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff_shift_preferences BEFORE DELETE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_leave_requests BEFORE DELETE ON leave_requests FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_leave_request_events BEFORE DELETE ON leave_request_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_timesheet_entries BEFORE DELETE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_timesheet_entry_versions BEFORE DELETE ON timesheet_entry_versions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_venue_membership_role_events BEFORE DELETE ON venue_membership_role_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_audit_events BEFORE DELETE ON audit_events FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_export_jobs BEFORE DELETE ON export_jobs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_connections BEFORE DELETE ON xero_connections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_sync_runs BEFORE DELETE ON xero_sync_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_employees BEFORE DELETE ON xero_employees FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_earnings_rates BEFORE DELETE ON xero_earnings_rates FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_payroll_calendars BEFORE DELETE ON xero_payroll_calendars FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_staff_mappings BEFORE DELETE ON xero_staff_mappings FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_earnings_rate_mappings BEFORE DELETE ON xero_earnings_rate_mappings FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_payroll_calendar_selections BEFORE DELETE ON xero_payroll_calendar_selections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_pay_item_account_code_selections BEFORE DELETE ON xero_pay_item_account_code_selections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_pay_item_requirement_records BEFORE DELETE ON xero_pay_item_requirement_records FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_submission_runs BEFORE DELETE ON xero_submission_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_timesheet_submissions BEFORE DELETE ON xero_timesheet_submissions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_timesheet_submission_entries BEFORE DELETE ON xero_timesheet_submission_entries FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();

-- schema-nav: tenant-integrity-triggers
CREATE OR REPLACE FUNCTION enforce_roster_week_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM roster_groups rg
        WHERE rg.id = NEW.roster_group_id
            AND rg.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'roster week venue_id must match roster_group_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_slot_name_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM roster_groups rg
        WHERE rg.id = NEW.roster_group_id
            AND rg.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'slot name venue_id must match roster_group_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_roster_group_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        JOIN roster_groups rg ON rg.id = NEW.roster_group_id
        WHERE s.id = NEW.staff_id
            AND s.venue_id = rg.venue_id
    ) THEN
        RAISE EXCEPTION 'staff roster group assignment must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_shift_preference_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        JOIN roster_groups rg ON rg.id = NEW.roster_group_id
        JOIN slot_names sn ON sn.id = NEW.slot_name_id
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
            AND rg.venue_id = NEW.venue_id
            AND sn.venue_id = NEW.venue_id
            AND sn.roster_group_id = NEW.roster_group_id
    ) THEN
        RAISE EXCEPTION 'staff shift preference staff, roster group, and slot name must stay within one venue and group';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_leave_request_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'leave request venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_timesheet_entry_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match staff_id venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM shift_types st
        WHERE st.id = NEW.shift_type_id
            AND st.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match shift_type_id venue';
    END IF;

    IF NEW.pay_config_snapshot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM pay_config_snapshots pcs
            WHERE pcs.id = NEW.pay_config_snapshot_id
                AND pcs.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match pay_config_snapshot_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_report_definition_filter_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM report_definitions rd
        JOIN shift_types st ON st.id = NEW.shift_type_id
        WHERE rd.id = NEW.report_definition_id
            AND rd.venue_id = st.venue_id
    ) THEN
        RAISE EXCEPTION 'report definition shift type filter must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_xero_connection_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM xero_connections xc
        WHERE xc.id = NEW.xero_connection_id
            AND xc.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero child row venue_id must match xero_connection_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_xero_staff_mapping_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM xero_connections xc
        WHERE xc.id = NEW.xero_connection_id
            AND xc.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero child row venue_id must match xero_connection_id venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero staff mapping venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION enforce_roster_week_venue_integrity();
CREATE TRIGGER enforce_slot_name_venue_integrity BEFORE INSERT OR UPDATE ON slot_names FOR EACH ROW EXECUTE FUNCTION enforce_slot_name_venue_integrity();
CREATE TRIGGER enforce_staff_roster_group_venue_integrity BEFORE INSERT OR UPDATE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION enforce_staff_roster_group_venue_integrity();
CREATE TRIGGER enforce_staff_shift_preference_venue_integrity BEFORE INSERT OR UPDATE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION enforce_staff_shift_preference_venue_integrity();
CREATE TRIGGER enforce_leave_request_venue_integrity BEFORE INSERT OR UPDATE ON leave_requests FOR EACH ROW EXECUTE FUNCTION enforce_leave_request_venue_integrity();
CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_entry_venue_integrity();
CREATE TRIGGER enforce_report_definition_filter_venue_integrity BEFORE INSERT OR UPDATE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION enforce_report_definition_filter_venue_integrity();
CREATE TRIGGER enforce_xero_sync_runs_venue_integrity BEFORE INSERT OR UPDATE ON xero_sync_runs FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_employees_venue_integrity BEFORE INSERT OR UPDATE ON xero_employees FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_earnings_rates_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rates FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_payroll_calendars_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendars FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_staff_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_staff_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_staff_mapping_venue_integrity();
CREATE TRIGGER enforce_xero_earnings_rate_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rate_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_payroll_calendar_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendar_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_pay_item_account_code_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_account_code_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_pay_item_requirement_records_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_requirement_records FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();

-- schema-nav: pay-sql-functions
CREATE OR REPLACE FUNCTION resolve_effective_pay_level(p_staff_id UUID, p_shift_type_id UUID, p_day_of_week INT)
RETURNS UUID
AS $$
    SELECT
        COALESCE(
            (
                SELECT st.override_award_level_id
                FROM shift_types st
                WHERE st.id = p_shift_type_id
                    AND st.override_award_level_id IS NOT NULL
                LIMIT 1
            ),
            (
                SELECT s.default_award_level_id
                FROM staff s
                WHERE s.id = p_staff_id
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
                    NULL,
                    NULLIF(shift_type ->> 'overrideAwardLevelId', '')::UUID
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
            AND te.deleted_at IS NULL
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
            e.had_break,
            e.break_start_time,
            e.break_end_time,
            e.break_minutes,
            e.pay_config_snapshot_id,
            e.pay_config_snapshot_version,
            e.pay_config_snapshot,
            (
                SELECT s.employment_basis
                FROM staff s
                WHERE s.id = e.staff_id
                LIMIT 1
            ) AS employment_basis,
            (EXTRACT(EPOCH FROM e.start_time) / 60)::INT AS start_minute_of_day,
            (
                CASE
                    WHEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                        THEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT + 1440
                    ELSE (EXTRACT(EPOCH FROM e.end_time) / 60)::INT
                END
            ) AS end_minute_of_day,
            CASE
                WHEN e.had_break
                    AND e.break_start_time IS NOT NULL
                    AND e.break_end_time IS NOT NULL
                    AND e.break_minutes > 0
                THEN
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT < (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT
                    END
                ELSE NULL
            END AS break_start_minute_of_day,
            CASE
                WHEN e.had_break
                    AND e.break_start_time IS NOT NULL
                    AND e.break_end_time IS NOT NULL
                    AND e.break_minutes > 0
                THEN
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT + 1440
                        WHEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT < (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT
                    END
                ELSE NULL
            END AS break_end_minute_of_day,
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
            resolve_effective_pay_level(
                e.staff_id,
                e.shift_type_id,
                EXTRACT(DOW FROM e.worked_on)::INT
            ) AS pay_level_id
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
            (
                SELECT COALESCE(al.classification_level || ' - ', '') || al.classification
                FROM award_levels al
                WHERE al.id = r.pay_level_id
                LIMIT 1
            ) AS pay_level_name,
            (
                SELECT al.award_fixed_id
                FROM award_levels al
                WHERE al.id = r.pay_level_id
                LIMIT 1
            ) AS award_fixed_id,
            COALESCE(
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = r.employment_basis
                        AND (albr.operative_from IS NULL OR albr.operative_from <= r.worked_on)
                        AND (albr.operative_to IS NULL OR albr.operative_to >= r.worked_on)
                    ORDER BY albr.operative_from DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                0::NUMERIC(12,4)
            ) AS base_rate,
            COALESCE(
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = 'permanent'
                        AND (albr.operative_from IS NULL OR albr.operative_from <= r.worked_on)
                        AND (albr.operative_to IS NULL OR albr.operative_to >= r.worked_on)
                    ORDER BY albr.operative_from DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = r.employment_basis
                        AND (albr.operative_from IS NULL OR albr.operative_from <= r.worked_on)
                        AND (albr.operative_to IS NULL OR albr.operative_to >= r.worked_on)
                    ORDER BY albr.operative_from DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                0::NUMERIC(12,4)
            ) AS permanent_base_rate,
            EXISTS (
                SELECT 1
                FROM staff s
                JOIN venue_config vc ON vc.venue_id = s.venue_id
                JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                    AND ph.holiday_date = r.worked_on
                    AND ph.is_regional = FALSE
                WHERE s.id = r.staff_id
                LIMIT 1
            ) AS is_public_holiday
        FROM resolved r
    ),
    paid_window AS (
        SELECT
            r.*,
            CASE
                WHEN r.break_start_minute_of_day IS NOT NULL AND r.break_end_minute_of_day IS NOT NULL
                    THEN LEAST(r.end_minute_of_day, 1860)
                ELSE LEAST(r.start_minute_of_day + r.paid_minutes, 1860)
            END AS paid_end_minute_of_day
        FROM labelled r
    ),
    delayed_meal_break_window AS (
        SELECT
            pw.*,
            CASE
                WHEN pw.end_minute_of_day - pw.start_minute_of_day > 360
                    AND NOT (
                        pw.break_start_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                        AND pw.break_start_minute_of_day <= pw.start_minute_of_day + 360
                    )
                THEN pw.start_minute_of_day + 360
                ELSE NULL
            END AS delayed_meal_break_start_minute,
            CASE
                WHEN pw.end_minute_of_day - pw.start_minute_of_day > 360
                    AND NOT (
                        pw.break_start_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                        AND pw.break_start_minute_of_day <= pw.start_minute_of_day + 360
                    )
                THEN
                    CASE
                        WHEN pw.break_start_minute_of_day IS NOT NULL
                            AND pw.break_end_minute_of_day IS NOT NULL
                            AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                            AND pw.break_start_minute_of_day > pw.start_minute_of_day + 360
                        THEN pw.break_start_minute_of_day
                        ELSE pw.end_minute_of_day
                    END
                ELSE NULL
            END AS delayed_meal_break_end_minute
        FROM paid_window pw
    ),
    segment_windows AS (
        SELECT *
        FROM (
            VALUES
                ('late_night_after_midnight'::TEXT, 0, 420, 1),
                ('ordinary'::TEXT, 420, 1140, 2),
                ('evening_after_7pm'::TEXT, 1140, 1440, 3),
                ('late_night_after_midnight'::TEXT, 1440, 1860, 4)
        ) AS windows(segment_name, window_start_minute, window_end_minute, sort_index)
    ),
    segment_rows AS (
        SELECT scoped.*,
            CASE
                WHEN scoped.penalty_kind IN ('delayed_meal_break_weekday', 'delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday') THEN
                    (
                        CASE
                            WHEN scoped.penalty_kind IN ('delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday') THEN
                                COALESCE(
                                    (
                                        SELECT alpr.hourly_rate
                                        FROM award_level_penalty_rates alpr
                                        WHERE alpr.award_level_id = scoped.pay_level_id
                                            AND alpr.employment_basis = scoped.employment_basis
                                            AND alpr.penalty_kind =
                                                CASE scoped.penalty_kind
                                                    WHEN 'delayed_meal_break_saturday' THEN 'saturday_penalty'::award_penalty_kind_enum
                                                    WHEN 'delayed_meal_break_sunday' THEN 'sunday_penalty'::award_penalty_kind_enum
                                                    WHEN 'delayed_meal_break_public_holiday' THEN 'public_holiday_penalty'::award_penalty_kind_enum
                                                    ELSE NULL::award_penalty_kind_enum
                                                END
                                            AND (alpr.operative_from IS NULL OR alpr.operative_from <= scoped.segment_date)
                                            AND (alpr.operative_to IS NULL OR alpr.operative_to >= scoped.segment_date)
                                        ORDER BY alpr.operative_from DESC NULLS LAST, alpr.created_at DESC
                                        LIMIT 1
                                    ),
                                    scoped.base_rate
                                )
                            ELSE scoped.base_rate
                        END
                    ) + (scoped.permanent_base_rate * 0.5)
                WHEN scoped.penalty_kind IN ('saturday_penalty', 'sunday_penalty', 'public_holiday_penalty') THEN
                    COALESCE(
                        (
                            SELECT alpr.hourly_rate
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (alpr.operative_from IS NULL OR alpr.operative_from <= scoped.segment_date)
                                AND (alpr.operative_to IS NULL OR alpr.operative_to >= scoped.segment_date)
                            ORDER BY alpr.operative_from DESC NULLS LAST, alpr.created_at DESC
                            LIMIT 1
                        ),
                        scoped.base_rate
                    )
                WHEN scoped.penalty_kind IN ('evening_after_7pm', 'late_night_after_midnight') THEN
                    scoped.base_rate + COALESCE(
                        (
                            SELECT atpa.hourly_amount
                            FROM award_time_penalty_allowances atpa
                            WHERE atpa.award_fixed_id = scoped.award_fixed_id
                                AND atpa.penalty_kind = scoped.penalty_kind
                                AND (atpa.operative_from IS NULL OR atpa.operative_from <= scoped.segment_date)
                                AND (atpa.operative_to IS NULL OR atpa.operative_to >= scoped.segment_date)
                            ORDER BY atpa.operative_from DESC NULLS LAST, atpa.created_at DESC
                            LIMIT 1
                        ),
                        (
                            SELECT GREATEST(alpr.hourly_rate - scoped.base_rate, 0)
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (alpr.operative_from IS NULL OR alpr.operative_from <= scoped.segment_date)
                                AND (alpr.operative_to IS NULL OR alpr.operative_to >= scoped.segment_date)
                            ORDER BY alpr.operative_from DESC NULLS LAST, alpr.created_at DESC
                            LIMIT 1
                        ),
                        0::NUMERIC(12,4)
                    )
                ELSE scoped.base_rate
            END AS segment_hourly_rate
        FROM (
            SELECT
                pw.id,
                pw.staff_id,
                pw.worked_on,
                pw.break_minutes,
                pw.paid_minutes,
                pw.break_start_minute_of_day,
                pw.break_end_minute_of_day,
                pw.shift_type_id,
                pw.shift_type_name,
                pw.pay_level_id,
                pw.pay_level_name,
                pw.award_fixed_id,
                pw.employment_basis,
                pw.permanent_base_rate,
                pw.pay_config_snapshot_id,
                pw.pay_config_snapshot_version,
                pw.pay_config_snapshot,
                scoped_segments.segment_name,
                scoped_segments.segment_date,
                scoped_segments.penalty_kind,
                scoped_segments.segment_minutes,
                pw.base_rate,
                scoped_segments.sort_index
            FROM delayed_meal_break_window pw
            CROSS JOIN LATERAL (
                SELECT
                    sw.segment_name,
                    (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END) AS segment_date,
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'public_holiday_penalty'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'saturday_penalty'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'sunday_penalty'::award_penalty_kind_enum
                        WHEN sw.segment_name = 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum
                        WHEN sw.segment_name = 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum
                        ELSE NULL::award_penalty_kind_enum
                    END AS penalty_kind,
                    GREATEST(
                        GREATEST(
                            LEAST(pw.paid_end_minute_of_day, sw.window_end_minute)
                            - GREATEST(pw.start_minute_of_day, sw.window_start_minute),
                            0
                        )::INT
                        - CASE
                            WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                GREATEST(
                                    LEAST(pw.break_end_minute_of_day, sw.window_end_minute)
                                    - GREATEST(pw.break_start_minute_of_day, sw.window_start_minute),
                                    0
                                )::INT
                            ELSE 0
                        END
                        - GREATEST(
                            CASE
                                WHEN pw.delayed_meal_break_start_minute IS NOT NULL AND pw.delayed_meal_break_end_minute IS NOT NULL THEN
                                    GREATEST(
                                        LEAST(pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                        - GREATEST(pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                        0
                                    )::INT
                                    - CASE
                                        WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                            GREATEST(
                                                LEAST(pw.break_end_minute_of_day, pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                                - GREATEST(pw.break_start_minute_of_day, pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                                0
                                            )::INT
                                        ELSE 0
                                    END
                                ELSE 0
                            END,
                            0
                        ),
                        0
                    ) AS segment_minutes,
                    sw.sort_index * 10 AS sort_index
                FROM segment_windows sw

                UNION ALL

                SELECT
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'delayed_meal_break_public_holiday'
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'delayed_meal_break_saturday'
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'delayed_meal_break_sunday'
                        ELSE 'delayed_meal_break_weekday'
                    END AS segment_name,
                    (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END) AS segment_date,
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'delayed_meal_break_public_holiday'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'delayed_meal_break_saturday'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'delayed_meal_break_sunday'::award_penalty_kind_enum
                        ELSE 'delayed_meal_break_weekday'::award_penalty_kind_enum
                    END AS penalty_kind,
                    GREATEST(
                        CASE
                            WHEN pw.delayed_meal_break_start_minute IS NOT NULL AND pw.delayed_meal_break_end_minute IS NOT NULL THEN
                                GREATEST(
                                    LEAST(pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                    - GREATEST(pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                    0
                                )::INT
                                - CASE
                                    WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                        GREATEST(
                                            LEAST(pw.break_end_minute_of_day, pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                            - GREATEST(pw.break_start_minute_of_day, pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                            0
                                        )::INT
                                    ELSE 0
                                END
                            ELSE 0
                        END,
                        0
                    ) AS segment_minutes,
                    sw.sort_index * 10 + 5 AS sort_index
                FROM segment_windows sw
            ) scoped_segments
        ) scoped
    ),
    segment_json AS (
        SELECT
            sr.id,
            COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'segment', sr.segment_name,
                        'segmentDate', sr.segment_date,
                        'minutes', sr.segment_minutes,
                        'shiftTypeId', sr.shift_type_id,
                        'shiftTypeName', sr.shift_type_name,
                        'payLevelId', sr.pay_level_id,
                        'payLevelName', sr.pay_level_name,
                        'penaltyKind', sr.penalty_kind,
                        'dayRuleMultiplier', CASE WHEN sr.base_rate = 0 THEN 1 ELSE ROUND((sr.segment_hourly_rate / sr.base_rate), 3) END,
                        'weekendMultiplier', CASE WHEN sr.penalty_kind IN ('saturday_penalty', 'sunday_penalty') AND sr.base_rate <> 0 THEN ROUND((sr.segment_hourly_rate / sr.base_rate), 3) ELSE 1 END,
                        'multiplier', CASE WHEN sr.base_rate = 0 THEN 1 ELSE ROUND((sr.segment_hourly_rate / sr.base_rate), 3) END,
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
        AND te.worked_on <= p_to_date
        AND te.deleted_at IS NULL;
$$ LANGUAGE SQL;
