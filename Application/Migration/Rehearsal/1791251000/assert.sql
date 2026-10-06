DO $$
DECLARE invalid_minutes INTEGER;
BEGIN
    IF (SELECT COUNT(*) FROM venue_config
        WHERE id IN ('a6540000-0000-0000-0000-000000000011', 'a6540000-0000-0000-0000-000000000012')
          AND default_roster_shift_duration_minutes = 480
          AND updated_at = '2026-01-01T00:00:00Z') <> 2 THEN
        RAISE EXCEPTION 'roster duration backfill or timestamp preservation failed';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM venue_config
        WHERE id = 'a6540000-0000-0000-0000-000000000011'
          AND roster_week_starts_on = 4 AND time_picker_start_minute_of_day = 540
          AND time_picker_final_selectable_minute_of_day = 1020
          AND minute_precision_shift_times_enabled) THEN
        RAISE EXCEPTION 'existing venue settings were not preserved';
    END IF;
    FOREACH invalid_minutes IN ARRAY ARRAY[-15, 0, 14, 16, 1441] LOOP
        BEGIN
            UPDATE venue_config SET default_roster_shift_duration_minutes = invalid_minutes
            WHERE id = 'a6540000-0000-0000-0000-000000000011';
            RAISE EXCEPTION 'invalid roster duration was accepted';
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END LOOP;
    BEGIN
        UPDATE venue_config SET default_roster_shift_duration_minutes = NULL
        WHERE id = 'a6540000-0000-0000-0000-000000000011';
        RAISE EXCEPTION 'null roster duration was accepted';
    EXCEPTION WHEN not_null_violation THEN NULL;
    END;
    UPDATE venue_config SET default_roster_shift_duration_minutes = 90
    WHERE id = 'a6540000-0000-0000-0000-000000000011';
    IF NOT EXISTS (SELECT 1 FROM venue_config
        WHERE id = 'a6540000-0000-0000-0000-000000000012'
          AND default_roster_shift_duration_minutes = 480) THEN
        RAISE EXCEPTION 'roster duration venue isolation failed';
    END IF;
END $$;
