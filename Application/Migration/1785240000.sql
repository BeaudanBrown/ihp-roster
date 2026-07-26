-- GitHub #234: immutable, append-only approved-timesheet wage ledger.
-- Existing approved rows remain readable through their legacy compatibility path
-- until the operator-gated Haskell backfill/cutover runs.

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
    ADD COLUMN active_pay_calculation_id UUID DEFAULT NULL,
    ADD COLUMN legacy_pay_backfill_pending BOOLEAN DEFAULT TRUE NOT NULL;
UPDATE timesheet_entries SET legacy_pay_backfill_pending = FALSE WHERE is_approved = FALSE;
ALTER TABLE timesheet_entries ALTER COLUMN legacy_pay_backfill_pending SET DEFAULT FALSE;
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

-- Existing approved rows carry the only permitted temporary exemption. The
-- backfill clears it atomically when attaching the sealed calculation. New rows
-- and previously-cleared rows cannot acquire the exemption.
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
