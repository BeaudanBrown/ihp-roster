DO $$
BEGIN
    IF (
        SELECT count(*)
        FROM timesheet_entries
        WHERE id IN (
            'b8000000-0000-0000-0000-000000000001',
            'b8000000-0000-0000-0000-000000000002',
            'b8000000-0000-0000-0000-000000000003'
        )
          AND staff_comment IN ('preserve-linked', 'preserve-membership', 'preserve-none')
    ) <> 3 THEN
        RAISE EXCEPTION 'timesheet_classification_customer_data_preservation failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timesheet_entries
        WHERE id = 'b8000000-0000-0000-0000-000000000001'
          AND roster_group_classification = 'in_roster_group'
          AND roster_group_id = 'b4000000-0000-0000-0000-000000000002'
    ) THEN
        RAISE EXCEPTION 'timesheet_classification_source_group_precedence failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timesheet_entries
        WHERE id = 'b8000000-0000-0000-0000-000000000002'
          AND roster_group_classification = 'in_roster_group'
          AND roster_group_id = 'b4000000-0000-0000-0000-000000000001'
    ) THEN
        RAISE EXCEPTION 'timesheet_classification_deterministic_membership_order failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM timesheet_entries
        WHERE id = 'b8000000-0000-0000-0000-000000000003'
          AND roster_group_classification = 'no_roster_group'
          AND roster_group_id IS NULL
    ) THEN
        RAISE EXCEPTION 'timesheet_classification_explicit_no_group failed';
    END IF;

    BEGIN
        UPDATE timesheet_entries
        SET roster_group_classification = 'no_roster_group', roster_group_id = NULL
        WHERE id = 'b8000000-0000-0000-0000-000000000001';
        RAISE EXCEPTION 'timesheet_classification_immutability failed';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM = 'timesheet_classification_immutability failed' THEN
            RAISE;
        END IF;
    END;
END
$$;
