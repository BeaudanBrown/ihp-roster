CREATE TABLE daysheets (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    operational_date DATE NOT NULL,
    definition_capture_id UUID NOT NULL,
    revision INT DEFAULT 0 NOT NULL,
    saved_data JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    created_by UUID NOT NULL,
    last_edited_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    last_edited_by UUID NOT NULL,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    submitted_by UUID DEFAULT NULL,
    CONSTRAINT daysheets_venue_day_unique UNIQUE (venue_id, operational_date),
    CONSTRAINT daysheets_capture_unique UNIQUE (definition_capture_id),
    CONSTRAINT daysheets_revision_nonnegative CHECK (revision >= 0),
    CONSTRAINT daysheets_submission_pair CHECK ((submitted_at IS NULL) = (submitted_by IS NULL)),
    CONSTRAINT daysheets_data_object CHECK (jsonb_typeof(saved_data) = 'object'),
    CONSTRAINT daysheets_data_bound CHECK (octet_length(saved_data::TEXT) <= 8388608)
);
ALTER TABLE daysheets ADD CONSTRAINT daysheets_ref_venue FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE daysheets ADD CONSTRAINT daysheets_ref_capture FOREIGN KEY (definition_capture_id) REFERENCES daysheet_definition_captures (id) ON DELETE RESTRICT;
ALTER TABLE daysheets ADD CONSTRAINT daysheets_ref_creator FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE daysheets ADD CONSTRAINT daysheets_ref_editor FOREIGN KEY (last_edited_by) REFERENCES users (id) ON DELETE RESTRICT;
ALTER TABLE daysheets ADD CONSTRAINT daysheets_ref_submitter FOREIGN KEY (submitted_by) REFERENCES users (id) ON DELETE RESTRICT;
CREATE OR REPLACE FUNCTION enforce_daysheet_daily_identity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Saved Daysheets require controlled retention handling';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        IF NEW.id IS DISTINCT FROM OLD.id OR NEW.venue_id IS DISTINCT FROM OLD.venue_id
           OR NEW.operational_date IS DISTINCT FROM OLD.operational_date
           OR NEW.definition_capture_id IS DISTINCT FROM OLD.definition_capture_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by
           OR NEW.revision <= OLD.revision THEN
            RAISE EXCEPTION 'Daysheet identity is immutable and revisions must advance';
        END IF;
        IF OLD.submitted_at IS NOT NULL AND (NEW.submitted_at IS DISTINCT FROM OLD.submitted_at OR NEW.submitted_by IS DISTINCT FROM OLD.submitted_by) THEN
            RAISE EXCEPTION 'Daysheet submission does not reopen';
        END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM daysheet_definition_captures WHERE id = NEW.definition_capture_id AND venue_id = NEW.venue_id AND operational_date = NEW.operational_date) THEN
        RAISE EXCEPTION 'Daysheet capture must belong to its venue and Operational day';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daysheet_daily_identity BEFORE INSERT OR UPDATE OR DELETE ON daysheets FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_daily_identity();
