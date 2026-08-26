-- Date-native Timesheets authority (#369).
--
-- Operational dates are additive and do not rewrite authoritative instants.
-- Roster-derived entries inherit the source Roster day's Operational date;
-- historical ad-hoc entries conservatively retain their local start date.

ALTER TABLE timesheet_entries
    ADD COLUMN operational_date DATE;

UPDATE timesheet_entries te
SET operational_date = rd.operational_date
FROM roster_slots rs
JOIN roster_days rd ON rd.id = rs.roster_day_id
WHERE te.source_roster_slot_id = rs.id;

UPDATE timesheet_entries te
SET operational_date = (te.starts_at AT TIME ZONE te.timezone)::DATE
WHERE te.operational_date IS NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM timesheet_entries
        WHERE operational_date IS NULL
    ) THEN
        RAISE EXCEPTION 'timesheet Operational-date backfill failed validation';
    END IF;
END
$$;

ALTER TABLE timesheet_entries
    ALTER COLUMN operational_date SET NOT NULL;

CREATE INDEX idx_timesheet_entries_venue_operational_date
    ON timesheet_entries (venue_id, operational_date)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION enforce_timesheet_entry_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry staff_id must stay within entry venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM shift_types st
        WHERE st.id = NEW.shift_type_id
            AND st.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry shift_type_id must stay within entry venue';
    END IF;

    IF NEW.staff_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM staff_pay_versions spv
            WHERE spv.id = NEW.staff_pay_version_id
                AND spv.venue_id = NEW.venue_id
                AND spv.staff_id = NEW.staff_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry staff_pay_version_id must match entry staff and venue';
    END IF;

    IF NEW.shift_type_pay_version_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM shift_type_pay_versions stpv
            WHERE stpv.id = NEW.shift_type_pay_version_id
                AND stpv.venue_id = NEW.venue_id
                AND stpv.shift_type_id = NEW.shift_type_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry shift_type_pay_version_id must match entry shift type and venue';
    END IF;

    IF NEW.source_roster_slot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_slots rs
            JOIN roster_days rd ON rd.id = rs.roster_day_id
            WHERE rs.id = NEW.source_roster_slot_id
                AND rd.venue_id = NEW.venue_id
                AND rd.operational_date = NEW.operational_date
        )
    THEN
        RAISE EXCEPTION 'timesheet entry source roster slot must match entry venue and Operational date';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF (OLD.source_roster_slot_id IS NOT NULL OR NEW.source_roster_slot_id IS NOT NULL)
        AND (
            NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id
            OR NEW.operational_date IS DISTINCT FROM OLD.operational_date
            OR NEW.timezone IS DISTINCT FROM OLD.timezone
        )
    THEN
        RAISE EXCEPTION 'roster-derived timesheet Operational date, timezone and source are immutable';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
