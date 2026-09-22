-- pg_dump seed imports clear search_path. Resolve override authority explicitly
-- without changing protected years, holiday data, or the existing trigger.
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
