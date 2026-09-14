-- Replace the unused draft/version template product with direct snapshot storage.
-- The operator confirmed that no customer template rows exist and explicitly
-- requires old draft/version content not to be migrated. Abort rather than
-- discard data if that production precondition is false.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM roster_templates)
        OR EXISTS (SELECT 1 FROM roster_template_designs)
        OR EXISTS (SELECT 1 FROM roster_template_days)
        OR EXISTS (SELECT 1 FROM roster_template_columns)
        OR EXISTS (SELECT 1 FROM roster_template_shifts) THEN
        RAISE EXCEPTION 'roster template snapshot cutover requires all legacy template tables to be empty';
    END IF;
END;
$$;

DROP TABLE roster_template_shifts;
DROP TABLE roster_template_columns;
DROP TABLE roster_template_days;
DROP TABLE roster_template_designs;
DROP TABLE roster_templates;
DROP FUNCTION IF EXISTS prevent_saved_roster_template_design_mutation();
DROP FUNCTION IF EXISTS prevent_saved_roster_template_content_mutation();
DROP FUNCTION IF EXISTS enforce_roster_template_integrity();
DROP FUNCTION IF EXISTS enforce_roster_template_design_integrity();

CREATE TABLE roster_templates (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_group_id UUID NOT NULL,
    name TEXT NOT NULL,
    scale roster_template_scale_enum NOT NULL,
    completion_id UUID DEFAULT uuid_generate_v4() NOT NULL,
    created_by_user_id UUID NOT NULL,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    deleted_by_user_id UUID DEFAULT NULL,
    delete_reason TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (deleted_by_user_id) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (name = btrim(name))
);

CREATE TABLE roster_template_days (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_id UUID NOT NULL,
    day_index INT NOT NULL,
    weekday_index INT DEFAULT NULL,
    is_closed BOOLEAN DEFAULT FALSE NOT NULL,
    row_count INT DEFAULT 4 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    UNIQUE(roster_template_id, day_index),
    FOREIGN KEY (roster_template_id) REFERENCES roster_templates (id) ON DELETE CASCADE,
    CHECK ((day_index >= 0) AND (day_index <= 6)),
    CHECK (weekday_index IS NULL OR ((weekday_index >= 0) AND (weekday_index <= 6))),
    CHECK (row_count >= 0)
);

CREATE TABLE roster_template_columns (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_id UUID NOT NULL,
    name TEXT NOT NULL,
    sort_order INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_template_id) REFERENCES roster_templates (id) ON DELETE CASCADE,
    CHECK ((char_length(btrim(name)) > 0) AND (char_length(name) <= 120)),
    CHECK (name = btrim(name)),
    CHECK (sort_order >= 0)
);

CREATE TABLE roster_template_shifts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    roster_template_id UUID NOT NULL,
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
    FOREIGN KEY (roster_template_id) REFERENCES roster_templates (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_template_day_id) REFERENCES roster_template_days (id) ON DELETE CASCADE,
    FOREIGN KEY (roster_template_column_id) REFERENCES roster_template_columns (id) ON DELETE CASCADE,
    FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT,
    FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT
);

CREATE TABLE roster_template_completions (
    id UUID PRIMARY KEY NOT NULL,
    roster_template_id UUID UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (roster_template_id) REFERENCES roster_templates (id) ON DELETE CASCADE
);
ALTER TABLE roster_templates
    ADD CONSTRAINT roster_templates_complete_content_fk
    FOREIGN KEY (completion_id)
    REFERENCES roster_template_completions (id)
    DEFERRABLE INITIALLY DEFERRED;

CREATE UNIQUE INDEX idx_roster_templates_active_name ON roster_templates (roster_group_id, LOWER(btrim(name))) WHERE deleted_at IS NULL;
CREATE INDEX idx_roster_templates_group_updated ON roster_templates (roster_group_id, updated_at DESC) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_roster_template_days_template_weekday ON roster_template_days (roster_template_id, weekday_index) WHERE weekday_index IS NOT NULL;
CREATE UNIQUE INDEX idx_roster_template_columns_template_name ON roster_template_columns (roster_template_id, LOWER(btrim(name)));
CREATE UNIQUE INDEX idx_roster_template_columns_template_sort ON roster_template_columns (roster_template_id, sort_order);
CREATE UNIQUE INDEX idx_roster_template_shifts_cell ON roster_template_shifts (roster_template_id, roster_template_day_id, row_index, roster_template_column_id);
CREATE INDEX idx_roster_template_shifts_staff ON roster_template_shifts (staff_id) WHERE staff_id IS NOT NULL;
CREATE INDEX idx_roster_template_shifts_shift_type ON roster_template_shifts (shift_type_id);

CREATE OR REPLACE FUNCTION enforce_roster_template_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_group_id <> OLD.roster_group_id
        OR NEW.scale <> OLD.scale
        OR NEW.completion_id <> OLD.completion_id THEN
        RAISE EXCEPTION 'roster template group, scale, and completion identity are immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_template_content_integrity()
RETURNS TRIGGER
AS $$
DECLARE
    template_group_id UUID;
    template_scale TEXT;
    group_venue_id UUID;
BEGIN
    SELECT t.roster_group_id, t.scale, rg.venue_id
    INTO template_group_id, template_scale, group_venue_id
    FROM roster_templates t
    JOIN roster_groups rg ON rg.id = t.roster_group_id
    WHERE t.id = NEW.roster_template_id;

    IF template_group_id IS NULL THEN
        RAISE EXCEPTION 'roster template content must reference an existing template';
    END IF;

    IF TG_TABLE_NAME = 'roster_template_days' THEN
        IF template_scale = 'day' AND (NEW.day_index <> 0 OR NEW.weekday_index IS NOT NULL) THEN
            RAISE EXCEPTION 'day roster templates may contain only target-relative day index zero';
        END IF;
        IF template_scale = 'week' AND NEW.weekday_index IS NULL THEN
            RAISE EXCEPTION 'week roster template days require explicit weekday identity';
        END IF;
        IF EXISTS (
            SELECT 1 FROM roster_template_shifts s
            WHERE s.roster_template_day_id = NEW.id
              AND (s.row_index >= NEW.row_count OR s.roster_template_id <> NEW.roster_template_id)
        ) THEN
            RAISE EXCEPTION 'roster template day must contain every shift row in one template';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_TABLE_NAME = 'roster_template_columns' THEN
        IF EXISTS (
            SELECT 1 FROM roster_template_shifts s
            WHERE s.roster_template_column_id = NEW.id
              AND s.roster_template_id <> NEW.roster_template_id
        ) THEN
            RAISE EXCEPTION 'roster template column and shifts must stay in one template';
        END IF;
        RETURN NEW;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM roster_template_days d
        JOIN roster_template_columns c ON c.roster_template_id = d.roster_template_id
        WHERE d.id = NEW.roster_template_day_id
          AND c.id = NEW.roster_template_column_id
          AND d.roster_template_id = NEW.roster_template_id
          AND NEW.row_index < d.row_count
    ) THEN
        RAISE EXCEPTION 'roster template shift must occupy a valid cell in one template';
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

CREATE OR REPLACE FUNCTION invalidate_roster_template_completion()
RETURNS TRIGGER
AS $$
BEGIN
    DELETE FROM roster_template_completions
    WHERE roster_template_id IN (
        CASE WHEN TG_OP = 'INSERT' THEN NEW.roster_template_id ELSE OLD.roster_template_id END,
        CASE WHEN TG_OP = 'DELETE' THEN OLD.roster_template_id ELSE NEW.roster_template_id END
    );
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION certify_roster_template_completion()
RETURNS TRIGGER
AS $$
DECLARE
    template_scale TEXT;
    template_venue_id UUID;
    day_count INT;
    column_count INT;
BEGIN
    SELECT t.scale, rg.venue_id
    INTO template_scale, template_venue_id
    FROM roster_templates t
    JOIN roster_groups rg ON rg.id = t.roster_group_id
    WHERE t.id = NEW.roster_template_id
      AND t.completion_id = NEW.id;

    IF template_scale IS NULL THEN
        RAISE EXCEPTION 'roster template completion token must match its template';
    END IF;

    SELECT COUNT(*) INTO day_count FROM roster_template_days WHERE roster_template_id = NEW.roster_template_id;
    SELECT COUNT(*) INTO column_count FROM roster_template_columns WHERE roster_template_id = NEW.roster_template_id;
    IF (template_scale = 'week' AND day_count <> 7)
        OR (template_scale = 'day' AND day_count <> 1) THEN
        RAISE EXCEPTION 'roster template content must contain every day required by its scale';
    END IF;
    IF column_count = 0 THEN
        RAISE EXCEPTION 'roster template content must contain at least one column';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM roster_template_shifts s
        JOIN roster_template_days d ON d.id = s.roster_template_day_id
        JOIN roster_template_columns c ON c.id = s.roster_template_column_id
        LEFT JOIN staff ON staff.id = s.staff_id
        JOIN shift_types ON shift_types.id = s.shift_type_id
        WHERE s.roster_template_id = NEW.roster_template_id
          AND (
            d.roster_template_id <> s.roster_template_id
            OR c.roster_template_id <> s.roster_template_id
            OR s.row_index >= d.row_count
            OR shift_types.venue_id <> template_venue_id
            OR (staff.id IS NOT NULL AND staff.venue_id <> template_venue_id)
          )
    ) THEN
        RAISE EXCEPTION 'roster template completion contains invalid shift structure or scope';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION remediate_roster_template_assignments(p_roster_template_id UUID, p_shift_ids UUID[])
RETURNS BOOLEAN
AS $$
BEGIN
    DELETE FROM roster_template_completions
    WHERE roster_template_id = p_roster_template_id;

    UPDATE roster_template_shifts
    SET assignment_state = 'open', staff_id = NULL, updated_at = NOW()
    WHERE roster_template_id = p_roster_template_id
      AND id = ANY(p_shift_ids);

    INSERT INTO roster_template_completions (id, roster_template_id)
    SELECT completion_id, id
    FROM roster_templates
    WHERE id = p_roster_template_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_roster_template_identity_immutable BEFORE UPDATE ON roster_templates FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_identity_immutable();
CREATE TRIGGER enforce_roster_template_day_integrity BEFORE INSERT OR UPDATE ON roster_template_days FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_content_integrity();
CREATE TRIGGER enforce_roster_template_column_integrity BEFORE INSERT OR UPDATE ON roster_template_columns FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_content_integrity();
CREATE TRIGGER enforce_roster_template_shift_integrity BEFORE INSERT OR UPDATE ON roster_template_shifts FOR EACH ROW EXECUTE FUNCTION enforce_roster_template_content_integrity();
CREATE TRIGGER invalidate_roster_template_completion_from_days AFTER INSERT OR UPDATE OR DELETE ON roster_template_days FOR EACH ROW EXECUTE FUNCTION invalidate_roster_template_completion();
CREATE TRIGGER invalidate_roster_template_completion_from_columns AFTER INSERT OR UPDATE OR DELETE ON roster_template_columns FOR EACH ROW EXECUTE FUNCTION invalidate_roster_template_completion();
CREATE TRIGGER invalidate_roster_template_completion_from_shifts AFTER INSERT OR UPDATE OR DELETE ON roster_template_shifts FOR EACH ROW EXECUTE FUNCTION invalidate_roster_template_completion();
CREATE TRIGGER certify_roster_template_completion BEFORE INSERT OR UPDATE ON roster_template_completions FOR EACH ROW EXECUTE FUNCTION certify_roster_template_completion();
