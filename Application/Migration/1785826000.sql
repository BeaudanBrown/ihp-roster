-- Roster template persistence for GitHub #307.
-- Additive only: existing customer roster data is not changed.

CREATE TABLE roster_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_group_id UUID NOT NULL,
    name TEXT NOT NULL,
    scale TEXT NOT NULL,
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
    CHECK (scale = 'day' OR scale = 'week'),
    CHECK (current_version >= 0)
);

CREATE TABLE roster_template_designs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_group_id UUID NOT NULL,
    scale TEXT NOT NULL,
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
    CHECK (scale = 'day' OR scale = 'week'),
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

CREATE UNIQUE INDEX idx_roster_templates_active_name ON roster_templates (roster_group_id, LOWER(btrim(name))) WHERE deleted_at IS NULL;
CREATE INDEX idx_roster_templates_group_updated ON roster_templates (roster_group_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_template_designs_one_draft_per_user ON roster_template_designs (draft_owner_user_id) WHERE draft_owner_user_id IS NOT NULL;
CREATE UNIQUE INDEX idx_roster_template_designs_saved_version ON roster_template_designs (template_id, version_number) WHERE template_id IS NOT NULL;
CREATE INDEX idx_roster_template_designs_group ON roster_template_designs (roster_group_id);
CREATE UNIQUE INDEX idx_roster_template_columns_design_name ON roster_template_columns (roster_template_design_id, LOWER(btrim(name)));
CREATE UNIQUE INDEX idx_roster_template_columns_design_sort ON roster_template_columns (roster_template_design_id, sort_order);
CREATE UNIQUE INDEX idx_roster_template_shifts_cell ON roster_template_shifts (roster_template_day_id, row_index, roster_template_column_id);
CREATE INDEX idx_roster_template_shifts_staff ON roster_template_shifts (staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX idx_roster_template_shifts_shift_type ON roster_template_shifts (shift_type_id);

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

CREATE TRIGGER enforce_roster_template_design_integrity BEFORE INSERT OR UPDATE ON roster_template_designs FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_design_integrity();
CREATE TRIGGER enforce_roster_template_day_integrity BEFORE INSERT OR UPDATE ON roster_template_days FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_integrity();
CREATE TRIGGER enforce_roster_template_shift_integrity BEFORE INSERT OR UPDATE ON roster_template_shifts FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_integrity();
