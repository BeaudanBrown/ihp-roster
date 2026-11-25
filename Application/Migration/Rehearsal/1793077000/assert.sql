DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM venue_config WHERE venue_id = '70200000-0000-0000-0000-000000000001'
        AND unavailable_staff_warning_threshold = 7 AND unavailable_staff_daily_maximum IS NULL) THEN
        RAISE EXCEPTION 'Upgrading must preserve warnings and leave the maximum unset';
    END IF;
    BEGIN
        UPDATE venue_config SET unavailable_staff_daily_maximum = 6 WHERE venue_id = '70200000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'Maximum below warning was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        UPDATE venue_config SET unavailable_staff_daily_maximum = 101 WHERE venue_id = '70200000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'Maximum above 100 was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END $$;
