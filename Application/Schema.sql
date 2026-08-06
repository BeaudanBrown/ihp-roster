-- Your database schema. Use the Schema Designer at http://localhost:8001/ to add some tables.
--
-- Schema navigation map:
-- - schema-nav: enum-types - shared status/role/action enums. Some finite
--   domains intentionally remain TEXT + explicit OR checks for IHP parser
--   compatibility; hardening belongs in GitHub issue #53.
-- - schema-nav: identity-and-access - venues, users, email verification,
--   passkeys, memberships, invitations, and onboarding.
-- - schema-nav: staff-profiles - venue staff profile and employment defaults.
-- - schema-nav: staff-documents - private venue-scoped staff compliance
--   documents such as RSA evidence.
-- - schema-nav: venue-config - shift types and venue-level defaults.
-- - schema-nav: roster-group-config - roster groups, staff group assignments,
--   and slot/day names.
-- - schema-nav: pay-reference - relational pay config versions, FWC MAPD
--   imports, award levels, rates, allowances, and public holidays.
-- - schema-nav: async-jobs - durable app jobs and progress/result payloads.
-- - schema-nav: roster-planning - roster weeks, days, slots, and staff shift
--   preferences.
-- - schema-nav: leave-timesheets-audit - leave requests, audit trail, and
--   export jobs.
-- - schema-nav: billing - venue-scoped Stripe customer/subscription mirrors,
--   durable Checkout attempts, provider ordering, event idempotency, and
--   manual billing controls.
-- - schema-nav: xero - OAuth connections, retained reference rows, mappings,
--   preparation choices, and pay item setup.
-- - schema-nav: timesheets - timesheet entries and version history.
-- - schema-nav: xero-submissions - Xero submission runs and submitted entries.
-- - schema-nav: indexes - composite, partial, uniqueness, and lookup indexes.
-- - schema-nav: retention-triggers - hard-delete guards for retained tables.
-- - schema-nav: tenant-integrity-triggers - cross-table venue consistency.
-- - schema-nav: pay-sql-functions - SQL pay calculation helpers.

-- schema-nav: enum-types
CREATE TYPE venue_status_enum AS ENUM ('active', 'inactive');
CREATE TYPE venue_role_enum AS ENUM ('worker', 'supervisor', 'manager', 'venue_admin', 'venue_owner');
CREATE TYPE platform_role_enum AS ENUM ('super_admin');
CREATE TYPE invitation_status_enum AS ENUM ('pending', 'accepted', 'revoked');
CREATE TYPE invitation_delivery_status_enum AS ENUM ('queued', 'sent', 'failed');
CREATE TYPE leave_request_status_enum AS ENUM ('pending', 'approved', 'denied');
CREATE TYPE leave_request_event_type_enum AS ENUM ('created', 'approved', 'denied', 'deleted');
CREATE TYPE entry_version_action_enum AS ENUM ('created', 'updated', 'approved', 'unapproved', 'approval_reset', 'deleted');
CREATE TYPE venue_membership_role_event_type_enum AS ENUM ('assigned', 'changed');
CREATE TYPE staff_employment_basis_enum AS ENUM ('permanent', 'casual');
CREATE TYPE pay_assignment_mode_enum AS ENUM ('award_rate', 'xero_rate', 'roster_only', 'staff_default', 'legacy_unresolved');
CREATE TYPE staff_document_type_enum AS ENUM ('rsa_statement_of_attainment');
CREATE TYPE staff_document_status_enum AS ENUM ('pending_review', 'verified', 'rejected', 'expired');
CREATE TYPE award_penalty_kind_enum AS ENUM ('evening_after_7pm', 'late_night_after_midnight', 'saturday_penalty', 'sunday_penalty', 'public_holiday_penalty', 'delayed_meal_break_weekday', 'delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday');
CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');
CREATE TYPE roster_template_scale_enum AS ENUM ('day', 'week');
CREATE TYPE feedback_type_enum AS ENUM ('bug', 'suggestion', 'other');
CREATE TYPE shift_type_colour_key_enum AS ENUM ('no_colour', 'palette_1', 'palette_2', 'palette_3', 'palette_4', 'palette_5', 'palette_6', 'palette_7', 'palette_8', 'palette_9', 'palette_10');
CREATE TYPE xero_sync_status_enum AS ENUM ('running', 'succeeded', 'failed');
CREATE TYPE xero_sync_kind_enum AS ENUM ('payroll_reference_data');
CREATE TYPE xero_staff_mapping_status_enum AS ENUM ('verified', 'not_applicable', 'stale');
CREATE TYPE xero_earnings_rate_mapping_status_enum AS ENUM ('unmapped', 'verified', 'stale');
CREATE TYPE xero_pay_item_account_code_selection_status_enum AS ENUM ('none', 'verified', 'stale');
CREATE TYPE xero_pay_item_requirement_status_enum AS ENUM ('proposed', 'matched', 'created', 'ignored', 'stale', 'rate_changed');
CREATE TYPE xero_submission_source_kind_enum AS ENUM ('approved_timesheets');
CREATE TYPE xero_submission_run_status_enum AS ENUM ('previewed', 'blocked', 'pending', 'submitted', 'partially_failed', 'failed', 'superseded');
CREATE TYPE xero_timesheet_preparation_run_status_enum AS ENUM ('started', 'preparing', 'needs_reconnect', 'needs_approval', 'blocked', 'resolved', 'ready_for_preview', 'previewed', 'submitted', 'failed', 'cancelled');
CREATE TYPE xero_timesheet_preparation_decision_kind_enum AS ENUM ('staff_auto_match', 'staff_manual_mapping', 'staff_not_paid', 'staff_step_approved', 'pay_item_create', 'account_code', 'calendar_selection');
CREATE TYPE xero_timesheet_preparation_decision_status_enum AS ENUM ('pending', 'proposed', 'applied', 'blocked', 'resolved', 'dismissed');
CREATE TYPE xero_timesheet_submission_status_enum AS ENUM ('blocked', 'pending', 'submitted', 'failed', 'skipped', 'superseded');

-- schema-nav: identity-and-access
CREATE TABLE venues (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    status venue_status_enum DEFAULT 'active' NOT NULL,
    closed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    closed_by_user_id UUID DEFAULT NULL,
    retention_until TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120))
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
    CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254)),
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
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120))
);
CREATE TABLE passkey_recovery_codes (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    code_hash TEXT NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(user_id),
    UNIQUE(code_hash),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CHECK (char_length(btrim(code_hash)) > 0)
);
CREATE TABLE passkey_setup_tokens (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    requested_by_user_id UUID DEFAULT NULL,
    venue_id UUID DEFAULT NULL,
    token_hash TEXT NOT NULL,
    purpose TEXT NOT NULL,
    sent_to_email TEXT NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    consumed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(token_hash),
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE CASCADE,
    CHECK ((purpose = 'self_new_device') OR (purpose = 'staff_new_device') OR (purpose = 'staff_recovery')),
    CHECK ((char_length(btrim(sent_to_email)) > 0) AND (char_length(sent_to_email) <= 254)),
    CHECK (char_length(btrim(token_hash)) > 0)
);
CREATE TABLE user_preferences (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL,
    roster_layout_mode roster_layout_mode_enum DEFAULT 'day_rows' NOT NULL,
    show_shift_type_highlights BOOLEAN DEFAULT TRUE NOT NULL,
    show_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL,
    highlight_own_live_shifts BOOLEAN DEFAULT TRUE NOT NULL,
    hide_approved BOOLEAN DEFAULT TRUE NOT NULL,
    show_timesheet_suggestions BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(user_id),
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
    staff_id UUID DEFAULT NULL,
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
    FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254))
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
    FOREIGN KEY (accepted_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    CHECK ((char_length(btrim(email)) > 0) AND (char_length(email) <= 254))
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
    pay_assignment_mode pay_assignment_mode_enum DEFAULT 'roster_only' NOT NULL,
    default_award_level_id UUID DEFAULT NULL,
    imported_xero_pay_item_id UUID DEFAULT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(first_name)) > 0) AND (char_length(first_name) <= 80)),
    CHECK ((char_length(btrim(last_name)) > 0) AND (char_length(last_name) <= 80)),
    CHECK (preferred_name IS NULL OR ((char_length(btrim(preferred_name)) > 0) AND (char_length(preferred_name) <= 80))),
    CHECK ((char_length(btrim(phone)) > 0) AND (char_length(phone) <= 80)),
    CHECK ((char_length(btrim(emergency_contact_name)) > 0) AND (char_length(emergency_contact_name) <= 120)),
    CHECK ((char_length(btrim(emergency_contact_phone)) > 0) AND (char_length(emergency_contact_phone) <= 80)),
    CHECK ((ideal_shifts_per_week >= 0) AND (ideal_shifts_per_week <= 7)),
    CHECK (
        (pay_assignment_mode = 'award_rate' AND default_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'xero_rate' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
        OR (pay_assignment_mode = 'roster_only' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'legacy_unresolved' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    )
);

-- schema-nav: staff-documents
CREATE TABLE staff_documents (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    document_type staff_document_type_enum DEFAULT 'rsa_statement_of_attainment' NOT NULL,
    status staff_document_status_enum DEFAULT 'pending_review' NOT NULL,
    issue_date DATE DEFAULT NULL,
    expiry_date DATE NOT NULL,
    issuing_authority TEXT DEFAULT NULL,
    document_number TEXT DEFAULT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_encoding TEXT DEFAULT 'base64' NOT NULL,
    file_contents TEXT NOT NULL,
    extraction_method TEXT DEFAULT NULL,
    extraction_confidence INT DEFAULT NULL,
    extraction_warnings_json JSONB DEFAULT NULL,
    extracted_subject_name TEXT DEFAULT NULL,
    uploaded_by_user_id UUID NOT NULL,
    reviewed_by_user_id UUID DEFAULT NULL,
    reviewed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    rejection_reason TEXT DEFAULT NULL,
    expiry_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    expired_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (uploaded_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (reviewed_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (issue_date IS NULL OR issue_date <= expiry_date),
    CHECK ((char_length(btrim(file_name)) > 0) AND (char_length(file_name) <= 255)),
    CHECK ((char_length(btrim(content_type)) > 0) AND (char_length(content_type) <= 120)),
    CHECK (file_encoding = 'base64'),
    CHECK (char_length(file_contents) > 0),
    CHECK (issuing_authority IS NULL OR ((char_length(btrim(issuing_authority)) > 0) AND (char_length(issuing_authority) <= 160))),
    CHECK (document_number IS NULL OR ((char_length(btrim(document_number)) > 0) AND (char_length(document_number) <= 80))),
    CHECK (extraction_method IS NULL OR ((char_length(btrim(extraction_method)) > 0) AND (char_length(extraction_method) <= 160))),
    CHECK (extraction_confidence IS NULL OR extraction_confidence >= 0),
    CHECK (extraction_confidence IS NULL OR extraction_confidence <= 100),
    CHECK (extraction_warnings_json IS NULL OR jsonb_typeof(extraction_warnings_json) = 'array'),
    CHECK (extracted_subject_name IS NULL OR ((char_length(btrim(extracted_subject_name)) > 0) AND (char_length(extracted_subject_name) <= 160))),
    CHECK (rejection_reason IS NULL OR ((char_length(btrim(rejection_reason)) > 0) AND (char_length(rejection_reason) <= 500))),
    CHECK (((status = 'rejected') AND rejection_reason IS NOT NULL) OR (status <> 'rejected')),
    CHECK ((reviewed_at IS NULL AND reviewed_by_user_id IS NULL) OR (reviewed_at IS NOT NULL AND reviewed_by_user_id IS NOT NULL))
);

-- schema-nav: venue-config
CREATE TABLE shift_types (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    pay_assignment_mode pay_assignment_mode_enum DEFAULT 'staff_default' NOT NULL,
    override_award_level_id UUID DEFAULT NULL,
    imported_xero_pay_item_id UUID DEFAULT NULL,
    colour_key shift_type_colour_key_enum DEFAULT 'no_colour' NOT NULL,
    is_active BOOLEAN DEFAULT TRUE NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (
        (pay_assignment_mode = 'award_rate' AND override_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'xero_rate' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
        OR (pay_assignment_mode = 'roster_only' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'staff_default' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    )
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
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120))
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
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120))
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
-- auto_timesheet_creation_enabled is a deprecated compatibility column;
-- background roster-to-timesheet creation is retired.
CREATE TABLE venue_config (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    timezone TEXT NOT NULL,
    roster_week_starts_on INT NOT NULL,
    week_offset_epoch DATE NOT NULL,
    late_to_early_min_start_gap_minutes INT DEFAULT 0 NOT NULL,
    time_picker_start_minute_of_day INT DEFAULT 360 NOT NULL,
    time_picker_final_selectable_minute_of_day INT DEFAULT 345 NOT NULL,
    minute_precision_shift_times_enabled BOOLEAN DEFAULT FALSE NOT NULL,
    roster_end_times_enabled BOOLEAN DEFAULT TRUE NOT NULL,
    auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL,
    staff_timesheet_edit_window_days INT DEFAULT 7 NOT NULL,
    unavailable_staff_warning_threshold INT DEFAULT NULL,
    public_holiday_jurisdiction TEXT DEFAULT 'VIC' NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((roster_week_starts_on >= 0) AND (roster_week_starts_on <= 6)),
    CHECK (late_to_early_min_start_gap_minutes >= 0),
    CHECK ((time_picker_start_minute_of_day >= 0) AND (time_picker_start_minute_of_day < 1440) AND (MOD(time_picker_start_minute_of_day, 15) = 0)),
    CHECK ((time_picker_final_selectable_minute_of_day >= 0) AND (time_picker_final_selectable_minute_of_day < 1440) AND (MOD(time_picker_final_selectable_minute_of_day, 15) = 0)),
    CHECK (time_picker_start_minute_of_day <> time_picker_final_selectable_minute_of_day),
    CHECK (staff_timesheet_edit_window_days >= 0),
    CHECK (unavailable_staff_warning_threshold IS NULL OR ((unavailable_staff_warning_threshold >= 1) AND (unavailable_staff_warning_threshold <= 100)))
);

-- schema-nav: pay-reference
CREATE TABLE staff_pay_versions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    pay_assignment_mode pay_assignment_mode_enum DEFAULT 'roster_only' NOT NULL,
    default_award_level_id UUID DEFAULT NULL,
    imported_xero_pay_item_id UUID DEFAULT NULL,
    employment_basis staff_employment_basis_enum NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE DEFAULT NULL,
    superseded_by_id UUID DEFAULT NULL,
    created_by_user_id UUID NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by_user_id UUID DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (superseded_by_id) REFERENCES staff_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (locked_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CHECK (
        (pay_assignment_mode = 'award_rate' AND default_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'xero_rate' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
        OR (pay_assignment_mode = 'roster_only' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'legacy_unresolved' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    )
);
CREATE TABLE shift_type_pay_versions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    shift_type_id UUID NOT NULL,
    pay_assignment_mode pay_assignment_mode_enum DEFAULT 'staff_default' NOT NULL,
    override_award_level_id UUID DEFAULT NULL,
    imported_xero_pay_item_id UUID DEFAULT NULL,
    payroll_label TEXT NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE DEFAULT NULL,
    superseded_by_id UUID DEFAULT NULL,
    created_by_user_id UUID NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    locked_by_user_id UUID DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT,
    FOREIGN KEY (superseded_by_id) REFERENCES shift_type_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (locked_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (effective_to IS NULL OR effective_to >= effective_from),
    CHECK (
        (pay_assignment_mode = 'award_rate' AND override_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'xero_rate' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
        OR (pay_assignment_mode = 'roster_only' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
        OR (pay_assignment_mode = 'staff_default' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    )
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
CREATE TABLE roster_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_group_id UUID NOT NULL,
    name TEXT NOT NULL,
    scale roster_template_scale_enum NOT NULL,
    current_version INT DEFAULT 0 NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (name = btrim(name)),
    CHECK (current_version >= 0)
);
CREATE TABLE roster_template_designs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_group_id UUID NOT NULL,
    scale roster_template_scale_enum NOT NULL,
    draft_owner_user_id UUID DEFAULT NULL,
    draft_name TEXT DEFAULT NULL,
    template_id UUID DEFAULT NULL,
    version_number INT DEFAULT NULL,
    source_template_id UUID DEFAULT NULL,
    base_version_number INT DEFAULT NULL,
    created_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (draft_owner_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (template_id) REFERENCES roster_templates (id) ON DELETE RESTRICT,
    FOREIGN KEY (source_template_id) REFERENCES roster_templates (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CONSTRAINT roster_template_designs_kind_check CHECK (
        (draft_owner_user_id IS NOT NULL AND draft_name IS NOT NULL AND template_id IS NULL AND version_number IS NULL)
        OR (draft_owner_user_id IS NULL AND draft_name IS NULL AND template_id IS NOT NULL AND version_number IS NOT NULL)
    ),
    CONSTRAINT roster_template_designs_source_check CHECK (
        (source_template_id IS NULL AND base_version_number IS NULL)
        OR (source_template_id IS NOT NULL AND base_version_number IS NOT NULL)
    ),
    CHECK (draft_name IS NULL OR ((char_length(btrim(draft_name)) > 0) AND (char_length(draft_name) <= 120) AND draft_name = btrim(draft_name))),
    CHECK (version_number IS NULL OR version_number > 0),
    CHECK (base_version_number IS NULL OR base_version_number > 0)
);
CREATE TABLE roster_template_days (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_design_id UUID NOT NULL,
    day_index INT NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE NOT NULL,
    row_count INT DEFAULT 4 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_template_design_id, day_index),
    FOREIGN KEY (roster_template_design_id) REFERENCES roster_template_designs (id) ON DELETE CASCADE,
    CHECK ((day_index >= 0) AND (day_index <= 6)),
    CHECK (row_count >= 0)
);
CREATE TABLE roster_template_columns (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_design_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_template_design_id) REFERENCES roster_template_designs (id) ON DELETE CASCADE,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (name = btrim(name)),
    CHECK (sort_order >= 0)
);
CREATE TABLE roster_template_shifts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_design_id UUID NOT NULL,
    roster_template_day_id UUID NOT NULL,
    roster_template_column_id UUID NOT NULL,
    assignment_state TEXT NOT NULL,
    staff_id UUID DEFAULT NULL,
    row_index INT NOT NULL,
    start_minute INT NOT NULL,
    end_minute INT NOT NULL,
    shift_type_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT roster_template_shifts_assignment_shape_check CHECK (
        (assignment_state = 'staff' AND staff_id IS NOT NULL)
        OR (assignment_state = 'open' AND staff_id IS NULL)
    ),
    CONSTRAINT roster_template_shifts_assignment_state_check CHECK (assignment_state = 'staff' OR assignment_state = 'open'),
    CONSTRAINT roster_template_shifts_structure_check CHECK (end_minute > start_minute),
    CHECK (row_index >= 0),
    CHECK (start_minute >= 0),
    CHECK (end_minute <= 2880),
    FOREIGN KEY (roster_template_design_id) REFERENCES roster_template_designs (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_template_day_id) REFERENCES roster_template_days (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_template_column_id) REFERENCES roster_template_columns (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT
);
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
    row_count INT DEFAULT 4 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_week_id, day_offset),
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    CHECK ((day_offset >= 0) AND (day_offset <= 6)),
    CHECK (row_count >= 0)
);
CREATE TABLE roster_week_slot_definitions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_week_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (sort_order >= 0)
);
CREATE TABLE roster_slots (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_day_id UUID NOT NULL,
    assignment_state TEXT NOT NULL,
    staff_id UUID,
    roster_week_slot_definition_id UUID NOT NULL,
    slot_sort_order INT DEFAULT 0 NOT NULL,
    row_index INT NOT NULL,
    starts_at TIMESTAMP WITH TIME ZONE,
    ends_at TIMESTAMP WITH TIME ZONE,
    timezone TEXT NOT NULL,
    shift_type_id UUID,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    CONSTRAINT roster_slots_assignment_shape_check CHECK (
        (assignment_state = 'staff' AND staff_id IS NOT NULL)
        OR (assignment_state = 'open' AND staff_id IS NULL)
    ),
    CONSTRAINT roster_slots_assignment_state_check CHECK (assignment_state = 'staff' OR assignment_state = 'open'),
    CONSTRAINT roster_slots_active_structure_check CHECK (
        deleted_at IS NOT NULL
        OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at > starts_at AND shift_type_id IS NOT NULL)
    ),
    CHECK (row_index >= 0),
    CHECK (slot_sort_order >= 0),
    CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at),
    CHECK (char_length(btrim(timezone)) > 0),
    CHECK (timezone = 'Australia/Melbourne'),
    FOREIGN KEY (roster_day_id) REFERENCES roster_days (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_week_slot_definition_id) REFERENCES roster_week_slot_definitions (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE roster_notification_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    roster_group_id UUID NOT NULL,
    roster_week_id UUID NOT NULL,
    week_offset INT NOT NULL,
    week_start DATE NOT NULL,
    snapshot_schema_version INT DEFAULT 1 NOT NULL,
    roster_snapshot JSONB NOT NULL,
    recipient_snapshot JSONB NOT NULL,
    skipped_recipient_snapshot JSONB NOT NULL,
    requested_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (snapshot_schema_version > 0),
    CHECK (jsonb_typeof(roster_snapshot) = 'object'),
    CHECK (jsonb_typeof(recipient_snapshot) = 'array'),
    CHECK (jsonb_typeof(skipped_recipient_snapshot) = 'array')
);
CREATE TABLE staff_shift_preferences (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    weekday_index INT NOT NULL,
    preferred_start_hour INT DEFAULT 9 NOT NULL,
    preferred_end_hour INT DEFAULT 17 NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((weekday_index >= 0) AND (weekday_index <= 6)),
    CHECK ((preferred_start_hour >= 5) AND (preferred_start_hour <= 23)),
    CHECK ((preferred_end_hour >= 5) AND (preferred_end_hour <= 23)),
    CHECK (preferred_start_hour <= preferred_end_hour)
);

-- schema-nav: leave-timesheets-audit
CREATE FUNCTION unavailability_blackout_range_is_valid(first_blocked_date DATE, last_blocked_date DATE)
RETURNS BOOLEAN AS $$
    SELECT last_blocked_date >= first_blocked_date
       AND last_blocked_date - first_blocked_date <= 365;
$$ LANGUAGE SQL;

CREATE FUNCTION unavailability_blackout_reason_is_valid(blackout_reason TEXT)
RETURNS BOOLEAN AS $$
    SELECT char_length(btrim(blackout_reason)) BETWEEN 3 AND 160;
$$ LANGUAGE SQL;

CREATE TABLE unavailability_blackouts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK (unavailability_blackout_range_is_valid(start_date, end_date)),
    CHECK (unavailability_blackout_reason_is_valid(reason))
);
CREATE INDEX unavailability_blackouts_venue_end_date_index ON unavailability_blackouts (venue_id, end_date);
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
    CHECK (notes IS NULL OR char_length(notes) <= 1000),
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
CREATE TABLE user_feedback_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    submitted_by_user_id UUID NOT NULL,
    feedback_type feedback_type_enum DEFAULT 'bug' NOT NULL,
    status TEXT DEFAULT 'new' NOT NULL,
    priority TEXT DEFAULT 'normal' NOT NULL,
    content TEXT NOT NULL,
    submitted_path TEXT,
    user_agent TEXT,
    submitted_role TEXT DEFAULT NULL,
    viewport_width INTEGER DEFAULT NULL,
    viewport_height INTEGER DEFAULT NULL,
    device_pixel_ratio DOUBLE PRECISION DEFAULT NULL,
    device_class TEXT DEFAULT NULL,
    display_mode TEXT DEFAULT NULL,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    read_by_user_id UUID DEFAULT NULL,
    support_note TEXT,
    resolved_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    resolved_by_user_id UUID DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (submitted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (read_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (resolved_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((status = 'new') OR (status = 'triaged') OR (status = 'planned') OR (status = 'in_progress') OR (status = 'done') OR (status = 'closed')),
    CHECK ((priority = 'low') OR (priority = 'normal') OR (priority = 'high')),
    CHECK (char_length(content) >= 3),
    CHECK (char_length(content) <= 3000),
    CHECK (submitted_path IS NULL OR ((char_length(submitted_path) > 0) AND (char_length(submitted_path) <= 500))),
    CHECK (user_agent IS NULL OR char_length(user_agent) <= 500),
    CHECK (submitted_role IS NULL OR (submitted_role = 'worker') OR (submitted_role = 'supervisor') OR (submitted_role = 'manager') OR (submitted_role = 'venue_admin') OR (submitted_role = 'venue_owner') OR (submitted_role = 'support_super_admin')),
    CHECK (viewport_width IS NULL OR ((viewport_width >= 1) AND (viewport_width <= 10000))),
    CHECK (viewport_height IS NULL OR ((viewport_height >= 1) AND (viewport_height <= 10000))),
    CHECK (device_pixel_ratio IS NULL OR ((device_pixel_ratio > 0) AND (device_pixel_ratio <= 100))),
    CHECK (device_class IS NULL OR (device_class = 'mobile') OR (device_class = 'desktop')),
    CHECK (display_mode IS NULL OR (display_mode = 'browser') OR (display_mode = 'standalone')),
    CHECK (support_note IS NULL OR char_length(support_note) <= 3000),
    CHECK (((read_at IS NULL) AND (read_by_user_id IS NULL)) OR ((read_at IS NOT NULL) AND (read_by_user_id IS NOT NULL))),
    CHECK (((resolved_at IS NULL) AND (resolved_by_user_id IS NULL)) OR ((resolved_at IS NOT NULL) AND (resolved_by_user_id IS NOT NULL)))
);
CREATE INDEX user_feedback_items_unread_idx ON user_feedback_items (created_at) WHERE read_at IS NULL;
CREATE INDEX user_feedback_items_venue_created_at_idx ON user_feedback_items (venue_id, created_at);
CREATE TABLE export_jobs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    requested_by_user_id UUID NOT NULL,
    export_type TEXT NOT NULL,
    status TEXT DEFAULT 'pending' NOT NULL,
    schema_version INT DEFAULT 1 NOT NULL,
    pay_config_version_manifest TEXT,
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

-- schema-nav: billing
CREATE TABLE venue_billing_customers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    stripe_customer_id TEXT NOT NULL,
    livemode BOOLEAN NOT NULL,
    created_by_user_id UUID DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    UNIQUE(stripe_customer_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255))
);
CREATE TABLE billing_checkout_attempts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    initiated_by_user_id UUID NOT NULL,
    livemode BOOLEAN NOT NULL,
    stripe_customer_id TEXT NOT NULL,
    stripe_price_id TEXT NOT NULL,
    stripe_checkout_session_id TEXT DEFAULT NULL,
    stripe_subscription_id TEXT DEFAULT NULL,
    status TEXT DEFAULT 'open' NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    completed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    error_code TEXT DEFAULT NULL,
    error_summary TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(stripe_checkout_session_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (initiated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((status = 'open') OR (status = 'completed') OR (status = 'expired') OR (status = 'failed')),
    CHECK (((status = 'completed') AND completed_at IS NOT NULL AND stripe_checkout_session_id IS NOT NULL) OR ((status <> 'completed') AND completed_at IS NULL)),
    CHECK ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255)),
    CHECK ((char_length(btrim(stripe_price_id)) > 0) AND (char_length(stripe_price_id) <= 255)),
    CHECK (stripe_checkout_session_id IS NULL OR ((char_length(btrim(stripe_checkout_session_id)) > 0) AND (char_length(stripe_checkout_session_id) <= 255))),
    CHECK (stripe_subscription_id IS NULL OR ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255))),
    CHECK (error_code IS NULL OR ((char_length(btrim(error_code)) > 0) AND (char_length(error_code) <= 120))),
    CHECK (error_summary IS NULL OR ((char_length(btrim(error_summary)) > 0) AND (char_length(error_summary) <= 1000)))
);
CREATE TABLE venue_subscriptions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    stripe_subscription_id TEXT NOT NULL,
    stripe_price_id TEXT NOT NULL,
    livemode BOOLEAN NOT NULL,
    status TEXT NOT NULL,
    current_period_start TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    current_period_end TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    cancel_at_period_end BOOLEAN DEFAULT FALSE NOT NULL,
    last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_applied_stripe_event_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    last_applied_stripe_event_id TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    UNIQUE(stripe_subscription_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255)),
    CHECK ((char_length(btrim(stripe_price_id)) > 0) AND (char_length(stripe_price_id) <= 255)),
    CHECK ((status = 'incomplete') OR (status = 'incomplete_expired') OR (status = 'trialing') OR (status = 'active') OR (status = 'past_due') OR (status = 'canceled') OR (status = 'unpaid') OR (status = 'paused')),
    CHECK (current_period_start IS NULL OR current_period_end IS NULL OR current_period_start <= current_period_end),
    CHECK ((last_applied_stripe_event_created_at IS NULL AND last_applied_stripe_event_id IS NULL) OR (last_applied_stripe_event_created_at IS NOT NULL AND last_applied_stripe_event_id IS NOT NULL)),
    CHECK (last_applied_stripe_event_id IS NULL OR ((char_length(btrim(last_applied_stripe_event_id)) > 0) AND (char_length(last_applied_stripe_event_id) <= 255)))
);
CREATE TABLE billing_events (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    stripe_event_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    stripe_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    livemode BOOLEAN NOT NULL,
    api_version TEXT DEFAULT NULL,
    provider_object_type TEXT DEFAULT NULL,
    provider_object_id TEXT DEFAULT NULL,
    venue_id UUID DEFAULT NULL,
    stripe_customer_id TEXT DEFAULT NULL,
    stripe_subscription_id TEXT DEFAULT NULL,
    status TEXT DEFAULT 'received' NOT NULL,
    error_summary TEXT DEFAULT NULL,
    received_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    processed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(stripe_event_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(stripe_event_id)) > 0) AND (char_length(stripe_event_id) <= 255)),
    CHECK ((char_length(btrim(event_type)) > 0) AND (char_length(event_type) <= 255)),
    CHECK (api_version IS NULL OR ((char_length(btrim(api_version)) > 0) AND (char_length(api_version) <= 80))),
    CHECK (provider_object_type IS NULL OR ((char_length(btrim(provider_object_type)) > 0) AND (char_length(provider_object_type) <= 120))),
    CHECK (provider_object_id IS NULL OR ((char_length(btrim(provider_object_id)) > 0) AND (char_length(provider_object_id) <= 255))),
    CHECK (stripe_customer_id IS NULL OR ((char_length(btrim(stripe_customer_id)) > 0) AND (char_length(stripe_customer_id) <= 255))),
    CHECK (stripe_subscription_id IS NULL OR ((char_length(btrim(stripe_subscription_id)) > 0) AND (char_length(stripe_subscription_id) <= 255))),
    CHECK ((status = 'received') OR (status = 'processed') OR (status = 'failed') OR (status = 'ignored')),
    CHECK (error_summary IS NULL OR ((char_length(btrim(error_summary)) > 0) AND (char_length(error_summary) <= 1000))),
    CHECK (((status = 'processed') AND processed_at IS NOT NULL) OR (status <> 'processed'))
);
CREATE TABLE venue_billing_controls (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    billing_required BOOLEAN DEFAULT TRUE NOT NULL,
    manual_read_only BOOLEAN DEFAULT FALSE NOT NULL,
    manual_read_only_reason TEXT DEFAULT NULL,
    set_by_user_id UUID DEFAULT NULL,
    set_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(venue_id),
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (set_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (manual_read_only_reason IS NULL OR ((char_length(btrim(manual_read_only_reason)) > 0) AND (char_length(manual_read_only_reason) <= 500))),
    CHECK ((set_by_user_id IS NULL AND set_at IS NULL) OR (set_by_user_id IS NOT NULL AND set_at IS NOT NULL)),
    CHECK ((manual_read_only = FALSE) OR (manual_read_only_reason IS NOT NULL AND set_by_user_id IS NOT NULL AND set_at IS NOT NULL))
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
    sync_status xero_sync_status_enum NOT NULL,
    sync_kind xero_sync_kind_enum DEFAULT 'payroll_reference_data' NOT NULL,
    employees_count INT DEFAULT 0 NOT NULL,
    earnings_rates_count INT DEFAULT 0 NOT NULL,
    payroll_calendars_count INT DEFAULT 0 NOT NULL,
    error_message TEXT,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    finished_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT
);
CREATE TABLE xero_reference_sync_leases (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    tenant_id TEXT NOT NULL UNIQUE,
    app_job_id UUID DEFAULT NULL,
    lease_expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    next_request_not_before TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (app_job_id) REFERENCES app_jobs (id) ON DELETE SET NULL
);
CREATE INDEX idx_xero_reference_sync_leases_expiry ON xero_reference_sync_leases (lease_expires_at);
CREATE TABLE xero_employees (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_employee_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    email TEXT,
    status TEXT,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (provider_available = (provider_unavailable_at IS NULL))
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
    provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (provider_available = (provider_unavailable_at IS NULL))
);
CREATE TABLE xero_imported_pay_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_earnings_rate_id TEXT NOT NULL,
    name TEXT NOT NULL,
    account_code TEXT,
    earnings_type TEXT NOT NULL,
    rate_type TEXT NOT NULL,
    type_of_units TEXT NOT NULL,
    rate_per_unit NUMERIC(12,4) NOT NULL,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    imported_by_user_id UUID NOT NULL,
    imported_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    archived_by_user_id UUID DEFAULT NULL,
    archive_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (imported_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (archived_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 255)),
    CHECK (char_length(btrim(xero_earnings_rate_id)) > 0),
    CHECK (account_code IS NULL OR ((char_length(btrim(account_code)) > 0) AND (char_length(account_code) <= 80))),
    CHECK (lower(earnings_type) = 'ordinarytimeearnings'),
    CHECK (lower(rate_type) = 'rateperunit'),
    CHECK (lower(type_of_units) = 'hours'),
    CHECK (rate_per_unit > 0),
    CHECK (provider_available = (provider_unavailable_at IS NULL)),
    CHECK (archived_at IS NULL OR archived_by_user_id IS NOT NULL)
);
CREATE TABLE xero_accounts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_account_id TEXT NOT NULL,
    code TEXT,
    name TEXT NOT NULL,
    account_type TEXT,
    status TEXT,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (provider_available = (provider_unavailable_at IS NULL))
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
    provider_available BOOLEAN DEFAULT TRUE NOT NULL,
    provider_unavailable_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (provider_available = (provider_unavailable_at IS NULL))
);
CREATE TABLE xero_pay_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_pay_run_id TEXT NOT NULL,
    xero_payroll_calendar_id TEXT NOT NULL,
    pay_period_start DATE NOT NULL,
    pay_period_end DATE NOT NULL,
    payment_date DATE,
    pay_run_status TEXT,
    raw_payload JSONB DEFAULT '{}'::JSONB NOT NULL,
    synced_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_staff_mappings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    xero_employee_id TEXT,
    xero_employee_name TEXT,
    xero_employee_email TEXT,
    mapping_status xero_staff_mapping_status_enum DEFAULT 'not_applicable' NOT NULL,
    last_verified_at TIMESTAMP WITH TIME ZONE,
    reference_refreshed_at TIMESTAMP WITH TIME ZONE,
    created_by_user_id UUID,
    updated_by_user_id UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);
CREATE TABLE xero_earnings_rate_mappings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    local_bucket_key TEXT NOT NULL,
    local_bucket_label TEXT NOT NULL,
    xero_earnings_rate_id TEXT,
    xero_earnings_rate_name TEXT,
    mapping_status xero_earnings_rate_mapping_status_enum DEFAULT 'unmapped' NOT NULL,
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
    selection_status xero_pay_item_account_code_selection_status_enum DEFAULT 'none' NOT NULL,
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
    requirement_status xero_pay_item_requirement_status_enum DEFAULT 'proposed' NOT NULL,
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
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
);

-- schema-nav: timesheets
CREATE TABLE timesheet_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    staff_id UUID NOT NULL,
    shift_type_id UUID NOT NULL,
    starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ends_at TIMESTAMP WITH TIME ZONE NOT NULL,
    break_starts_at TIMESTAMP WITH TIME ZONE,
    break_ends_at TIMESTAMP WITH TIME ZONE,
    timezone TEXT NOT NULL,
    active_pay_calculation_id UUID DEFAULT NULL,
    legacy_pay_backfill_pending BOOLEAN DEFAULT FALSE NOT NULL,
    staff_pay_version_id UUID,
    shift_type_pay_version_id UUID,
    source_roster_slot_id UUID DEFAULT NULL,
    staff_comment TEXT DEFAULT NULL,
    manager_note TEXT DEFAULT NULL,
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
    FOREIGN KEY (staff_pay_version_id) REFERENCES staff_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_pay_version_id) REFERENCES shift_type_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (source_roster_slot_id) REFERENCES roster_slots (id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_by_user_id) REFERENCES users (id) ON DELETE SET NULL,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (ends_at > starts_at),
    CHECK ((break_starts_at IS NULL AND break_ends_at IS NULL) OR (break_starts_at IS NOT NULL AND break_ends_at IS NOT NULL AND break_starts_at >= starts_at AND break_ends_at > break_starts_at AND break_ends_at <= ends_at)),
    CHECK (char_length(btrim(timezone)) > 0),
    CHECK (timezone = 'Australia/Melbourne'),
    CHECK (staff_comment IS NULL OR char_length(staff_comment) <= 1000),
    CHECK (manager_note IS NULL OR char_length(manager_note) <= 1000),
    CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND staff_pay_version_id IS NULL AND shift_type_pay_version_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND staff_pay_version_id IS NOT NULL AND shift_type_pay_version_id IS NOT NULL))
);
CREATE TABLE timesheet_pay_calculations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    timesheet_entry_id UUID NOT NULL,
    calculation_version TEXT NOT NULL,
    calculation_source TEXT NOT NULL,
    rate_book_version TEXT DEFAULT NULL,
    venue_timezone TEXT NOT NULL,
    holiday_jurisdiction TEXT NOT NULL,
    staff_pay_version_id UUID NOT NULL,
    shift_type_pay_version_id UUID NOT NULL,
    approved_at TIMESTAMP WITH TIME ZONE NOT NULL,
    approved_by_user_id UUID NOT NULL,
    sealed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_pay_version_id) REFERENCES staff_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_pay_version_id) REFERENCES shift_type_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (char_length(btrim(calculation_version)) > 0),
    CHECK (calculation_source = 'hospitality_award' OR calculation_source = 'external_imported_pay_item'),
    CHECK (char_length(btrim(venue_timezone)) > 0),
    CHECK (char_length(btrim(holiday_jurisdiction)) > 0)
);
CREATE TABLE timesheet_pay_time_segments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    timesheet_pay_calculation_id UUID NOT NULL,
    ordinal INT NOT NULL,
    paid_time_kind TEXT NOT NULL,
    starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ends_at TIMESTAMP WITH TIME ZONE NOT NULL,
    local_date DATE NOT NULL,
    source_condition TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (timesheet_pay_calculation_id) REFERENCES timesheet_pay_calculations (id) ON DELETE RESTRICT,
    CHECK (ordinal >= 0),
    CHECK (ends_at > starts_at),
    CHECK (paid_time_kind = 'worked' OR paid_time_kind = 'casual_minimum_engagement_top_up' OR paid_time_kind = 'public_holiday_minimum_top_up'),
    CHECK (char_length(btrim(source_condition)) > 0),
    UNIQUE (timesheet_pay_calculation_id, ordinal)
);
CREATE TABLE timesheet_pay_earnings_components (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    timesheet_pay_calculation_id UUID NOT NULL,
    ordinal INT NOT NULL,
    quantity NUMERIC NOT NULL,
    unit_type TEXT NOT NULL,
    rate_per_unit NUMERIC NOT NULL,
    exact_amount NUMERIC NOT NULL,
    source_condition TEXT NOT NULL,
    calculation_source TEXT NOT NULL,
    source_rate_identity TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (timesheet_pay_calculation_id) REFERENCES timesheet_pay_calculations (id) ON DELETE RESTRICT,
    CHECK (ordinal >= 0),
    CHECK (quantity >= 0),
    CHECK (unit_type = 'hours' OR unit_type = 'commenced_hours'),
    CHECK (rate_per_unit >= 0),
    CHECK (exact_amount >= 0),
    CHECK (char_length(btrim(source_condition)) > 0),
    CHECK (calculation_source = 'hospitality_award' OR calculation_source = 'external_imported_pay_item'),
    CHECK (source_rate_identity IS NULL OR char_length(btrim(source_rate_identity)) > 0),
    UNIQUE (timesheet_pay_calculation_id, ordinal)
);
ALTER TABLE timesheet_entries
    ADD CONSTRAINT timesheet_entries_active_pay_calculation_id_fk
        FOREIGN KEY (active_pay_calculation_id) REFERENCES timesheet_pay_calculations (id) ON DELETE RESTRICT;
CREATE INDEX idx_timesheet_pay_calculations_entry ON timesheet_pay_calculations (timesheet_entry_id, created_at DESC);
CREATE INDEX idx_timesheet_pay_time_segments_calculation ON timesheet_pay_time_segments (timesheet_pay_calculation_id, ordinal);
CREATE INDEX idx_timesheet_pay_earnings_components_calculation ON timesheet_pay_earnings_components (timesheet_pay_calculation_id, ordinal);
CREATE OR REPLACE FUNCTION enforce_timesheet_pay_calculation_immutability()
RETURNS TRIGGER
AS $$
BEGIN
    IF TG_OP = 'UPDATE'
        AND OLD.sealed_at IS NULL
        AND NEW.sealed_at IS NOT NULL
        AND (to_jsonb(OLD) - 'sealed_at') = (to_jsonb(NEW) - 'sealed_at')
    THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'approved timesheet pay calculation rows are immutable after creation';
END;
$$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION enforce_timesheet_pay_child_immutability()
RETURNS TRIGGER
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NOT EXISTS (
        SELECT 1 FROM timesheet_pay_calculations calculation
        WHERE calculation.id = NEW.timesheet_pay_calculation_id
            AND calculation.sealed_at IS NOT NULL
    ) THEN
        RETURN NEW;
    END IF;
    RAISE EXCEPTION 'approved timesheet pay child rows are immutable after calculation sealing';
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER enforce_timesheet_pay_calculations_immutable BEFORE UPDATE OR DELETE ON timesheet_pay_calculations FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_pay_calculation_immutability();
CREATE TRIGGER enforce_timesheet_pay_time_segments_immutable BEFORE INSERT OR UPDATE OR DELETE ON timesheet_pay_time_segments FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_pay_child_immutability();
CREATE TRIGGER enforce_timesheet_pay_earnings_components_immutable BEFORE INSERT OR UPDATE OR DELETE ON timesheet_pay_earnings_components FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_pay_child_immutability();
CREATE OR REPLACE FUNCTION prevent_legacy_pay_backfill_grant()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.legacy_pay_backfill_pending = TRUE
        AND (TG_OP = 'INSERT' OR OLD.legacy_pay_backfill_pending = FALSE)
    THEN
        RAISE EXCEPTION 'legacy pay backfill exemption cannot be granted after migration';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER prevent_legacy_pay_backfill_grant BEFORE INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION prevent_legacy_pay_backfill_grant();
CREATE OR REPLACE FUNCTION enforce_timesheet_active_pay_calculation_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM timesheet_entries entry
        WHERE entry.id = NEW.id
            AND (
                (entry.is_approved = FALSE AND entry.active_pay_calculation_id IS NULL AND entry.legacy_pay_backfill_pending = FALSE)
                OR (
                    entry.is_approved = TRUE
                    AND (
                        (entry.legacy_pay_backfill_pending = TRUE AND entry.active_pay_calculation_id IS NULL)
                        OR (
                            entry.legacy_pay_backfill_pending = FALSE
                            AND entry.active_pay_calculation_id IS NOT NULL
                            AND EXISTS (
                                SELECT 1 FROM timesheet_pay_calculations calculation
                                WHERE calculation.id = entry.active_pay_calculation_id
                                    AND calculation.timesheet_entry_id = entry.id
                                    AND calculation.sealed_at IS NOT NULL
                            )
                        )
                    )
                )
            )
    ) THEN
        RAISE EXCEPTION 'timesheet approval requires a sealed same-entry active pay calculation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER enforce_timesheet_active_pay_calculation_integrity AFTER INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_active_pay_calculation_integrity();

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
CREATE TABLE export_job_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    export_job_id UUID NOT NULL,
    timesheet_entry_id UUID NOT NULL,
    staff_pay_version_id UUID NOT NULL,
    shift_type_pay_version_id UUID NOT NULL,
    entry_updated_at_at_export TIMESTAMP WITH TIME ZONE NOT NULL,
    entry_approved_at_at_export TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (export_job_id) REFERENCES export_jobs (id) ON DELETE RESTRICT,
    FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_pay_version_id) REFERENCES staff_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_pay_version_id) REFERENCES shift_type_pay_versions (id) ON DELETE RESTRICT
);

-- schema-nav: xero-submissions
CREATE TABLE xero_submission_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    submitted_by_user_id UUID NOT NULL,
    pay_period_start DATE NOT NULL,
    pay_period_end DATE NOT NULL,
    xero_timesheet_preparation_run_id UUID DEFAULT NULL,
    selected_payroll_calendar_id TEXT DEFAULT NULL,
    selected_payroll_calendar_name TEXT DEFAULT NULL,
    selected_period_key TEXT DEFAULT NULL,
    payment_date DATE DEFAULT NULL,
    xero_pay_run_id TEXT DEFAULT NULL,
    xero_pay_run_status TEXT DEFAULT NULL,
    source_kind xero_submission_source_kind_enum DEFAULT 'approved_timesheets' NOT NULL,
    status xero_submission_run_status_enum DEFAULT 'previewed' NOT NULL,
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
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_timesheet_preparation_runs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    created_by_user_id UUID NOT NULL,
    selected_payroll_calendar_id TEXT DEFAULT NULL,
    selected_payroll_calendar_name TEXT,
    selected_period_key TEXT DEFAULT NULL,
    pay_period_start DATE DEFAULT NULL,
    pay_period_end DATE DEFAULT NULL,
    payment_date DATE,
    xero_pay_run_id TEXT,
    xero_pay_run_status TEXT,
    status xero_timesheet_preparation_run_status_enum DEFAULT 'started' NOT NULL,
    connection_snapshot_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    remote_pay_runs_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    remote_timesheets_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    readiness_snapshot_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    proposed_actions_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    events_json JSONB DEFAULT '[]'::JSONB NOT NULL,
    preview_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    xero_submission_run_id UUID DEFAULT NULL,
    error_summary TEXT DEFAULT NULL,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    completed_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_submission_run_id) REFERENCES xero_submission_runs (id) ON DELETE RESTRICT,
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_timesheet_preparation_decisions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    xero_timesheet_preparation_run_id UUID NOT NULL,
    venue_id UUID NOT NULL,
    xero_connection_id UUID NOT NULL,
    staff_id UUID DEFAULT NULL,
    decision_kind xero_timesheet_preparation_decision_kind_enum NOT NULL,
    decision_status xero_timesheet_preparation_decision_status_enum DEFAULT 'pending' NOT NULL,
    xero_employee_id TEXT,
    xero_employee_name TEXT,
    local_bucket_key TEXT,
    payload_json JSONB DEFAULT '{}'::JSONB NOT NULL,
    decided_by_user_id UUID DEFAULT NULL,
    decided_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (xero_timesheet_preparation_run_id) REFERENCES xero_timesheet_preparation_runs (id) ON DELETE RESTRICT,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (xero_connection_id) REFERENCES xero_connections (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (decided_by_user_id) REFERENCES users (id) ON DELETE RESTRICT
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
    status xero_timesheet_submission_status_enum DEFAULT 'pending' NOT NULL,
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
    CHECK (char_length(idempotency_key) <= 128),
    CHECK (attempt_count >= 0),
    CHECK (pay_period_end >= pay_period_start)
);
CREATE TABLE xero_timesheet_submission_entries (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    xero_timesheet_submission_id UUID NOT NULL,
    timesheet_entry_id UUID NOT NULL,
    staff_pay_version_id UUID NOT NULL,
    shift_type_pay_version_id UUID NOT NULL,
    entry_updated_at_at_preview TIMESTAMP WITH TIME ZONE NOT NULL,
    entry_approved_at_at_preview TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (xero_timesheet_submission_id) REFERENCES xero_timesheet_submissions (id) ON DELETE RESTRICT,
    FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT,
    FOREIGN KEY (staff_pay_version_id) REFERENCES staff_pay_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_pay_version_id) REFERENCES shift_type_pay_versions (id) ON DELETE RESTRICT
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
CREATE INDEX idx_passkey_setup_tokens_user_id ON passkey_setup_tokens (user_id);
CREATE INDEX idx_passkey_setup_tokens_venue_id ON passkey_setup_tokens (venue_id);
CREATE INDEX idx_venue_invitations_venue_status ON venue_invitations (venue_id, status);
CREATE INDEX idx_venue_invitations_email_status ON venue_invitations (email, status);
CREATE INDEX idx_venue_invitations_staff ON venue_invitations (staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX idx_venue_onboarding_invitations_email_status ON venue_onboarding_invitations (email, status);
CREATE UNIQUE INDEX idx_venue_onboarding_invitations_pending_email_unique ON venue_onboarding_invitations (LOWER(email)) WHERE status = 'pending' AND accepted_at IS NULL;
CREATE INDEX idx_staff_venue ON staff (venue_id);
CREATE INDEX idx_staff_default_award_level ON staff (default_award_level_id) WHERE default_award_level_id IS NOT NULL;
CREATE INDEX idx_staff_imported_xero_pay_item ON staff (imported_xero_pay_item_id) WHERE imported_xero_pay_item_id IS NOT NULL;
CREATE UNIQUE INDEX idx_staff_linked_user_per_venue ON staff (venue_id, user_id) WHERE user_id IS NOT NULL AND is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_staff_documents_venue_staff_type_created ON staff_documents (venue_id, staff_id, document_type, created_at DESC);
CREATE INDEX idx_staff_documents_rsa_expiry ON staff_documents (venue_id, expiry_date) WHERE document_type = 'rsa_statement_of_attainment' AND status <> 'rejected';
CREATE UNIQUE INDEX idx_roster_groups_active_name ON roster_groups (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_roster_groups_one_active_default ON roster_groups (venue_id) WHERE is_default = TRUE AND is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_staff_roster_groups_active_assignment ON staff_roster_groups (staff_id, roster_group_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_roster_groups_group_staff ON staff_roster_groups (roster_group_id, staff_id);
CREATE INDEX idx_slot_names_group_sort ON slot_names (roster_group_id, sort_order ASC, created_at ASC);
CREATE UNIQUE INDEX idx_slot_names_active_name ON slot_names (roster_group_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE UNIQUE INDEX idx_shift_types_active_name ON shift_types (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_shift_types_imported_xero_pay_item ON shift_types (imported_xero_pay_item_id) WHERE imported_xero_pay_item_id IS NOT NULL;
CREATE UNIQUE INDEX idx_roster_templates_name ON roster_templates (roster_group_id, LOWER(btrim(name)));
CREATE INDEX idx_roster_templates_group_updated ON roster_templates (roster_group_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_template_designs_one_draft_per_user ON roster_template_designs (draft_owner_user_id) WHERE draft_owner_user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_roster_template_designs_saved_version ON roster_template_designs (template_id, version_number) WHERE template_id IS NOT NULL;
CREATE INDEX idx_roster_template_designs_group ON roster_template_designs (roster_group_id);
CREATE UNIQUE INDEX idx_roster_template_columns_design_name ON roster_template_columns (roster_template_design_id, LOWER(btrim(name)));
CREATE UNIQUE INDEX idx_roster_template_columns_design_sort ON roster_template_columns (roster_template_design_id, sort_order);
CREATE UNIQUE INDEX idx_roster_template_shifts_cell ON roster_template_shifts (roster_template_day_id, row_index, roster_template_column_id);
CREATE INDEX idx_roster_template_shifts_staff ON roster_template_shifts (staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX idx_roster_template_shifts_shift_type ON roster_template_shifts (shift_type_id);
CREATE INDEX idx_roster_weeks_venue_offset ON roster_weeks (venue_id, week_offset);
CREATE INDEX idx_roster_week_slot_definitions_week_sort ON roster_week_slot_definitions (roster_week_id, sort_order ASC, created_at ASC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_week_slot_definitions_active_name ON roster_week_slot_definitions (roster_week_id, name) WHERE deleted_at IS NULL;
CREATE INDEX idx_roster_slots_day ON roster_slots (roster_day_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_roster_slots_staff ON roster_slots (staff_id) WHERE staff_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_roster_slots_shift_type ON roster_slots (shift_type_id) WHERE shift_type_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_roster_notification_runs_group_week_created ON roster_notification_runs (roster_group_id, week_offset, created_at DESC);
CREATE UNIQUE INDEX idx_roster_slots_active_cell ON roster_slots (roster_day_id, row_index, roster_week_slot_definition_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_pay_versions_staff_effective ON staff_pay_versions (staff_id, effective_from DESC, created_at DESC);
CREATE UNIQUE INDEX idx_staff_pay_versions_one_open ON staff_pay_versions (staff_id) WHERE effective_to IS NULL;
CREATE INDEX idx_staff_pay_versions_imported_xero_pay_item ON staff_pay_versions (imported_xero_pay_item_id) WHERE imported_xero_pay_item_id IS NOT NULL;
CREATE INDEX idx_shift_type_pay_versions_shift_effective ON shift_type_pay_versions (shift_type_id, effective_from DESC, created_at DESC);
CREATE UNIQUE INDEX idx_shift_type_pay_versions_one_open ON shift_type_pay_versions (shift_type_id) WHERE effective_to IS NULL;
CREATE INDEX idx_shift_type_pay_versions_imported_xero_pay_item ON shift_type_pay_versions (imported_xero_pay_item_id) WHERE imported_xero_pay_item_id IS NOT NULL;
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
CREATE UNIQUE INDEX idx_public_holidays_unique_null_safe ON public_holidays (jurisdiction, holiday_date, name, COALESCE(region, ''));
CREATE INDEX idx_app_jobs_pending ON app_jobs (status, run_at, created_at);
CREATE INDEX idx_app_jobs_kind_created_at ON app_jobs (job_kind, created_at DESC);
CREATE INDEX idx_app_jobs_venue_created_at ON app_jobs (venue_id, created_at DESC);
CREATE INDEX idx_app_jobs_related ON app_jobs (related_table, related_id);
CREATE UNIQUE INDEX idx_app_jobs_active_dedupe ON app_jobs (dedupe_key) WHERE dedupe_key IS NOT NULL AND (status = 'job_status_not_started' OR status = 'job_status_running' OR status = 'job_status_retry');
CREATE INDEX idx_timesheet_entries_venue_staff ON timesheet_entries (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_timesheet_entries_venue_starts_at ON timesheet_entries (venue_id, starts_at) WHERE deleted_at IS NULL;
CREATE INDEX idx_timesheet_entries_staff_pay_version ON timesheet_entries (staff_pay_version_id);
CREATE INDEX idx_timesheet_entries_shift_type_pay_version ON timesheet_entries (shift_type_pay_version_id);
CREATE UNIQUE INDEX idx_timesheet_entries_source_roster_slot ON timesheet_entries (source_roster_slot_id) WHERE source_roster_slot_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX idx_timesheet_entry_versions_entry_created_at ON timesheet_entry_versions (timesheet_entry_id, created_at DESC);
CREATE INDEX idx_leave_requests_venue_staff ON leave_requests (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_requests_venue_start_date ON leave_requests (venue_id, start_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_requests_venue_status_staff_dates ON leave_requests (venue_id, status, staff_id, start_date, end_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_leave_request_events_request_created_at ON leave_request_events (leave_request_id, created_at DESC);
CREATE INDEX idx_staff_shift_preferences_venue_staff ON staff_shift_preferences (venue_id, staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_shift_preferences_staff ON staff_shift_preferences (staff_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_staff_shift_preferences_venue_day ON staff_shift_preferences (venue_id, weekday_index) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_staff_shift_preferences_active_unique ON staff_shift_preferences (staff_id, weekday_index) WHERE deleted_at IS NULL;
CREATE INDEX idx_audit_events_venue_created_at ON audit_events (venue_id, created_at DESC);
CREATE INDEX idx_audit_events_target ON audit_events (target_table, target_id);
CREATE INDEX idx_export_jobs_venue_created_at ON export_jobs (venue_id, created_at DESC);
CREATE INDEX idx_export_job_entries_export ON export_job_entries (export_job_id);
CREATE UNIQUE INDEX idx_export_job_entries_unique_entry ON export_job_entries (export_job_id, timesheet_entry_id);
CREATE INDEX idx_venue_membership_role_events_membership_created_at ON venue_membership_role_events (venue_membership_id, created_at DESC);
CREATE UNIQUE INDEX idx_export_jobs_generated_file_id ON export_jobs (generated_file_id);
CREATE UNIQUE INDEX idx_export_jobs_download_token ON export_jobs (download_token);
CREATE INDEX idx_venue_billing_customers_venue ON venue_billing_customers (venue_id);
CREATE UNIQUE INDEX idx_billing_checkout_attempts_one_open_per_venue ON billing_checkout_attempts (venue_id) WHERE status = 'open';
CREATE INDEX idx_billing_checkout_attempts_venue_created_at ON billing_checkout_attempts (venue_id, created_at DESC);
CREATE INDEX idx_billing_checkout_attempts_subscription ON billing_checkout_attempts (stripe_subscription_id) WHERE stripe_subscription_id IS NOT NULL;
CREATE INDEX idx_venue_subscriptions_venue_status ON venue_subscriptions (venue_id, status);
CREATE INDEX idx_billing_events_received_at ON billing_events (received_at DESC);
CREATE INDEX idx_billing_events_stripe_created_at ON billing_events (stripe_created_at, stripe_event_id) WHERE stripe_created_at IS NOT NULL;
CREATE INDEX idx_billing_events_status_received_at ON billing_events (status, received_at);
CREATE INDEX idx_billing_events_venue_received_at ON billing_events (venue_id, received_at DESC) WHERE venue_id IS NOT NULL;
CREATE INDEX idx_billing_events_provider_object ON billing_events (provider_object_type, provider_object_id) WHERE provider_object_id IS NOT NULL;
CREATE INDEX idx_venue_billing_controls_manual_read_only ON venue_billing_controls (manual_read_only) WHERE manual_read_only = TRUE;
CREATE INDEX idx_xero_connections_venue_created_at ON xero_connections (venue_id, created_at DESC);
CREATE INDEX idx_xero_connections_remote_id ON xero_connections (xero_connection_remote_id);
CREATE UNIQUE INDEX idx_xero_connections_active_venue ON xero_connections (venue_id) WHERE connection_status = 'active';
CREATE INDEX idx_xero_oauth_states_token ON xero_oauth_states (state_token);
CREATE INDEX idx_xero_oauth_states_venue_user_created_at ON xero_oauth_states (venue_id, user_id, created_at DESC);
CREATE INDEX idx_xero_sync_runs_venue_started_at ON xero_sync_runs (venue_id, started_at DESC);
CREATE UNIQUE INDEX idx_xero_employees_connection_employee ON xero_employees (xero_connection_id, xero_employee_id);
CREATE INDEX idx_xero_employees_venue_name ON xero_employees (venue_id, display_name) WHERE provider_available = TRUE;
CREATE UNIQUE INDEX idx_xero_earnings_rates_connection_rate ON xero_earnings_rates (xero_connection_id, xero_earnings_rate_id);
CREATE INDEX idx_xero_earnings_rates_venue_name ON xero_earnings_rates (venue_id, name) WHERE provider_available = TRUE;
CREATE UNIQUE INDEX idx_xero_imported_pay_items_active_remote ON xero_imported_pay_items (xero_connection_id, xero_earnings_rate_id) WHERE archived_at IS NULL;
CREATE INDEX idx_xero_imported_pay_items_venue_active_name ON xero_imported_pay_items (venue_id, name) WHERE archived_at IS NULL AND provider_available = TRUE;
CREATE INDEX idx_xero_imported_pay_items_venue_archived ON xero_imported_pay_items (venue_id, archived_at DESC) WHERE archived_at IS NOT NULL;
CREATE UNIQUE INDEX idx_xero_accounts_connection_account ON xero_accounts (xero_connection_id, xero_account_id);
CREATE INDEX idx_xero_accounts_connection_code ON xero_accounts (xero_connection_id, code);
CREATE INDEX idx_xero_accounts_venue_type_status ON xero_accounts (venue_id, account_type, status) WHERE provider_available = TRUE;
CREATE UNIQUE INDEX idx_xero_payroll_calendars_connection_calendar ON xero_payroll_calendars (xero_connection_id, xero_payroll_calendar_id);
CREATE INDEX idx_xero_payroll_calendars_venue_name ON xero_payroll_calendars (venue_id, name) WHERE provider_available = TRUE;
CREATE UNIQUE INDEX idx_xero_pay_runs_connection_pay_run ON xero_pay_runs (xero_connection_id, xero_pay_run_id);
CREATE INDEX idx_xero_pay_runs_connection_calendar_period ON xero_pay_runs (xero_connection_id, xero_payroll_calendar_id, pay_period_start, pay_period_end);
CREATE INDEX idx_xero_pay_runs_venue_period ON xero_pay_runs (venue_id, pay_period_start DESC, pay_period_end DESC);
CREATE UNIQUE INDEX idx_xero_staff_mappings_staff_connection ON xero_staff_mappings (staff_id, xero_connection_id);
CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee ON xero_staff_mappings (xero_connection_id, xero_employee_id) WHERE mapping_status = 'verified' AND xero_employee_id IS NOT NULL;
CREATE INDEX idx_xero_staff_mappings_venue_status ON xero_staff_mappings (venue_id, mapping_status);
CREATE UNIQUE INDEX idx_xero_earnings_rate_mappings_bucket_connection ON xero_earnings_rate_mappings (xero_connection_id, local_bucket_key);
CREATE INDEX idx_xero_earnings_rate_mappings_venue_status ON xero_earnings_rate_mappings (venue_id, mapping_status);
CREATE UNIQUE INDEX idx_xero_pay_item_account_code_selections_connection ON xero_pay_item_account_code_selections (xero_connection_id);
CREATE UNIQUE INDEX idx_xero_pay_item_requirement_records_connection_key ON xero_pay_item_requirement_records (xero_connection_id, requirement_key);
CREATE INDEX idx_xero_pay_item_requirement_records_venue_status ON xero_pay_item_requirement_records (venue_id, requirement_status);
ALTER TABLE venue_invitations ADD CONSTRAINT venue_invitations_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT;
ALTER TABLE staff ADD CONSTRAINT staff_imported_xero_pay_item_id_fk FOREIGN KEY (imported_xero_pay_item_id) REFERENCES xero_imported_pay_items (id) ON DELETE RESTRICT;
ALTER TABLE shift_types ADD CONSTRAINT shift_types_imported_xero_pay_item_id_fk FOREIGN KEY (imported_xero_pay_item_id) REFERENCES xero_imported_pay_items (id) ON DELETE RESTRICT;
ALTER TABLE staff_pay_versions ADD CONSTRAINT staff_pay_versions_imported_xero_pay_item_id_fk FOREIGN KEY (imported_xero_pay_item_id) REFERENCES xero_imported_pay_items (id) ON DELETE RESTRICT;
ALTER TABLE shift_type_pay_versions ADD CONSTRAINT shift_type_pay_versions_imported_xero_pay_item_id_fk FOREIGN KEY (imported_xero_pay_item_id) REFERENCES xero_imported_pay_items (id) ON DELETE RESTRICT;
ALTER TABLE xero_submission_runs ADD CONSTRAINT xero_submission_runs_preparation_run_id_fk FOREIGN KEY (xero_timesheet_preparation_run_id) REFERENCES xero_timesheet_preparation_runs (id) ON DELETE RESTRICT;
CREATE INDEX idx_xero_submission_runs_connection_period ON xero_submission_runs (xero_connection_id, pay_period_start, pay_period_end);
CREATE INDEX idx_xero_submission_runs_preparation ON xero_submission_runs (xero_timesheet_preparation_run_id) WHERE xero_timesheet_preparation_run_id IS NOT NULL;
CREATE INDEX idx_xero_timesheet_preparation_runs_connection_period ON xero_timesheet_preparation_runs (xero_connection_id, pay_period_start, pay_period_end);
CREATE INDEX idx_xero_timesheet_preparation_runs_venue_created ON xero_timesheet_preparation_runs (venue_id, created_at DESC);
CREATE INDEX idx_xero_timesheet_preparation_decisions_run_kind_status ON xero_timesheet_preparation_decisions (xero_timesheet_preparation_run_id, decision_kind, decision_status);
CREATE INDEX idx_xero_timesheet_preparation_decisions_run_staff ON xero_timesheet_preparation_decisions (xero_timesheet_preparation_run_id, staff_id);
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

CREATE OR REPLACE FUNCTION enforce_roster_notification_run_immutability()
RETURNS TRIGGER
AS $$
BEGIN
    RAISE EXCEPTION 'roster notification runs are immutable retained communication records';
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_xero_imported_pay_item_identity_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.venue_id IS DISTINCT FROM OLD.venue_id
        OR NEW.xero_connection_id IS DISTINCT FROM OLD.xero_connection_id
        OR NEW.xero_earnings_rate_id IS DISTINCT FROM OLD.xero_earnings_rate_id
    THEN
        RAISE EXCEPTION 'imported Xero pay item identity is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_locked_staff_pay_version_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND (
            NEW.pay_assignment_mode IS DISTINCT FROM OLD.pay_assignment_mode
            OR NEW.default_award_level_id IS DISTINCT FROM OLD.default_award_level_id
            OR NEW.imported_xero_pay_item_id IS DISTINCT FROM OLD.imported_xero_pay_item_id
        )
    THEN
        RAISE EXCEPTION 'locked staff pay assignment is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_locked_shift_pay_version_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND (
            NEW.pay_assignment_mode IS DISTINCT FROM OLD.pay_assignment_mode
            OR NEW.override_award_level_id IS DISTINCT FROM OLD.override_award_level_id
            OR NEW.imported_xero_pay_item_id IS DISTINCT FROM OLD.imported_xero_pay_item_id
        )
    THEN
        RAISE EXCEPTION 'locked shift pay assignment is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_locked_shift_pay_version_label_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND NEW.payroll_label IS DISTINCT FROM OLD.payroll_label
    THEN
        RAISE EXCEPTION 'locked shift pay version payroll label is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_hard_delete_venues BEFORE DELETE ON venues FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_users BEFORE DELETE ON users FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_venue_memberships BEFORE DELETE ON venue_memberships FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff BEFORE DELETE ON staff FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff_documents BEFORE DELETE ON staff_documents FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff_roster_groups BEFORE DELETE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_roster_groups BEFORE DELETE ON roster_groups FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_slot_names BEFORE DELETE ON slot_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_day_names BEFORE DELETE ON day_names FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_shift_types BEFORE DELETE ON shift_types FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_venue_config BEFORE DELETE ON venue_config FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_staff_pay_versions BEFORE DELETE ON staff_pay_versions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_shift_type_pay_versions BEFORE DELETE ON shift_type_pay_versions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_locked_staff_pay_version_imported_item_update BEFORE UPDATE ON staff_pay_versions FOR EACH ROW EXECUTE FUNCTION prevent_locked_staff_pay_version_change();
CREATE TRIGGER prevent_locked_shift_pay_version_imported_item_update BEFORE UPDATE ON shift_type_pay_versions FOR EACH ROW EXECUTE FUNCTION prevent_locked_shift_pay_version_change();
CREATE TRIGGER prevent_locked_shift_pay_version_payroll_label_update BEFORE UPDATE ON shift_type_pay_versions FOR EACH ROW EXECUTE FUNCTION prevent_locked_shift_pay_version_label_change();
CREATE TRIGGER prevent_hard_delete_roster_weeks BEFORE DELETE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER enforce_roster_notification_runs_immutable BEFORE UPDATE OR DELETE ON roster_notification_runs FOR EACH ROW EXECUTE FUNCTION enforce_roster_notification_run_immutability();
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
CREATE TRIGGER prevent_hard_delete_export_job_entries BEFORE DELETE ON export_job_entries FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_connections BEFORE DELETE ON xero_connections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_sync_runs BEFORE DELETE ON xero_sync_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_employees BEFORE DELETE ON xero_employees FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_earnings_rates BEFORE DELETE ON xero_earnings_rates FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_imported_pay_items BEFORE DELETE ON xero_imported_pay_items FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_xero_imported_pay_item_identity_update BEFORE UPDATE ON xero_imported_pay_items FOR EACH ROW EXECUTE FUNCTION prevent_xero_imported_pay_item_identity_change();
CREATE TRIGGER prevent_hard_delete_xero_accounts BEFORE DELETE ON xero_accounts FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_payroll_calendars BEFORE DELETE ON xero_payroll_calendars FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_pay_runs BEFORE DELETE ON xero_pay_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_staff_mappings BEFORE DELETE ON xero_staff_mappings FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_earnings_rate_mappings BEFORE DELETE ON xero_earnings_rate_mappings FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_pay_item_account_code_selections BEFORE DELETE ON xero_pay_item_account_code_selections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_pay_item_requirement_records BEFORE DELETE ON xero_pay_item_requirement_records FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_submission_runs BEFORE DELETE ON xero_submission_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_timesheet_preparation_runs BEFORE DELETE ON xero_timesheet_preparation_runs FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_timesheet_preparation_decisions BEFORE DELETE ON xero_timesheet_preparation_decisions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
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

CREATE OR REPLACE FUNCTION prevent_saved_roster_template_design_mutation()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.draft_owner_user_id IS NULL THEN
        RAISE EXCEPTION 'saved roster template versions are immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_saved_roster_template_content_mutation()
RETURNS TRIGGER
AS $$
DECLARE
    old_design_id UUID;
    new_design_id UUID;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        old_design_id := OLD.roster_template_design_id;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        new_design_id := NEW.roster_template_design_id;
    END IF;
    IF TG_OP = 'INSERT' AND EXISTS (
        SELECT 1
        FROM roster_template_designs d
        JOIN roster_templates t ON t.id = d.template_id
        WHERE d.id = new_design_id
          AND d.draft_owner_user_id IS NULL
          AND d.version_number = t.current_version + 1
    ) THEN
        RETURN NEW;
    END IF;
    IF EXISTS (
        SELECT 1 FROM roster_template_designs d
        WHERE (d.id = old_design_id OR d.id = new_design_id)
          AND d.draft_owner_user_id IS NULL
    ) THEN
        RAISE EXCEPTION 'sealed roster template version content is immutable';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_template_integrity()
RETURNS TRIGGER
AS $$
DECLARE
    design_group_id UUID;
    design_scale TEXT;
    group_venue_id UUID;
BEGIN
    IF TG_TABLE_NAME = 'roster_template_days' THEN
        SELECT roster_group_id, scale INTO design_group_id, design_scale
        FROM roster_template_designs WHERE id = NEW.roster_template_design_id;
        IF design_scale = 'day' AND NEW.day_index <> 0 THEN
            RAISE EXCEPTION 'day roster templates may contain only day index zero';
        END IF;
        RETURN NEW;
    END IF;

    SELECT d.roster_group_id, d.scale, rg.venue_id
    INTO design_group_id, design_scale, group_venue_id
    FROM roster_template_designs d
    JOIN roster_groups rg ON rg.id = d.roster_group_id
    WHERE d.id = NEW.roster_template_design_id;

    IF NOT EXISTS (
        SELECT 1
        FROM roster_template_days d
        JOIN roster_template_columns c ON c.roster_template_design_id = d.roster_template_design_id
        WHERE d.id = NEW.roster_template_day_id
          AND c.id = NEW.roster_template_column_id
          AND d.roster_template_design_id = NEW.roster_template_design_id
    ) THEN
        RAISE EXCEPTION 'roster template shift content must belong to one design';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM shift_types st
        WHERE st.id = NEW.shift_type_id AND st.venue_id = group_venue_id
    ) THEN
        RAISE EXCEPTION 'roster template shift type must stay within template venue';
    END IF;

    IF NEW.staff_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM staff s
        WHERE s.id = NEW.staff_id AND s.venue_id = group_venue_id
    ) THEN
        RAISE EXCEPTION 'roster template staff assignment must stay within template venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_template_design_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.template_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM roster_templates t
        WHERE t.id = NEW.template_id
          AND t.roster_group_id = NEW.roster_group_id
          AND t.scale = NEW.scale
    ) THEN
        RAISE EXCEPTION 'saved roster template design must match template group and scale';
    END IF;

    IF NEW.source_template_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM roster_templates t
        JOIN roster_template_designs d
          ON d.template_id = t.id AND d.version_number = NEW.base_version_number
        WHERE t.id = NEW.source_template_id
          AND t.roster_group_id = NEW.roster_group_id
          AND t.scale = NEW.scale
    ) THEN
        RAISE EXCEPTION 'roster template draft source version must match group and scale';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_slot_week_definition_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM roster_days rd
        JOIN roster_week_slot_definitions rwsd ON rwsd.id = NEW.roster_week_slot_definition_id
        WHERE rd.id = NEW.roster_day_id
            AND rd.roster_week_id = rwsd.roster_week_id
    ) THEN
        RAISE EXCEPTION 'roster slot day and slot definition must belong to the same roster week';
    END IF;

    IF NEW.shift_type_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_days rd
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            JOIN shift_types st ON st.id = NEW.shift_type_id
            WHERE rd.id = NEW.roster_day_id
                AND st.venue_id = rw.venue_id
        )
    THEN
        RAISE EXCEPTION 'roster slot shift_type_id must stay within roster week venue';
    END IF;

    IF NEW.staff_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_days rd
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            JOIN staff s ON s.id = NEW.staff_id
            WHERE rd.id = NEW.roster_day_id
                AND s.venue_id = rw.venue_id
        )
    THEN
        RAISE EXCEPTION 'roster slot staff_id must stay within roster week venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_venue_invitation_staff_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.staff_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'venue invitation staff_id must match invitation venue';
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
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff shift preference staff must stay within its venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_document_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff document venue_id must match staff_id venue';
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

    IF NEW.staff_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM staff_pay_versions spv
            WHERE spv.id = NEW.staff_pay_version_id
                AND spv.venue_id = NEW.venue_id
                AND spv.staff_id = NEW.staff_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry staff_pay_version_id must match entry staff and venue';
    END IF;

    IF NEW.shift_type_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM shift_type_pay_versions stpv
            WHERE stpv.id = NEW.shift_type_pay_version_id
                AND stpv.venue_id = NEW.venue_id
                AND stpv.shift_type_id = NEW.shift_type_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry shift_type_pay_version_id must match entry shift type and venue';
    END IF;

    IF NEW.source_roster_slot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_slots rs
            JOIN roster_days rd ON rd.id = rs.roster_day_id
            JOIN roster_weeks rw ON rw.id = rd.roster_week_id
            WHERE rs.id = NEW.source_roster_slot_id
                AND rw.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry source_roster_slot_id must stay within entry venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF (OLD.source_roster_slot_id IS NOT NULL OR NEW.source_roster_slot_id IS NOT NULL)
        AND (
            NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id
            OR (NEW.starts_at AT TIME ZONE NEW.timezone)::DATE IS DISTINCT FROM (OLD.starts_at AT TIME ZONE OLD.timezone)::DATE
            OR NEW.timezone IS DISTINCT FROM OLD.timezone
        )
    THEN
        RAISE EXCEPTION 'roster-derived timesheet local date, timezone and source are immutable';
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

CREATE OR REPLACE FUNCTION enforce_imported_xero_pay_item_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.imported_xero_pay_item_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM xero_imported_pay_items xipi
            WHERE xipi.id = NEW.imported_xero_pay_item_id
                AND xipi.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'imported_xero_pay_item_id venue_id must match row venue';
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

CREATE OR REPLACE FUNCTION enforce_xero_preparation_decision_venue_integrity()
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
        FROM xero_timesheet_preparation_runs run
        WHERE run.id = NEW.xero_timesheet_preparation_run_id
            AND run.venue_id = NEW.venue_id
            AND run.xero_connection_id = NEW.xero_connection_id
    ) THEN
        RAISE EXCEPTION 'xero preparation decision must match preparation run venue and connection';
    END IF;

    IF NEW.staff_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero preparation decision venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_saved_roster_template_design_mutation BEFORE UPDATE OR DELETE ON roster_template_designs FOR EACH ROW EXECUTE FUNCTION prevent_saved_roster_template_design_mutation();
CREATE TRIGGER prevent_saved_roster_template_days_mutation BEFORE INSERT OR UPDATE OR DELETE ON roster_template_days FOR EACH ROW EXECUTE FUNCTION prevent_saved_roster_template_content_mutation();
CREATE TRIGGER prevent_saved_roster_template_columns_mutation BEFORE INSERT OR UPDATE OR DELETE ON roster_template_columns FOR EACH ROW EXECUTE FUNCTION prevent_saved_roster_template_content_mutation();
CREATE TRIGGER prevent_saved_roster_template_shifts_mutation BEFORE INSERT OR UPDATE OR DELETE ON roster_template_shifts FOR EACH ROW EXECUTE FUNCTION prevent_saved_roster_template_content_mutation();
CREATE TRIGGER enforce_roster_template_design_integrity BEFORE INSERT OR UPDATE ON roster_template_designs FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_design_integrity();
CREATE TRIGGER enforce_roster_template_day_integrity BEFORE INSERT OR UPDATE ON roster_template_days FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_integrity();
CREATE TRIGGER enforce_roster_template_shift_integrity BEFORE INSERT OR UPDATE ON roster_template_shifts FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_integrity();
CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION enforce_roster_week_venue_integrity();
CREATE TRIGGER enforce_slot_name_venue_integrity BEFORE INSERT OR UPDATE ON slot_names FOR EACH ROW EXECUTE FUNCTION enforce_slot_name_venue_integrity();
CREATE TRIGGER enforce_roster_slot_week_definition_integrity BEFORE INSERT OR UPDATE ON roster_slots FOR EACH ROW EXECUTE FUNCTION enforce_roster_slot_week_definition_integrity();
CREATE TRIGGER enforce_venue_invitation_staff_venue_integrity BEFORE INSERT OR UPDATE ON venue_invitations FOR EACH ROW EXECUTE FUNCTION enforce_venue_invitation_staff_venue_integrity();
CREATE TRIGGER enforce_staff_roster_group_venue_integrity BEFORE INSERT OR UPDATE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION enforce_staff_roster_group_venue_integrity();
CREATE TRIGGER enforce_staff_shift_preference_venue_integrity BEFORE INSERT OR UPDATE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION enforce_staff_shift_preference_venue_integrity();
CREATE TRIGGER enforce_staff_document_venue_integrity BEFORE INSERT OR UPDATE ON staff_documents FOR EACH ROW EXECUTE FUNCTION enforce_staff_document_venue_integrity();
CREATE TRIGGER enforce_leave_request_venue_integrity BEFORE INSERT OR UPDATE ON leave_requests FOR EACH ROW EXECUTE FUNCTION enforce_leave_request_venue_integrity();
CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_entry_venue_integrity();
CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable BEFORE UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_roster_derived_timesheet_identity_immutable();
CREATE TRIGGER enforce_xero_sync_runs_venue_integrity BEFORE INSERT OR UPDATE ON xero_sync_runs FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_employees_venue_integrity BEFORE INSERT OR UPDATE ON xero_employees FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_staff_xero_pay_item_venue BEFORE INSERT OR UPDATE ON staff FOR EACH ROW EXECUTE FUNCTION enforce_imported_xero_pay_item_venue_integrity();
CREATE TRIGGER enforce_shift_types_xero_pay_item_venue BEFORE INSERT OR UPDATE ON shift_types FOR EACH ROW EXECUTE FUNCTION enforce_imported_xero_pay_item_venue_integrity();
CREATE TRIGGER enforce_staff_pay_versions_xero_pay_item_venue BEFORE INSERT OR UPDATE ON staff_pay_versions FOR EACH ROW EXECUTE FUNCTION enforce_imported_xero_pay_item_venue_integrity();
CREATE TRIGGER enforce_shift_pay_versions_xero_pay_item_venue BEFORE INSERT OR UPDATE ON shift_type_pay_versions FOR EACH ROW EXECUTE FUNCTION enforce_imported_xero_pay_item_venue_integrity();
CREATE TRIGGER enforce_xero_earnings_rates_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rates FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_imported_pay_items_venue_integrity BEFORE INSERT OR UPDATE ON xero_imported_pay_items FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_accounts_venue_integrity BEFORE INSERT OR UPDATE ON xero_accounts FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_payroll_calendars_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendars FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_pay_runs_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_runs FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_staff_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_staff_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_staff_mapping_venue_integrity();
CREATE TRIGGER enforce_xero_earnings_rate_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rate_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_pay_item_account_code_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_account_code_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_pay_item_requirement_records_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_requirement_records FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_timesheet_preparation_runs_venue_integrity BEFORE INSERT OR UPDATE ON xero_timesheet_preparation_runs FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
CREATE TRIGGER enforce_xero_timesheet_preparation_decisions_venue_integrity BEFORE INSERT OR UPDATE ON xero_timesheet_preparation_decisions FOR EACH ROW EXECUTE FUNCTION enforce_xero_preparation_decision_venue_integrity();

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

CREATE OR REPLACE FUNCTION venue_effective_award_rate_from(p_week_starts_on INT, p_operative_from DATE)
RETURNS DATE
AS $$
    SELECT CASE
        WHEN p_operative_from IS NULL THEN NULL
        ELSE p_operative_from + (((p_week_starts_on - EXTRACT(DOW FROM p_operative_from)::INT + 7) % 7)::INT)
    END;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION venue_effective_award_rate_to(p_week_starts_on INT, p_operative_to DATE)
RETURNS DATE
AS $$
    SELECT CASE
        WHEN p_operative_to IS NULL THEN NULL
        ELSE venue_effective_award_rate_from(p_week_starts_on, p_operative_to + 1) - 1
    END;
$$ LANGUAGE SQL;
