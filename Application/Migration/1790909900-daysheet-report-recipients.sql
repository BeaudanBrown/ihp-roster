-- Additive external-recipient identity. Existing account/invitation envelopes,
-- dedupe keys, user accounts and queue rows are unchanged.
CREATE TABLE daysheet_report_recipients (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    venue_id UUID NOT NULL,
    report_id UUID NOT NULL,
    definition_version_id UUID NOT NULL,
    address TEXT NOT NULL,
    created_by UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    removed_at TIMESTAMP WITH TIME ZONE,
    removed_by UUID,
    FOREIGN KEY (venue_id) REFERENCES venues (id) ON DELETE RESTRICT,
    FOREIGN KEY (definition_version_id) REFERENCES daysheet_definition_versions (id) ON DELETE RESTRICT,
    FOREIGN KEY (created_by) REFERENCES users (id) ON DELETE RESTRICT,
    FOREIGN KEY (removed_by) REFERENCES users (id) ON DELETE RESTRICT,
    CHECK ((char_length(address) > 0) AND (char_length(address) <= 254)),
    CHECK (address = lower(btrim(address))),
    CHECK ((removed_at IS NULL) = (removed_by IS NULL))
);
CREATE UNIQUE INDEX daysheet_report_recipient_active_address ON daysheet_report_recipients (venue_id, report_id, address) WHERE removed_at IS NULL;
CREATE OR REPLACE FUNCTION enforce_daysheet_recipient_identity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Daysheet recipient identities must be retained';
    END IF;
    IF (to_jsonb(OLD) - 'removed_at' - 'removed_by') IS DISTINCT FROM (to_jsonb(NEW) - 'removed_at' - 'removed_by')
       OR (OLD.removed_at IS NOT NULL AND (NEW.removed_at IS DISTINCT FROM OLD.removed_at OR NEW.removed_by IS DISTINCT FROM OLD.removed_by)) THEN
        RAISE EXCEPTION 'Daysheet recipient identity and cancellation are immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER daysheet_recipient_identity BEFORE UPDATE OR DELETE ON daysheet_report_recipients FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_recipient_identity();
CREATE TRIGGER daysheet_recipient_version_venue BEFORE INSERT OR UPDATE ON daysheet_report_recipients FOR EACH ROW EXECUTE FUNCTION enforce_daysheet_version_venue();
