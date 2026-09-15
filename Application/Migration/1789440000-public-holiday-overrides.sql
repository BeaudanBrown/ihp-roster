-- Additive override authority. See public-holiday-override-runbook.md.
-- Reviewed calendars are explicit authority, never fabricated provider imports.
CREATE TABLE public_holiday_overrides (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    jurisdiction TEXT NOT NULL,
    target_year INT NOT NULL,
    snapshot_key TEXT NOT NULL UNIQUE,
    source_url TEXT NOT NULL,
    verified_at TIMESTAMP WITH TIME ZONE NOT NULL,
    review_due_at TIMESTAMP WITH TIME ZONE NOT NULL,
    retired_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    correction_before JSONB NOT NULL,
    correction_after JSONB NOT NULL,
    CHECK (review_due_at > verified_at)
);
CREATE UNIQUE INDEX public_holiday_overrides_active_year ON public_holiday_overrides (jurisdiction, target_year) WHERE retired_at IS NULL;

CREATE FUNCTION protect_public_holiday_override() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        IF NOT OLD.is_regional AND EXISTS (
            SELECT 1 FROM public_holiday_overrides
            WHERE retired_at IS NULL AND jurisdiction = OLD.jurisdiction
              AND target_year = EXTRACT(YEAR FROM OLD.holiday_date)::INT
        ) THEN
            RAISE EXCEPTION 'Public holiday year is protected by a reviewed override';
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NOT NEW.is_regional AND EXISTS (
            SELECT 1 FROM public_holiday_overrides
            WHERE retired_at IS NULL AND jurisdiction = NEW.jurisdiction
              AND target_year = EXTRACT(YEAR FROM NEW.holiday_date)::INT
        ) THEN
            RAISE EXCEPTION 'Public holiday year is protected by a reviewed override';
        END IF;
        RETURN NEW;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER protect_public_holiday_override BEFORE INSERT OR UPDATE OR DELETE ON public_holidays FOR EACH ROW EXECUTE FUNCTION protect_public_holiday_override();
