DO $$
DECLARE
    correction public_holiday_overrides;
BEGIN
    SELECT * INTO STRICT correction FROM public_holiday_overrides
    WHERE snapshot_key = 'business-victoria-vic-2026-20260915-v1';
    IF correction.retired_at IS NOT NULL OR correction.target_year <> 2026
       OR jsonb_array_length(correction.correction_before) <> 14
       OR jsonb_array_length(correction.correction_after) <> 15 THEN
        RAISE EXCEPTION 'Holiday override activation/audit invariant failed';
    END IF;
    IF (SELECT count(*) FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
        AND holiday_date BETWEEN DATE '2026-01-01' AND DATE '2026-12-31') <> 14 THEN
        RAISE EXCEPTION 'Holiday override complete-year invariant failed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC'
        AND holiday_date = DATE '2026-09-25' AND name = 'Friday before the AFL grand final' AND imported_at IS NULL) THEN
        RAISE EXCEPTION 'Grand Final correction/freshness invariant failed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC'
        AND holiday_date = DATE '2027-03-29' AND name = 'Easter Monday')
       OR NOT EXISTS (SELECT 1 FROM public_holidays WHERE jurisdiction = 'VIC'
        AND holiday_date = DATE '2027-03-28' AND name = 'Easter Sunday') THEN
        RAISE EXCEPTION 'Easter correction preservation invariant failed';
    END IF;
    IF (SELECT count(*) FROM public_holidays WHERE imported_at = TIMESTAMPTZ '2026-07-31 18:26:21+00') <> 15
       OR (SELECT count(*) FROM public_holidays WHERE name IN ('Local-only fixture', 'Other-state fixture')) <> 2 THEN
        RAISE EXCEPTION 'Holiday correction unrelated data/freshness preservation failed';
    END IF;
    -- Failed protected writes roll back to this PL/pgSQL subtransaction.
    BEGIN
        DELETE FROM public_holidays WHERE jurisdiction = 'VIC' AND NOT is_regional
          AND holiday_date = DATE '2026-03-09';
        RAISE EXCEPTION 'Reviewed calendar write guard did not reject mutation' USING ERRCODE = '23514';
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        NULL;
    END;
END;
$$;
