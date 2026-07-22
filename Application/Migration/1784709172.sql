-- Update Hospitality Award meal-break and public-holiday minimum calculations.

CREATE OR REPLACE FUNCTION calculate_timesheet_pay(p_entry_id UUID)
RETURNS JSONB
AS $$
    WITH entry_data AS (
        SELECT
            te.*,
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
            e.start_time,
            e.end_time,
            e.had_break,
            e.break_start_time,
            e.break_end_time,
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
            (EXTRACT(EPOCH FROM e.start_time) / 60)::INT AS start_minute_of_day,
            (
                CASE
                    WHEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                        THEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT + 1440
                    ELSE (EXTRACT(EPOCH FROM e.end_time) / 60)::INT
                END
            ) AS end_minute_of_day,
            CASE
                WHEN e.had_break
                    AND e.break_start_time IS NOT NULL
                    AND e.break_end_time IS NOT NULL
                    AND e.break_minutes > 0
                THEN
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT < (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT
                    END
                ELSE NULL
            END AS break_start_minute_of_day,
            CASE
                WHEN e.had_break
                    AND e.break_start_time IS NOT NULL
                    AND e.break_end_time IS NOT NULL
                    AND e.break_minutes > 0
                THEN
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.break_start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT + 1440
                        WHEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT < (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.break_end_time) / 60)::INT
                    END
                ELSE NULL
            END AS break_end_minute_of_day,
            GREATEST(
                (
                    CASE
                        WHEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT <= (EXTRACT(EPOCH FROM e.start_time) / 60)::INT
                            THEN (EXTRACT(EPOCH FROM e.end_time) / 60)::INT + 1440
                        ELSE (EXTRACT(EPOCH FROM e.end_time) / 60)::INT
                    END
                ) - (EXTRACT(EPOCH FROM e.start_time) / 60)::INT - e.break_minutes,
                0
            ) AS paid_minutes,
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
        SELECT
            r.*,
            CASE
                WHEN r.break_start_minute_of_day IS NOT NULL AND r.break_end_minute_of_day IS NOT NULL
                    THEN LEAST(r.end_minute_of_day, 1860)
                ELSE LEAST(r.start_minute_of_day + r.paid_minutes, 1860)
            END AS paid_end_minute_of_day
        FROM labelled r
    ),
    delayed_meal_break_window AS (
        SELECT
            pw.*,
            CASE
                WHEN pw.end_minute_of_day - pw.start_minute_of_day > 360
                    AND NOT (
                        pw.break_start_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                        AND pw.break_start_minute_of_day >= pw.start_minute_of_day + 120
                        AND pw.break_start_minute_of_day <= pw.start_minute_of_day + 360
                    )
                THEN pw.start_minute_of_day + 360
                ELSE NULL
            END AS delayed_meal_break_start_minute,
            CASE
                WHEN pw.end_minute_of_day - pw.start_minute_of_day > 360
                    AND NOT (
                        pw.break_start_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day IS NOT NULL
                        AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                        AND pw.break_start_minute_of_day >= pw.start_minute_of_day + 120
                        AND pw.break_start_minute_of_day <= pw.start_minute_of_day + 360
                    )
                THEN
                    CASE
                        WHEN pw.break_start_minute_of_day IS NOT NULL
                            AND pw.break_end_minute_of_day IS NOT NULL
                            AND pw.break_end_minute_of_day - pw.break_start_minute_of_day >= 30
                            AND pw.break_start_minute_of_day > pw.start_minute_of_day + 360
                        THEN pw.break_start_minute_of_day
                        ELSE pw.end_minute_of_day
                    END
                ELSE NULL
            END AS delayed_meal_break_end_minute
        FROM paid_window pw
    ),
    segment_windows AS (
        SELECT *
        FROM (
            VALUES
                ('late_night_after_midnight'::TEXT, 0, 420, 1),
                ('ordinary'::TEXT, 420, 1140, 2),
                ('evening_after_7pm'::TEXT, 1140, 1440, 3),
                ('late_night_after_midnight'::TEXT, 1440, 1860, 4)
        ) AS windows(segment_name, window_start_minute, window_end_minute, sort_index)
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
                pw.id,
                pw.staff_id,
                pw.worked_on,
                pw.break_minutes,
                pw.paid_minutes,
                pw.break_start_minute_of_day,
                pw.break_end_minute_of_day,
                pw.shift_type_id,
                pw.shift_type_name,
                pw.pay_level_id,
                pw.imported_xero_pay_item_id,
                pw.pay_level_name,
                pw.award_fixed_id,
                pw.employment_basis,
                pw.venue_week_starts_on,
                pw.permanent_base_rate,
                pw.staff_pay_version_id,
                pw.shift_type_pay_version_id,
                pw.approved_at,
                scoped_segments.segment_name,
                scoped_segments.source_segment_name,
                scoped_segments.segment_date,
                scoped_segments.penalty_kind,
                scoped_segments.segment_minutes,
                pw.base_rate,
                scoped_segments.sort_index
            FROM delayed_meal_break_window pw
            CROSS JOIN LATERAL (
                SELECT
                    sw.segment_name,
                    sw.segment_name AS source_segment_name,
                    (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END) AS segment_date,
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'public_holiday_penalty'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'saturday_penalty'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'sunday_penalty'::award_penalty_kind_enum
                        WHEN sw.segment_name = 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum
                        WHEN sw.segment_name = 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum
                        ELSE NULL::award_penalty_kind_enum
                    END AS penalty_kind,
                    GREATEST(
                        GREATEST(
                            LEAST(pw.paid_end_minute_of_day, sw.window_end_minute)
                            - GREATEST(pw.start_minute_of_day, sw.window_start_minute),
                            0
                        )::INT
                        - CASE
                            WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                GREATEST(
                                    LEAST(pw.break_end_minute_of_day, sw.window_end_minute)
                                    - GREATEST(pw.break_start_minute_of_day, sw.window_start_minute),
                                    0
                                )::INT
                            ELSE 0
                        END
                        - GREATEST(
                            CASE
                                WHEN pw.delayed_meal_break_start_minute IS NOT NULL AND pw.delayed_meal_break_end_minute IS NOT NULL THEN
                                    GREATEST(
                                        LEAST(pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                        - GREATEST(pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                        0
                                    )::INT
                                    - CASE
                                        WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                            GREATEST(
                                                LEAST(pw.break_end_minute_of_day, pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                                - GREATEST(pw.break_start_minute_of_day, pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                                0
                                            )::INT
                                        ELSE 0
                                    END
                                ELSE 0
                            END,
                            0
                        ),
                        0
                    ) AS segment_minutes,
                    sw.sort_index * 10 AS sort_index
                FROM segment_windows sw

                UNION ALL

                SELECT
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'delayed_meal_break_public_holiday'
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'delayed_meal_break_saturday'
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'delayed_meal_break_sunday'
                        ELSE 'delayed_meal_break_weekday'
                    END AS segment_name,
                    sw.segment_name AS source_segment_name,
                    (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END) AS segment_date,
                    CASE
                        WHEN EXISTS (
                            SELECT 1
                            FROM staff s
                            JOIN venue_config vc ON vc.venue_id = s.venue_id
                            JOIN public_holidays ph ON ph.jurisdiction = vc.public_holiday_jurisdiction
                                AND ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)
                                AND ph.is_regional = FALSE
                            WHERE s.id = pw.staff_id
                            LIMIT 1
                        ) THEN 'delayed_meal_break_public_holiday'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'delayed_meal_break_saturday'::award_penalty_kind_enum
                        WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 0 THEN 'delayed_meal_break_sunday'::award_penalty_kind_enum
                        ELSE 'delayed_meal_break_weekday'::award_penalty_kind_enum
                    END AS penalty_kind,
                    GREATEST(
                        CASE
                            WHEN pw.delayed_meal_break_start_minute IS NOT NULL AND pw.delayed_meal_break_end_minute IS NOT NULL THEN
                                GREATEST(
                                    LEAST(pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                    - GREATEST(pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                    0
                                )::INT
                                - CASE
                                    WHEN pw.break_start_minute_of_day IS NOT NULL AND pw.break_end_minute_of_day IS NOT NULL THEN
                                        GREATEST(
                                            LEAST(pw.break_end_minute_of_day, pw.delayed_meal_break_end_minute, sw.window_end_minute)
                                            - GREATEST(pw.break_start_minute_of_day, pw.delayed_meal_break_start_minute, sw.window_start_minute),
                                            0
                                        )::INT
                                    ELSE 0
                                END
                            ELSE 0
                        END,
                        0
                    ) AS segment_minutes,
                    sw.sort_index * 10 + 5 AS sort_index
                FROM segment_windows sw
            ) scoped_segments
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
            )::INT AS paid_minutes,
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
