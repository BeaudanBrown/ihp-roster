-- GitHub #151 rollback DDL.
-- Run only in the operator-approved recovery procedure before restoring the
-- encrypted table-data archive. This restores structure, not captured rows.

BEGIN;

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

CREATE INDEX idx_report_definitions_venue_sort ON report_definitions (venue_id, sort_order ASC, created_at ASC);
CREATE UNIQUE INDEX idx_report_definitions_active_slug ON report_definitions (venue_id, slug) WHERE is_active = TRUE AND archived_at IS NULL;
CREATE INDEX idx_report_definition_shift_type_filters_definition ON report_definition_shift_type_filters (report_definition_id);
CREATE UNIQUE INDEX idx_report_definition_shift_type_filters_active ON report_definition_shift_type_filters (report_definition_id, shift_type_id) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX idx_xero_payroll_calendar_selections_connection ON xero_payroll_calendar_selections (xero_connection_id);
CREATE INDEX idx_xero_payroll_calendar_selections_venue_status ON xero_payroll_calendar_selections (venue_id, calendar_status);

CREATE FUNCTION enforce_report_definition_filter_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.report_definitions rd
        JOIN public.shift_types st ON st.id = NEW.shift_type_id
        WHERE rd.id = NEW.report_definition_id
            AND rd.venue_id = st.venue_id
    ) THEN
        RAISE EXCEPTION 'report definition shift type filter must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_hard_delete_report_definitions BEFORE DELETE ON report_definitions FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_report_definition_shift_type_filters BEFORE DELETE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER prevent_hard_delete_xero_payroll_calendar_selections BEFORE DELETE ON xero_payroll_calendar_selections FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete();
CREATE TRIGGER enforce_report_definition_filter_venue_integrity BEFORE INSERT OR UPDATE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION enforce_report_definition_filter_venue_integrity();
CREATE TRIGGER enforce_xero_payroll_calendar_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendar_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();

COMMIT;
