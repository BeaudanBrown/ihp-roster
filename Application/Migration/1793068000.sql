-- Add reusable venue recipient groups without converting legacy schedules or
-- modifying existing recipient snapshots. No time-conversion backfill.
CREATE TABLE recipient_groups (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    recipients TEXT[] NOT NULL,
    revision INT DEFAULT 0 NOT NULL,
    created_by_user_id UUID NOT NULL,
    updated_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    archived_at TIMESTAMP WITH TIME ZONE,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 100) AND (name = regexp_replace(btrim(name), '[[:space:]]+', ' ', 'g'))),
    CHECK ((cardinality(recipients) > 0) AND (cardinality(recipients) <= 50)),
    CHECK (revision >= 0)
);
CREATE UNIQUE INDEX recipient_groups_venue_name_idx ON recipient_groups (venue_id, lower(name)) WHERE archived_at IS NULL;
ALTER TABLE payroll_report_settings ADD COLUMN recipient_group_id UUID;
ALTER TABLE payroll_report_settings ADD CONSTRAINT payroll_report_settings_recipient_group_fkey FOREIGN KEY (recipient_group_id) REFERENCES recipient_groups (id) ON DELETE RESTRICT;
