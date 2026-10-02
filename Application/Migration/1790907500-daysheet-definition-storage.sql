-- Additive Daysheet foundation. No existing customer rows are rewritten.
-- Draft corrections are isolated from live reference data until publication.
CREATE TABLE daysheet_definition_versions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    version_number INT NOT NULL,
    definition JSONB NOT NULL,
    reference_data JSONB NOT NULL,
    published_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (published_by) REFERENCES users (id) ON DELETE RESTRICT,
    UNIQUE (venue_id, version_number),
    CHECK (version_number > 0),
    CHECK (jsonb_typeof(definition) = 'object'),
    CHECK (jsonb_typeof(reference_data) = 'object'),
    CHECK (octet_length(definition::TEXT) <= 1048576),
    CHECK (octet_length(reference_data::TEXT) <= 1048576)
);
CREATE TABLE daysheet_configurations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL UNIQUE,
    published_version_id UUID,
    revision BIGINT DEFAULT 0 NOT NULL,
    reference_data JSONB DEFAULT '{}'::JSONB NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (published_version_id) REFERENCES daysheet_definition_versions (id) ON DELETE RESTRICT,
    CHECK (revision >= 0),
    CHECK (jsonb_typeof(reference_data) = 'object'),
    CHECK (octet_length(reference_data::TEXT) <= 1048576)
);
CREATE TABLE daysheet_definition_drafts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL UNIQUE,
    base_revision BIGINT NOT NULL,
    revision BIGINT DEFAULT 0 NOT NULL,
    definition JSONB NOT NULL,
    reference_data JSONB NOT NULL,
    updated_by UUID NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (updated_by) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK (base_revision >= 0),
    CHECK (revision >= 0),
    CHECK (jsonb_typeof(definition) = 'object'),
    CHECK (jsonb_typeof(reference_data) = 'object'),
    CHECK (octet_length(definition::TEXT) <= 1048576),
    CHECK (octet_length(reference_data::TEXT) <= 1048576)
);
CREATE TABLE daysheet_definition_captures (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    operational_date DATE NOT NULL,
    timezone TEXT NOT NULL,
    definition_version_id UUID NOT NULL,
    reference_data JSONB NOT NULL,
    captured_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (definition_version_id) REFERENCES daysheet_definition_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (captured_by) REFERENCES users (id) ON DELETE RESTRICT,
    UNIQUE (venue_id, operational_date),
    CHECK (char_length(btrim(timezone)) > 0),
    CHECK (jsonb_typeof(reference_data) = 'object'),
    CHECK (octet_length(reference_data::TEXT) <= 1048576)
);
CREATE OR REPLACE FUNCTION enforce_daysheet_definition_immutability()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'published Daysheet definitions and captures are immutable';
END;
$$ LANGUAGE plpgsql;
-- IHP's schema parser supports single-column foreign keys. This trigger pairs
-- the normal version FK with venue equality; immutable versions cannot move.
CREATE OR REPLACE FUNCTION enforce_daysheet_version_venue()
RETURNS TRIGGER AS $$
DECLARE
    selected_version UUID;
BEGIN
    IF TG_TABLE_NAME = 'daysheet_configurations' THEN
        selected_version := NEW.published_version_id;
    ELSE
        selected_version := NEW.definition_version_id;
    END IF;
    IF selected_version IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM daysheet_definition_versions
        WHERE id = selected_version AND venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'Daysheet definition version belongs to another venue';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daysheet_versions_immutable BEFORE UPDATE OR DELETE ON daysheet_definition_versions FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_definition_immutability();
CREATE TRIGGER daysheet_captures_immutable BEFORE UPDATE OR DELETE ON daysheet_definition_captures FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_definition_immutability();
CREATE TRIGGER daysheet_configurations_version_venue BEFORE INSERT OR UPDATE ON daysheet_configurations FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_version_venue();
CREATE TRIGGER daysheet_captures_version_venue BEFORE INSERT OR UPDATE ON daysheet_definition_captures FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_version_venue();
