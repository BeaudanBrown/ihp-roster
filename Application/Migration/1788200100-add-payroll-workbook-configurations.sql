-- Additive persistence for venue-scoped named Payroll Workbook definitions.
-- Generated export jobs retain independent JSON snapshots and intentionally
-- have no foreign key to these removable configuration rows.
CREATE TABLE payroll_workbook_configurations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    name TEXT NOT NULL,
    definition_version INT DEFAULT 1 NOT NULL,
    created_by_user_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 100) AND (name = regexp_replace(btrim(name), '[[:space:]]+', ' ', 'g'))),
    CHECK (definition_version = 1)
);
CREATE UNIQUE INDEX payroll_workbook_configurations_venue_name_idx ON payroll_workbook_configurations (venue_id, lower(name));

CREATE TABLE payroll_workbook_configuration_families (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    configuration_id UUID NOT NULL,
    family_key TEXT NOT NULL,
    position INT NOT NULL,
    FOREIGN KEY (configuration_id) REFERENCES payroll_workbook_configurations (id) ON DELETE CASCADE,
    UNIQUE(configuration_id, position),
    UNIQUE(configuration_id, family_key),
    CHECK ((family_key = 'summary') OR (family_key = 'employee-pay-bucket-hours') OR (family_key = 'shift-type-hours') OR (family_key = 'employee-pay-bucket-wages') OR (family_key = 'shift-type-wages')),
    CHECK ((position >= 0) AND (position < 5))
);
