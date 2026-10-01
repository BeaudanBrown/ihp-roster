DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public_holiday_import_batches
        WHERE jurisdiction = 'VIC' AND target_years = ARRAY[2035]
          AND accepted_at = TIMESTAMPTZ '2034-12-01 00:00:00+00'
          AND source = 'legacy_import') THEN
        RAISE EXCEPTION 'DataVic migration failed to preserve legacy acceptance timestamp';
    END IF;
    IF EXISTS (SELECT 1 FROM public_holiday_import_batches WHERE 2036 = ANY(target_years)) THEN
        RAISE EXCEPTION 'DataVic migration fabricated acceptance for unverified dates';
    END IF;
    IF (SELECT count(*) FROM public_holidays WHERE id IN
        ('65600000-0000-0000-0000-000000000001', '65600000-0000-0000-0000-000000000002')) <> 2 THEN
        RAISE EXCEPTION 'DataVic migration changed existing calendar rows';
    END IF;
END $$;
