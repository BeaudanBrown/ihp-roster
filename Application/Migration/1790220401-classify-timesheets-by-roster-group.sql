-- Add explicit classification without changing timestamps, approval state, pay evidence or export history.
ALTER TABLE timesheet_entries
    ADD COLUMN roster_group_classification roster_timesheet_group_classification_enum,
    ADD COLUMN roster_group_id UUID;

-- Exact source provenance is authoritative, including archived groups and historical slots.
UPDATE timesheet_entries entry
SET roster_group_classification = 'in_roster_group',
    roster_group_id = roster_day.roster_group_id
FROM roster_slots roster_slot
JOIN roster_days roster_day ON roster_day.id = roster_slot.roster_day_id
WHERE entry.source_roster_slot_id = roster_slot.id;

-- Unlinked entries use current Staff memberships. Multiple memberships are deliberately
-- deterministic by group sort_order then stable id and are reported by the runbook.
WITH ranked_memberships AS (
    SELECT
        entry.id AS timesheet_entry_id,
        staff_group.roster_group_id,
        row_number() OVER (
            PARTITION BY entry.id
            ORDER BY roster_group.sort_order, roster_group.id
        ) AS membership_rank
    FROM timesheet_entries entry
    JOIN staff_roster_groups staff_group
        ON staff_group.staff_id = entry.staff_id
       AND staff_group.deleted_at IS NULL
    JOIN roster_groups roster_group ON roster_group.id = staff_group.roster_group_id
    WHERE entry.roster_group_classification IS NULL
)
UPDATE timesheet_entries entry
SET roster_group_classification = 'in_roster_group',
    roster_group_id = ranked_memberships.roster_group_id
FROM ranked_memberships
WHERE ranked_memberships.timesheet_entry_id = entry.id
  AND ranked_memberships.membership_rank = 1;

UPDATE timesheet_entries
SET roster_group_classification = 'no_roster_group'
WHERE roster_group_classification IS NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM timesheet_entries
        WHERE roster_group_classification IS NULL
           OR (roster_group_classification = 'in_roster_group') <> (roster_group_id IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'timesheet roster group classification backfill incomplete';
    END IF;
END;
$$;

ALTER TABLE timesheet_entries
    ALTER COLUMN roster_group_classification SET DEFAULT 'no_roster_group',
    ALTER COLUMN roster_group_classification SET NOT NULL,
    ADD CONSTRAINT timesheet_entries_roster_group_id_fkey
        FOREIGN KEY (roster_group_id) REFERENCES roster_groups (id) ON DELETE RESTRICT,
    ADD CONSTRAINT timesheet_entries_roster_group_classification_check
        CHECK (
            (roster_group_classification = 'in_roster_group' AND roster_group_id IS NOT NULL)
            OR (roster_group_classification = 'no_roster_group' AND roster_group_id IS NULL)
        );

CREATE INDEX idx_timesheet_entries_venue_roster_group
    ON timesheet_entries (venue_id, roster_group_id, operational_date)
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
        RAISE EXCEPTION 'timesheet entry venue_id must match staff_id venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM shift_types st
        WHERE st.id = NEW.shift_type_id
            AND st.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match shift_type_id venue';
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

    IF NEW.roster_group_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM roster_groups rg
            WHERE rg.id = NEW.roster_group_id
                AND rg.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry roster group must match entry venue';
    END IF;

    IF NEW.source_roster_slot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM roster_slots rs
            JOIN roster_days rd ON rd.id = rs.roster_day_id
            WHERE rs.id = NEW.source_roster_slot_id
                AND rd.venue_id = NEW.venue_id
                AND rd.operational_date = NEW.operational_date
                AND rd.roster_group_id = NEW.roster_group_id
                AND NEW.roster_group_classification = 'in_roster_group'
        )
    THEN
        RAISE EXCEPTION 'timesheet entry source roster slot must match entry venue, Operational date and roster group';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.roster_group_classification IS DISTINCT FROM OLD.roster_group_classification
        OR NEW.roster_group_id IS DISTINCT FROM OLD.roster_group_id
    THEN
        RAISE EXCEPTION 'timesheet roster group classification is immutable';
    END IF;

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
