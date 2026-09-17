-- Seed/pg_dump sessions intentionally use an empty search_path. Resolve the
-- override authority explicitly rather than depending on the caller's path.
-- Data-preserving: replace only the function body; retain its trigger, calendar
-- rows and override audit history. Recovery: reapply this definition; restoring
-- the old body would reintroduce the seed/restore failure.
CREATE OR REPLACE FUNCTION public.protect_public_holiday_override() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        IF NOT OLD.is_regional AND EXISTS (
            SELECT 1 FROM public.public_holiday_overrides
            WHERE retired_at IS NULL AND jurisdiction = OLD.jurisdiction
              AND target_year = EXTRACT(YEAR FROM OLD.holiday_date)::INT
        ) THEN
            RAISE EXCEPTION 'Public holiday year is protected by a reviewed override';
        END IF;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        IF NOT NEW.is_regional AND EXISTS (
            SELECT 1 FROM public.public_holiday_overrides
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
