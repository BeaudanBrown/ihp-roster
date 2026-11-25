DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM user_preferences WHERE user_id = '70200000-0000-0000-0000-000000000002'
        AND roster_fit_whole_week IS FALSE) THEN
        RAISE EXCEPTION 'Upgrading must leave Fit whole week disabled';
    END IF;
END $$;
