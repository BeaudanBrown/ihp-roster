-- Additive storage only: no existing Daysheet, recipient or queue row is rewritten.
CREATE TYPE daysheet_report_origin AS ENUM ('daysheet_manual', 'daysheet_scheduled');
CREATE TABLE daysheet_report_snapshots (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    daysheet_id UUID NOT NULL,
    definition_capture_id UUID NOT NULL,
    report_id UUID NOT NULL,
    request_key UUID NOT NULL,
    origin daysheet_report_origin NOT NULL,
    sender_id UUID DEFAULT NULL,
    cutoff_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    captured_at TIMESTAMP WITH TIME ZONE NOT NULL,
    source_revision INT NOT NULL,
    content JSONB NOT NULL,
    recipient_ids JSONB NOT NULL,
    CONSTRAINT daysheet_report_request_unique UNIQUE (venue_id, request_key),
    CONSTRAINT daysheet_report_revision_nonnegative CHECK (source_revision >= 0),
    CONSTRAINT daysheet_report_origin_shape CHECK (
        (origin = 'daysheet_manual' AND sender_id IS NOT NULL AND cutoff_at IS NULL)
        OR (origin = 'daysheet_scheduled' AND sender_id IS NULL AND cutoff_at IS NOT NULL AND captured_at >= cutoff_at)),
    CONSTRAINT daysheet_report_content_object CHECK (jsonb_typeof(content) = 'object'),
    CONSTRAINT daysheet_report_content_bound CHECK (octet_length(content::TEXT) <= 33554432),
    CONSTRAINT daysheet_report_recipients_array CHECK (jsonb_typeof(recipient_ids) = 'array'),
    CONSTRAINT daysheet_report_recipients_bound CHECK (jsonb_array_length(recipient_ids) <= 10000)
);
ALTER TABLE daysheet_report_snapshots ADD CONSTRAINT daysheet_report_ref_venue FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT;
ALTER TABLE daysheet_report_snapshots ADD CONSTRAINT daysheet_report_ref_day FOREIGN KEY (daysheet_id) REFERENCES daysheets (id) ON DELETE RESTRICT;
ALTER TABLE daysheet_report_snapshots ADD CONSTRAINT daysheet_report_ref_capture FOREIGN KEY (definition_capture_id) REFERENCES daysheet_definition_captures (id) ON DELETE RESTRICT;
ALTER TABLE daysheet_report_snapshots ADD CONSTRAINT daysheet_report_ref_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE RESTRICT;
CREATE UNIQUE INDEX daysheet_report_cutoff_unique ON daysheet_report_snapshots (daysheet_id, report_id, cutoff_at) WHERE origin = 'daysheet_scheduled';
CREATE INDEX daysheet_report_history ON daysheet_report_snapshots (venue_id, daysheet_id, captured_at DESC);
CREATE OR REPLACE FUNCTION enforce_daysheet_report_snapshot()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'Frozen Daysheet reports require controlled retention handling';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM daysheets
        WHERE id = NEW.daysheet_id AND venue_id = NEW.venue_id
          AND definition_capture_id = NEW.definition_capture_id
          AND revision = NEW.source_revision AND submitted_at IS NOT NULL
          AND last_edited_at <= NEW.captured_at AND submitted_at <= NEW.captured_at
          AND (NEW.cutoff_at IS NULL OR (last_edited_at <= NEW.cutoff_at AND submitted_at <= NEW.cutoff_at))) THEN
        RAISE EXCEPTION 'Frozen Daysheet report must match a submitted saved source';
    END IF;
    IF jsonb_typeof(NEW.recipient_ids) <> 'array' THEN
        RAISE EXCEPTION 'Frozen Daysheet recipients must be a captured set';
    END IF;
    IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(NEW.recipient_ids) AS intended(recipient_id)
        WHERE NOT EXISTS (SELECT 1 FROM daysheet_report_recipients
            WHERE id = intended.recipient_id::UUID AND venue_id = NEW.venue_id
              AND report_id = NEW.report_id AND removed_at IS NULL))
       OR (SELECT count(DISTINCT recipient_id) FROM jsonb_array_elements_text(NEW.recipient_ids) AS intended(recipient_id)) <> jsonb_array_length(NEW.recipient_ids) THEN
        RAISE EXCEPTION 'Frozen Daysheet recipients must be distinct active scoped identities';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daysheet_report_snapshot_guard BEFORE INSERT OR UPDATE OR DELETE ON daysheet_report_snapshots FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_report_snapshot();
