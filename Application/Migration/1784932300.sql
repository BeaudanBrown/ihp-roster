-- GitHub #274: replace roster/timesheet wall-clock columns with authoritative
-- instants plus the IANA timezone snapshot used to interpret them.
--
-- This migration is intentionally destructive only after every legacy row has
-- been backfilled and checked. Follow authoritative-time-boundaries-274-runbook.md
-- and take the required database backup before applying it.
-- The current VenueTime authority deliberately supports Melbourne only. Fail
-- before destructive work when deployed configuration is outside that contract.

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM venue_config vc
        WHERE btrim(vc.timezone) IS DISTINCT FROM 'Australia/Melbourne'
    ) THEN
        RAISE EXCEPTION 'unsupported venue timezone for authoritative-boundary migration; see #274 runbook';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION bepis_first_civil_occurrence(
    p_local_time TIMESTAMP WITHOUT TIME ZONE,
    p_timezone TEXT
)
RETURNS TIMESTAMP WITH TIME ZONE
AS $$
DECLARE
    resolved TIMESTAMP WITH TIME ZONE := p_local_time AT TIME ZONE p_timezone;
BEGIN
    -- PostgreSQL chooses the later standard-time occurrence for a repeated
    -- civil time. If one hour earlier round-trips to the same civil value,
    -- select that earlier instant for the deterministic migration policy.
    IF ((resolved - INTERVAL '1 hour') AT TIME ZONE p_timezone) = p_local_time THEN
        RETURN resolved - INTERVAL '1 hour';
    END IF;

    -- A spring-forward gap does not round-trip. Abort rather than silently
    -- normalizing legacy customer input to a different wall clock.
    IF (resolved AT TIME ZONE p_timezone) <> p_local_time THEN
        RAISE EXCEPTION 'nonexistent civil time % in timezone %; see #274 runbook', p_local_time, p_timezone;
    END IF;

    RETURN resolved;
END;
$$ LANGUAGE plpgsql STABLE;

ALTER TABLE roster_slots
    ADD COLUMN starts_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN ends_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN timezone TEXT DEFAULT NULL;

ALTER TABLE timesheet_entries
    ADD COLUMN starts_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN ends_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN break_starts_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN break_ends_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ADD COLUMN timezone TEXT DEFAULT NULL;

WITH roster_civil AS (
    SELECT
        rs.id,
        btrim(vc.timezone) AS timezone,
        vc.week_offset_epoch + (rw.week_offset * 7) + rd.day_offset AS roster_date,
        rs.start_time,
        rs.end_time
    FROM roster_slots rs
    JOIN roster_days rd ON rd.id = rs.roster_day_id
    JOIN roster_weeks rw ON rw.id = rd.roster_week_id
    JOIN venue_config vc ON vc.venue_id = rw.venue_id
), roster_resolved AS (
    SELECT
        id,
        timezone,
        CASE
            WHEN start_time IS NULL THEN NULL
            ELSE bepis_first_civil_occurrence(
                roster_date + CASE WHEN start_time < TIME '06:00' THEN 1 ELSE 0 END + start_time,
                timezone
            )
        END AS starts_at,
        CASE
            WHEN end_time IS NULL THEN NULL
            ELSE bepis_first_civil_occurrence(
                roster_date
                    + CASE WHEN end_time < TIME '06:00' THEN 1 ELSE 0 END
                    + end_time,
                timezone
            )
        END AS ends_at
    FROM roster_civil
)
UPDATE roster_slots rs
SET
    starts_at = resolved.starts_at,
    ends_at = resolved.ends_at,
    timezone = resolved.timezone
FROM roster_resolved resolved
WHERE resolved.id = rs.id;

WITH timesheet_civil AS (
    SELECT
        te.id,
        btrim(vc.timezone) AS timezone,
        te.worked_on + te.start_time AS start_local,
        te.worked_on
            + CASE WHEN te.end_time <= te.start_time THEN 1 ELSE 0 END
            + te.end_time AS end_local,
        CASE
            WHEN te.break_start_time IS NULL THEN NULL
            ELSE te.worked_on
                + CASE WHEN te.break_start_time < te.start_time THEN 1 ELSE 0 END
                + te.break_start_time
        END AS break_start_local,
        CASE
            WHEN te.break_end_time IS NULL THEN NULL
            ELSE te.worked_on
                + CASE
                    WHEN te.break_start_time IS NOT NULL AND te.break_end_time <= te.break_start_time THEN 1
                    WHEN te.break_end_time < te.start_time THEN 1
                    ELSE 0
                  END
                + te.break_end_time
        END AS break_end_local
    FROM timesheet_entries te
    JOIN venue_config vc ON vc.venue_id = te.venue_id
), timesheet_resolved AS (
    SELECT
        id,
        timezone,
        bepis_first_civil_occurrence(start_local, timezone) AS starts_at,
        bepis_first_civil_occurrence(end_local, timezone) AS ends_at,
        CASE
            WHEN break_start_local IS NULL THEN NULL
            ELSE bepis_first_civil_occurrence(break_start_local, timezone)
        END AS break_starts_at,
        CASE
            WHEN break_end_local IS NULL THEN NULL
            ELSE bepis_first_civil_occurrence(break_end_local, timezone)
        END AS break_ends_at
    FROM timesheet_civil
)
UPDATE timesheet_entries te
SET
    starts_at = resolved.starts_at,
    ends_at = resolved.ends_at,
    break_starts_at = resolved.break_starts_at,
    break_ends_at = resolved.break_ends_at,
    timezone = resolved.timezone
FROM timesheet_resolved resolved
WHERE resolved.id = te.id;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM roster_slots
        WHERE timezone IS NULL
            OR char_length(btrim(timezone)) = 0
            OR (starts_at IS NOT NULL AND ends_at IS NOT NULL AND ends_at <= starts_at)
    ) THEN
        RAISE EXCEPTION 'authoritative roster boundary backfill failed validation; see #274 runbook';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM timesheet_entries
        WHERE starts_at IS NULL
            OR ends_at IS NULL
            OR timezone IS NULL
            OR char_length(btrim(timezone)) = 0
            OR ends_at <= starts_at
            OR ((break_starts_at IS NULL) <> (break_ends_at IS NULL))
            OR (break_starts_at IS NOT NULL AND (
                break_starts_at < starts_at
                OR break_ends_at <= break_starts_at
                OR break_ends_at > ends_at
            ))
    ) THEN
        RAISE EXCEPTION 'authoritative timesheet boundary backfill failed validation; see #274 runbook';
    END IF;
END;
$$;

DROP INDEX IF EXISTS idx_timesheet_entries_venue_worked_on;
DROP TRIGGER IF EXISTS enforce_roster_derived_timesheet_identity_immutable ON timesheet_entries;

ALTER TABLE roster_slots
    ALTER COLUMN timezone SET NOT NULL,
    ADD CONSTRAINT roster_slots_positive_duration_check
        CHECK (starts_at IS NULL OR ends_at IS NULL OR ends_at > starts_at),
    ADD CONSTRAINT roster_slots_timezone_nonempty_check
        CHECK (char_length(btrim(timezone)) > 0),
    ADD CONSTRAINT roster_slots_supported_timezone_check
        CHECK (timezone = 'Australia/Melbourne');

ALTER TABLE timesheet_entries
    ALTER COLUMN starts_at SET NOT NULL,
    ALTER COLUMN ends_at SET NOT NULL,
    ALTER COLUMN timezone SET NOT NULL,
    ADD CONSTRAINT timesheet_entries_positive_duration_check
        CHECK (ends_at > starts_at),
    ADD CONSTRAINT timesheet_entries_break_boundaries_check
        CHECK (
            (break_starts_at IS NULL AND break_ends_at IS NULL)
            OR (
                break_starts_at IS NOT NULL
                AND break_ends_at IS NOT NULL
                AND break_starts_at >= starts_at
                AND break_ends_at > break_starts_at
                AND break_ends_at <= ends_at
            )
        ),
    ADD CONSTRAINT timesheet_entries_timezone_nonempty_check
        CHECK (char_length(btrim(timezone)) > 0),
    ADD CONSTRAINT timesheet_entries_supported_timezone_check
        CHECK (timezone = 'Australia/Melbourne');

ALTER TABLE roster_slots
    DROP COLUMN start_time,
    DROP COLUMN end_time,
    DROP COLUMN duration_minutes;

ALTER TABLE timesheet_entries
    DROP COLUMN worked_on,
    DROP COLUMN start_time,
    DROP COLUMN end_time,
    DROP COLUMN had_break,
    DROP COLUMN break_start_time,
    DROP COLUMN break_end_time,
    DROP COLUMN break_minutes;

CREATE INDEX idx_timesheet_entries_venue_starts_at
    ON timesheet_entries (venue_id, starts_at)
    WHERE deleted_at IS NULL;

CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()
RETURNS TRIGGER
AS $$
BEGIN
    IF (OLD.source_roster_slot_id IS NOT NULL OR NEW.source_roster_slot_id IS NOT NULL)
        AND (
            NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id
            OR (NEW.starts_at AT TIME ZONE NEW.timezone)::DATE IS DISTINCT FROM (OLD.starts_at AT TIME ZONE OLD.timezone)::DATE
            OR NEW.timezone IS DISTINCT FROM OLD.timezone
        )
    THEN
        RAISE EXCEPTION 'roster-derived timesheet local date, timezone and source are immutable';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable
    BEFORE UPDATE ON timesheet_entries
    FOR EACH ROW EXECUTE FUNCTION enforce_roster_derived_timesheet_identity_immutable();

CREATE OR REPLACE FUNCTION calculate_timesheet_pay(p_entry_id UUID)
RETURNS JSONB
AS $$
    WITH entry_data AS (
        SELECT
            te.*,
            (te.starts_at AT TIME ZONE te.timezone)::DATE AS worked_on,
            COALESCE(EXTRACT(EPOCH FROM (te.break_ends_at - te.break_starts_at)) / 60, 0) AS break_minutes,
            GREATEST(
                EXTRACT(EPOCH FROM (te.ends_at - te.starts_at)) / 60
                - COALESCE(EXTRACT(EPOCH FROM (te.break_ends_at - te.break_starts_at)) / 60, 0),
                0
            ) AS authoritative_paid_minutes,
            spv.default_award_level_id AS version_staff_award_level_id,
            spv.imported_xero_pay_item_id AS version_staff_imported_xero_pay_item_id,
            spv.employment_basis AS version_employment_basis,
            stpv.override_award_level_id AS version_shift_award_level_id,
            stpv.imported_xero_pay_item_id AS version_shift_imported_xero_pay_item_id,
            stpv.payroll_label AS version_shift_type_name
        FROM timesheet_entries te
        LEFT JOIN staff_pay_versions spv ON spv.id = te.staff_pay_version_id
        LEFT JOIN shift_type_pay_versions stpv ON stpv.id = te.shift_type_pay_version_id
        WHERE te.id = p_entry_id
            AND te.deleted_at IS NULL
        LIMIT 1
    ),
    resolved AS (
        SELECT
            e.id,
            e.staff_id,
            e.shift_type_id,
            e.worked_on,
            e.starts_at,
            e.ends_at,
            e.break_starts_at,
            e.break_ends_at,
            e.timezone,
            e.break_minutes,
            e.staff_pay_version_id,
            e.shift_type_pay_version_id,
            e.approved_at,
            e.version_shift_type_name,
            COALESCE(
                (
                    SELECT vc.roster_week_starts_on
                    FROM venue_config vc
                    WHERE vc.venue_id = e.venue_id
                    LIMIT 1
                ),
                1
            ) AS venue_week_starts_on,
            COALESCE(
                e.version_employment_basis,
                (
                    SELECT s.employment_basis
                    FROM staff s
                    WHERE s.id = e.staff_id
                    LIMIT 1
                )
            ) AS employment_basis,
            e.authoritative_paid_minutes AS paid_minutes,
            COALESCE(
                e.version_shift_award_level_id,
                e.version_staff_award_level_id,
                resolve_effective_pay_level(
                    e.staff_id,
                    e.shift_type_id,
                    EXTRACT(DOW FROM e.worked_on)::INT
                )
            ) AS pay_level_id,
            COALESCE(
                e.version_shift_imported_xero_pay_item_id,
                CASE WHEN e.shift_type_pay_version_id IS NULL THEN (
                    SELECT st.imported_xero_pay_item_id
                    FROM shift_types st
                    WHERE st.id = e.shift_type_id
                    LIMIT 1
                ) ELSE NULL END,
                e.version_staff_imported_xero_pay_item_id,
                CASE WHEN e.staff_pay_version_id IS NULL THEN (
                    SELECT s.imported_xero_pay_item_id
                    FROM staff s
                    WHERE s.id = e.staff_id
                    LIMIT 1
                ) ELSE NULL END
            ) AS imported_xero_pay_item_id
        FROM entry_data e
    ),
    labelled AS (
        SELECT
            r.*,
            COALESCE(
                r.version_shift_type_name,
                (
                    SELECT st.name
                    FROM shift_types st
                    WHERE st.id = r.shift_type_id
                    LIMIT 1
                )
            ) AS shift_type_name,
            COALESCE(
                (
                    SELECT xipi.name
                    FROM xero_imported_pay_items xipi
                    WHERE xipi.id = r.imported_xero_pay_item_id
                    LIMIT 1
                ),
                (
                    SELECT COALESCE(al.classification_level || ' - ', '') || al.classification
                    FROM award_levels al
                    WHERE al.id = r.pay_level_id
                    LIMIT 1
                )
            ) AS pay_level_name,
            (
                SELECT al.award_fixed_id
                FROM award_levels al
                WHERE al.id = r.pay_level_id
                LIMIT 1
            ) AS award_fixed_id,
            COALESCE(
                (
                    SELECT xipi.rate_per_unit
                    FROM xero_imported_pay_items xipi
                    WHERE xipi.id = r.imported_xero_pay_item_id
                    LIMIT 1
                ),
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = r.employment_basis
                        AND (venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) IS NULL OR venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) <= r.worked_on)
                        AND (r.approved_at IS NOT NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) IS NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) >= r.worked_on)
                        AND (r.approved_at IS NULL OR albr.created_at <= r.approved_at)
                    ORDER BY venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                0::NUMERIC(12,4)
            ) AS base_rate,
            COALESCE(
                (
                    SELECT xipi.rate_per_unit
                    FROM xero_imported_pay_items xipi
                    WHERE xipi.id = r.imported_xero_pay_item_id
                    LIMIT 1
                ),
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = 'permanent'
                        AND (venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) IS NULL OR venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) <= r.worked_on)
                        AND (r.approved_at IS NOT NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) IS NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) >= r.worked_on)
                        AND (r.approved_at IS NULL OR albr.created_at <= r.approved_at)
                    ORDER BY venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = r.employment_basis
                        AND (venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) IS NULL OR venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) <= r.worked_on)
                        AND (r.approved_at IS NOT NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) IS NULL OR venue_effective_award_rate_to(r.venue_week_starts_on, albr.operative_to) >= r.worked_on)
                        AND (r.approved_at IS NULL OR albr.created_at <= r.approved_at)
                    ORDER BY venue_effective_award_rate_from(r.venue_week_starts_on, albr.operative_from) DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                0::NUMERIC(12,4)
            ) AS permanent_base_rate,
            EXISTS (
                SELECT 1
                FROM staff s
                JOIN venue_config vc ON vc.venue_id = s.venue_id
                JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                    AND ph.holiday_date = r.worked_on
                    AND ph.is_regional = FALSE
                WHERE s.id = r.staff_id
                LIMIT 1
            ) AS is_public_holiday
        FROM resolved r
    ),
    paid_window AS (
        SELECT r.*
        FROM labelled r
    ),
    delayed_meal_break_window AS (
        SELECT
            pw.*,
            CASE
                WHEN pw.ends_at - pw.starts_at > INTERVAL '360 minutes'
                    AND NOT (
                        pw.break_starts_at IS NOT NULL
                        AND pw.break_ends_at IS NOT NULL
                        AND pw.break_ends_at - pw.break_starts_at >= INTERVAL '30 minutes'
                        AND pw.break_starts_at >= pw.starts_at + INTERVAL '120 minutes'
                        AND pw.break_starts_at <= pw.starts_at + INTERVAL '360 minutes'
                    )
                THEN pw.starts_at + INTERVAL '360 minutes'
                ELSE NULL
            END AS delayed_meal_break_starts_at,
            CASE
                WHEN pw.ends_at - pw.starts_at > INTERVAL '360 minutes'
                    AND NOT (
                        pw.break_starts_at IS NOT NULL
                        AND pw.break_ends_at IS NOT NULL
                        AND pw.break_ends_at - pw.break_starts_at >= INTERVAL '30 minutes'
                        AND pw.break_starts_at >= pw.starts_at + INTERVAL '120 minutes'
                        AND pw.break_starts_at <= pw.starts_at + INTERVAL '360 minutes'
                    )
                THEN
                    CASE
                        WHEN pw.break_starts_at IS NOT NULL
                            AND pw.break_ends_at IS NOT NULL
                            AND pw.break_ends_at - pw.break_starts_at >= INTERVAL '30 minutes'
                            AND pw.break_starts_at > pw.starts_at + INTERVAL '360 minutes'
                        THEN pw.break_starts_at
                        ELSE pw.ends_at
                    END
                ELSE NULL
            END AS delayed_meal_break_ends_at
        FROM paid_window pw
    ),
    local_segment_windows AS (
        SELECT
            pw.id,
            windows.segment_name,
            windows.segment_date,
            windows.window_starts_at,
            windows.window_ends_at,
            windows.sort_index
        FROM delayed_meal_break_window pw
        CROSS JOIN LATERAL generate_series(
            date_trunc('day', pw.starts_at AT TIME ZONE pw.timezone),
            date_trunc('day', pw.ends_at AT TIME ZONE pw.timezone),
            INTERVAL '1 day'
        ) AS local_days(local_midnight)
        CROSS JOIN LATERAL (
            SELECT
                raw_windows.segment_name,
                local_midnight::DATE AS segment_date,
                raw_windows.window_start_local AT TIME ZONE pw.timezone AS window_starts_at,
                raw_windows.window_end_local AT TIME ZONE pw.timezone AS window_ends_at,
                ((local_midnight::DATE - pw.worked_on) * 100 + raw_windows.window_sort_index * 10)::INT AS sort_index
            FROM (
                VALUES
                    ('late_night_after_midnight'::TEXT, local_midnight, local_midnight + INTERVAL '7 hours', 1),
                    ('ordinary'::TEXT, local_midnight + INTERVAL '7 hours', local_midnight + INTERVAL '19 hours', 2),
                    ('evening_after_7pm'::TEXT, local_midnight + INTERVAL '19 hours', local_midnight + INTERVAL '1 day', 3)
            ) AS raw_windows(segment_name, window_start_local, window_end_local, window_sort_index)
        ) windows
        WHERE windows.window_ends_at > pw.starts_at
            AND windows.window_starts_at < pw.ends_at
    ),
    segment_scopes AS (
        SELECT
            pw.*,
            sw.segment_name,
            sw.segment_date,
            sw.sort_index,
            GREATEST(
                EXTRACT(EPOCH FROM (LEAST(pw.ends_at, sw.window_ends_at) - GREATEST(pw.starts_at, sw.window_starts_at))) / 60,
                0
            ) AS worked_segment_minutes,
            CASE
                WHEN pw.break_starts_at IS NOT NULL AND pw.break_ends_at IS NOT NULL THEN
                    GREATEST(
                        EXTRACT(EPOCH FROM (LEAST(pw.break_ends_at, pw.ends_at, sw.window_ends_at) - GREATEST(pw.break_starts_at, pw.starts_at, sw.window_starts_at))) / 60,
                        0
                    )
                ELSE 0
            END AS break_segment_minutes,
            CASE
                WHEN pw.delayed_meal_break_starts_at IS NOT NULL AND pw.delayed_meal_break_ends_at IS NOT NULL THEN
                    GREATEST(
                        EXTRACT(EPOCH FROM (LEAST(pw.delayed_meal_break_ends_at, pw.ends_at, sw.window_ends_at) - GREATEST(pw.delayed_meal_break_starts_at, pw.starts_at, sw.window_starts_at))) / 60,
                        0
                    )
                ELSE 0
            END AS delayed_segment_minutes,
            CASE
                WHEN pw.break_starts_at IS NOT NULL
                    AND pw.break_ends_at IS NOT NULL
                    AND pw.delayed_meal_break_starts_at IS NOT NULL
                    AND pw.delayed_meal_break_ends_at IS NOT NULL
                THEN
                    GREATEST(
                        EXTRACT(EPOCH FROM (LEAST(pw.break_ends_at, pw.delayed_meal_break_ends_at, pw.ends_at, sw.window_ends_at) - GREATEST(pw.break_starts_at, pw.delayed_meal_break_starts_at, pw.starts_at, sw.window_starts_at))) / 60,
                        0
                    )
                ELSE 0
            END AS break_delayed_segment_minutes
        FROM delayed_meal_break_window pw
        JOIN local_segment_windows sw ON sw.id = pw.id
    ),
    segment_rows AS (
        SELECT scoped.*,
            CASE
                WHEN scoped.imported_xero_pay_item_id IS NOT NULL THEN scoped.base_rate
                WHEN scoped.penalty_kind IN ('delayed_meal_break_weekday', 'delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday') THEN
                    (
                        CASE
                            WHEN scoped.penalty_kind IN ('delayed_meal_break_saturday', 'delayed_meal_break_sunday', 'delayed_meal_break_public_holiday') THEN
                                COALESCE(
                                    (
                                        SELECT alpr.hourly_rate
                                        FROM award_level_penalty_rates alpr
                                        WHERE alpr.award_level_id = scoped.pay_level_id
                                            AND alpr.employment_basis = scoped.employment_basis
                                            AND alpr.penalty_kind =
                                                CASE scoped.penalty_kind
                                                    WHEN 'delayed_meal_break_saturday' THEN 'saturday_penalty'::award_penalty_kind_enum
                                                    WHEN 'delayed_meal_break_sunday' THEN 'sunday_penalty'::award_penalty_kind_enum
                                                    WHEN 'delayed_meal_break_public_holiday' THEN 'public_holiday_penalty'::award_penalty_kind_enum
                                                    ELSE NULL::award_penalty_kind_enum
                                                END
                                            AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) <= scoped.segment_date)
                                            AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) >= scoped.segment_date)
                                            AND (scoped.approved_at IS NULL OR alpr.created_at <= scoped.approved_at)
                                        ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) DESC NULLS LAST, alpr.created_at DESC
                                        LIMIT 1
                                    ),
                                    scoped.base_rate
                                )
                            ELSE scoped.base_rate
                        END
                    ) + (scoped.permanent_base_rate * 0.5)
                    + CASE
                        WHEN scoped.penalty_kind = 'delayed_meal_break_weekday'
                            AND scoped.source_segment_name IN ('evening_after_7pm', 'late_night_after_midnight')
                        THEN COALESCE(
                            (
                                SELECT atpa.hourly_amount
                                FROM award_time_penalty_allowances atpa
                                WHERE atpa.award_fixed_id = scoped.award_fixed_id
                                    AND atpa.penalty_kind =
                                        CASE scoped.source_segment_name
                                            WHEN 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum
                                            WHEN 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum
                                            ELSE NULL::award_penalty_kind_enum
                                        END
                                    AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) <= scoped.segment_date)
                                    AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, atpa.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, atpa.operative_to) >= scoped.segment_date)
                                    AND (scoped.approved_at IS NULL OR atpa.created_at <= scoped.approved_at)
                                ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) DESC NULLS LAST, atpa.created_at DESC
                                LIMIT 1
                            ),
                            (
                                SELECT GREATEST(alpr.hourly_rate - scoped.base_rate, 0)
                                FROM award_level_penalty_rates alpr
                                WHERE alpr.award_level_id = scoped.pay_level_id
                                    AND alpr.employment_basis = scoped.employment_basis
                                    AND alpr.penalty_kind =
                                        CASE scoped.source_segment_name
                                            WHEN 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum
                                            WHEN 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum
                                            ELSE NULL::award_penalty_kind_enum
                                        END
                                    AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) <= scoped.segment_date)
                                    AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) >= scoped.segment_date)
                                    AND (scoped.approved_at IS NULL OR alpr.created_at <= scoped.approved_at)
                                ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) DESC NULLS LAST, alpr.created_at DESC
                                LIMIT 1
                            ),
                            0::NUMERIC(12,4)
                        )
                        ELSE 0::NUMERIC(12,4)
                    END
                WHEN scoped.penalty_kind IN ('saturday_penalty', 'sunday_penalty', 'public_holiday_penalty') THEN
                    COALESCE(
                        (
                            SELECT alpr.hourly_rate
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) <= scoped.segment_date)
                                AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) >= scoped.segment_date)
                                AND (scoped.approved_at IS NULL OR alpr.created_at <= scoped.approved_at)
                            ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) DESC NULLS LAST, alpr.created_at DESC
                            LIMIT 1
                        ),
                        scoped.base_rate
                    )
                WHEN scoped.penalty_kind IN ('evening_after_7pm', 'late_night_after_midnight') THEN
                    scoped.base_rate + COALESCE(
                        (
                            SELECT atpa.hourly_amount
                            FROM award_time_penalty_allowances atpa
                            WHERE atpa.award_fixed_id = scoped.award_fixed_id
                                AND atpa.penalty_kind = scoped.penalty_kind
                                AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) <= scoped.segment_date)
                                AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, atpa.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, atpa.operative_to) >= scoped.segment_date)
                                AND (scoped.approved_at IS NULL OR atpa.created_at <= scoped.approved_at)
                            ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, atpa.operative_from) DESC NULLS LAST, atpa.created_at DESC
                            LIMIT 1
                        ),
                        (
                            SELECT GREATEST(alpr.hourly_rate - scoped.base_rate, 0)
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) IS NULL OR venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) <= scoped.segment_date)
                                AND (scoped.approved_at IS NOT NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) IS NULL OR venue_effective_award_rate_to(scoped.venue_week_starts_on, alpr.operative_to) >= scoped.segment_date)
                                AND (scoped.approved_at IS NULL OR alpr.created_at <= scoped.approved_at)
                            ORDER BY venue_effective_award_rate_from(scoped.venue_week_starts_on, alpr.operative_from) DESC NULLS LAST, alpr.created_at DESC
                            LIMIT 1
                        ),
                        0::NUMERIC(12,4)
                    )
                ELSE scoped.base_rate
            END AS segment_hourly_rate
        FROM (
            SELECT
                ss.id,
                ss.staff_id,
                ss.worked_on,
                ss.break_minutes,
                ss.paid_minutes,
                ss.shift_type_id,
                ss.shift_type_name,
                ss.pay_level_id,
                ss.imported_xero_pay_item_id,
                ss.pay_level_name,
                ss.award_fixed_id,
                ss.employment_basis,
                ss.venue_week_starts_on,
                ss.permanent_base_rate,
                ss.staff_pay_version_id,
                ss.shift_type_pay_version_id,
                ss.approved_at,
                ss.segment_name,
                ss.segment_name AS source_segment_name,
                ss.segment_date,
                CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM staff s
                        JOIN venue_config vc ON vc.venue_id = s.venue_id
                        JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                            AND ph.holiday_date = ss.segment_date
                            AND ph.is_regional = FALSE
                        WHERE s.id = ss.staff_id
                        LIMIT 1
                    ) THEN 'public_holiday_penalty'::award_penalty_kind_enum
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 6 THEN 'saturday_penalty'::award_penalty_kind_enum
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 0 THEN 'sunday_penalty'::award_penalty_kind_enum
                    WHEN ss.segment_name = 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum
                    WHEN ss.segment_name = 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum
                    ELSE NULL::award_penalty_kind_enum
                END AS penalty_kind,
                GREATEST(
                    ss.worked_segment_minutes
                    - ss.break_segment_minutes
                    - GREATEST(ss.delayed_segment_minutes - ss.break_delayed_segment_minutes, 0),
                    0
                ) AS segment_minutes,
                ss.base_rate,
                ss.sort_index
            FROM segment_scopes ss

            UNION ALL

            SELECT
                ss.id,
                ss.staff_id,
                ss.worked_on,
                ss.break_minutes,
                ss.paid_minutes,
                ss.shift_type_id,
                ss.shift_type_name,
                ss.pay_level_id,
                ss.imported_xero_pay_item_id,
                ss.pay_level_name,
                ss.award_fixed_id,
                ss.employment_basis,
                ss.venue_week_starts_on,
                ss.permanent_base_rate,
                ss.staff_pay_version_id,
                ss.shift_type_pay_version_id,
                ss.approved_at,
                CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM staff s
                        JOIN venue_config vc ON vc.venue_id = s.venue_id
                        JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                            AND ph.holiday_date = ss.segment_date
                            AND ph.is_regional = FALSE
                        WHERE s.id = ss.staff_id
                        LIMIT 1
                    ) THEN 'delayed_meal_break_public_holiday'
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 6 THEN 'delayed_meal_break_saturday'
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 0 THEN 'delayed_meal_break_sunday'
                    ELSE 'delayed_meal_break_weekday'
                END AS segment_name,
                ss.segment_name AS source_segment_name,
                ss.segment_date,
                CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM staff s
                        JOIN venue_config vc ON vc.venue_id = s.venue_id
                        JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                            AND ph.holiday_date = ss.segment_date
                            AND ph.is_regional = FALSE
                        WHERE s.id = ss.staff_id
                        LIMIT 1
                    ) THEN 'delayed_meal_break_public_holiday'::award_penalty_kind_enum
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 6 THEN 'delayed_meal_break_saturday'::award_penalty_kind_enum
                    WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 0 THEN 'delayed_meal_break_sunday'::award_penalty_kind_enum
                    ELSE 'delayed_meal_break_weekday'::award_penalty_kind_enum
                END AS penalty_kind,
                GREATEST(ss.delayed_segment_minutes - ss.break_delayed_segment_minutes, 0) AS segment_minutes,
                ss.base_rate,
                ss.sort_index + 5 AS sort_index
            FROM segment_scopes ss
        ) scoped
    ),
    public_holiday_minimum_rows AS (
        SELECT
            ph.id,
            'public_holiday_minimum_top_up'::TEXT AS segment_name,
            ph.segment_date,
            CASE ph.employment_basis
                WHEN 'casual' THEN 120
                ELSE 240
            END - ph.paid_minutes AS segment_minutes,
            ph.shift_type_id,
            ph.shift_type_name,
            ph.pay_level_id,
            ph.pay_level_name,
            'public_holiday_penalty'::award_penalty_kind_enum AS penalty_kind,
            ph.base_rate,
            ph.segment_hourly_rate,
            1000 AS sort_index
        FROM (
            SELECT DISTINCT ON (sr.id) sr.*
            FROM segment_rows sr
            WHERE sr.imported_xero_pay_item_id IS NULL
                AND sr.penalty_kind = 'public_holiday_penalty'
                AND sr.segment_minutes > 0
            ORDER BY sr.id, sr.segment_date ASC, sr.sort_index ASC
        ) ph
        WHERE ph.paid_minutes <
            CASE ph.employment_basis
                WHEN 'casual' THEN 120
                ELSE 240
            END
    ),
    payable_segments AS (
        SELECT
            sr.id,
            sr.segment_name,
            sr.segment_date,
            sr.segment_minutes,
            sr.shift_type_id,
            sr.shift_type_name,
            sr.pay_level_id,
            sr.pay_level_name,
            sr.penalty_kind,
            sr.base_rate,
            sr.segment_hourly_rate,
            sr.sort_index
        FROM segment_rows sr

        UNION ALL

        SELECT
            phmr.id,
            phmr.segment_name,
            phmr.segment_date,
            phmr.segment_minutes,
            phmr.shift_type_id,
            phmr.shift_type_name,
            phmr.pay_level_id,
            phmr.pay_level_name,
            phmr.penalty_kind,
            phmr.base_rate,
            phmr.segment_hourly_rate,
            phmr.sort_index
        FROM public_holiday_minimum_rows phmr
    ),
    segment_json AS (
        SELECT
            sr.id,
            COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'segment', sr.segment_name,
                        'segmentDate', sr.segment_date,
                        'minutes', sr.segment_minutes,
                        'shiftTypeId', sr.shift_type_id,
                        'shiftTypeName', sr.shift_type_name,
                        'payLevelId', sr.pay_level_id,
                        'payLevelName', sr.pay_level_name,
                        'penaltyKind', sr.penalty_kind,
                        'dayRuleMultiplier', CASE WHEN sr.base_rate = 0 THEN 1 ELSE ROUND((sr.segment_hourly_rate / sr.base_rate), 3) END,
                        'weekendMultiplier', CASE WHEN sr.penalty_kind IN ('saturday_penalty', 'sunday_penalty') AND sr.base_rate <> 0 THEN ROUND((sr.segment_hourly_rate / sr.base_rate), 3) ELSE 1 END,
                        'multiplier', CASE WHEN sr.base_rate = 0 THEN 1 ELSE ROUND((sr.segment_hourly_rate / sr.base_rate), 3) END,
                        'baseRate', sr.base_rate,
                        'amount', ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2)
                    )
                    ORDER BY sr.sort_index ASC
                ) FILTER (WHERE sr.segment_minutes > 0),
                jsonb_build_array()
            ) AS segments
        FROM payable_segments sr
        GROUP BY sr.id
    ),
    segment_totals AS (
        SELECT
            sr.id,
            COALESCE(
                SUM(sr.segment_minutes) FILTER (WHERE sr.segment_minutes > 0),
                0
            ) AS paid_minutes,
            COALESCE(
                SUM(ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2))
                    FILTER (WHERE sr.segment_minutes > 0),
                0::NUMERIC(12,2)
            ) AS total_amount
        FROM payable_segments sr
        GROUP BY sr.id
    ),
    payload AS (
        SELECT jsonb_build_object(
            'entryId', pw.id,
            'staffId', pw.staff_id,
            'workedOn', pw.worked_on,
            'shiftTypeId', pw.shift_type_id,
            'shiftTypeName', pw.shift_type_name,
            'payLevelId', pw.pay_level_id,
            'payLevelName', pw.pay_level_name,
            'staffPayVersionId', pw.staff_pay_version_id,
            'shiftTypePayVersionId', pw.shift_type_pay_version_id,
            'breakMinutes', pw.break_minutes,
            'paidMinutes', pw.paid_minutes,
            'segments', sj.segments,
            'totals', jsonb_build_object(
                'paidMinutes', st.paid_minutes,
                'totalAmount', st.total_amount
            )
        ) AS pay_json
        FROM paid_window pw
        LEFT JOIN segment_json sj ON sj.id = pw.id
        LEFT JOIN segment_totals st ON st.id = pw.id
    )
    SELECT COALESCE(
        (SELECT pay_json FROM payload),
        jsonb_build_object(
            'entryId', p_entry_id,
            'error', 'timesheet_entry_not_found',
            'segments', jsonb_build_array(),
            'totals', jsonb_build_object('paidMinutes', 0, 'totalAmount', 0)
        )
    );
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION calculate_timesheet_pay_range(p_staff_id UUID, p_from_date DATE, p_to_date DATE)
RETURNS JSONB
AS $$
    SELECT COALESCE(
        jsonb_agg(calculate_timesheet_pay(te.id) ORDER BY te.starts_at ASC, te.id ASC),
        jsonb_build_array()
    )
    FROM timesheet_entries te
    WHERE te.staff_id = p_staff_id
        AND (te.starts_at AT TIME ZONE te.timezone)::DATE >= p_from_date
        AND (te.starts_at AT TIME ZONE te.timezone)::DATE <= p_to_date
        AND te.deleted_at IS NULL;
$$ LANGUAGE SQL;


DROP FUNCTION bepis_first_civil_occurrence(TIMESTAMP WITHOUT TIME ZONE, TEXT);
