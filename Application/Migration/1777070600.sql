CREATE OR REPLACE FUNCTION calculate_timesheet_pay(p_entry_id UUID)
RETURNS JSONB
AS $$
    WITH entry_data AS (
        SELECT
            te.*,
            pcs.version_label AS pay_config_snapshot_version,
            pcs.snapshot AS pay_config_snapshot
        FROM timesheet_entries te
        LEFT JOIN pay_config_snapshots pcs ON pcs.id = te.pay_config_snapshot_id
        WHERE te.id = p_entry_id
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
            e.pay_config_snapshot_id,
            e.pay_config_snapshot_version,
            e.pay_config_snapshot,
            (
                SELECT s.employment_basis
                FROM staff s
                WHERE s.id = e.staff_id
                LIMIT 1
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
            resolve_effective_pay_level(
                e.staff_id,
                e.shift_type_id,
                EXTRACT(DOW FROM e.worked_on)::INT
            ) AS pay_level_id
        FROM entry_data e
    ),
    labelled AS (
        SELECT
            r.*,
            CASE
                WHEN r.pay_config_snapshot_id IS NOT NULL THEN
                    (
                        SELECT shift_type ->> 'name'
                        FROM jsonb_array_elements(COALESCE(r.pay_config_snapshot -> 'shiftTypes', '[]'::JSONB)) shift_type
                        WHERE (shift_type ->> 'id')::UUID = r.shift_type_id
                        LIMIT 1
                    )
                ELSE
                    (
                        SELECT st.name
                        FROM shift_types st
                        WHERE st.id = r.shift_type_id
                        LIMIT 1
                    )
            END AS shift_type_name,
            (
                SELECT COALESCE(al.classification_level || ' - ', '') || al.classification
                FROM award_levels al
                WHERE al.id = r.pay_level_id
                LIMIT 1
            ) AS pay_level_name,
            (
                SELECT al.award_fixed_id
                FROM award_levels al
                WHERE al.id = r.pay_level_id
                LIMIT 1
            ) AS award_fixed_id,
            COALESCE(
                (
                    SELECT albr.hourly_rate
                    FROM award_level_base_rates albr
                    WHERE albr.award_level_id = r.pay_level_id
                        AND albr.employment_basis = r.employment_basis
                        AND (albr.operative_from IS NULL OR albr.operative_from <= r.worked_on)
                        AND (albr.operative_to IS NULL OR albr.operative_to >= r.worked_on)
                    ORDER BY albr.operative_from DESC NULLS LAST, albr.created_at DESC
                    LIMIT 1
                ),
                0::NUMERIC(12,4)
            ) AS base_rate
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
                WHEN scoped.penalty_kind IN ('saturday_penalty', 'sunday_penalty', 'public_holiday_penalty') THEN
                    COALESCE(
                        (
                            SELECT alpr.hourly_rate
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (alpr.operative_from IS NULL OR alpr.operative_from <= scoped.segment_date)
                                AND (alpr.operative_to IS NULL OR alpr.operative_to >= scoped.segment_date)
                            ORDER BY alpr.operative_from DESC NULLS LAST, alpr.created_at DESC
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
                                AND (atpa.operative_from IS NULL OR atpa.operative_from <= scoped.segment_date)
                                AND (atpa.operative_to IS NULL OR atpa.operative_to >= scoped.segment_date)
                            ORDER BY atpa.operative_from DESC NULLS LAST, atpa.created_at DESC
                            LIMIT 1
                        ),
                        (
                            SELECT GREATEST(alpr.hourly_rate - scoped.base_rate, 0)
                            FROM award_level_penalty_rates alpr
                            WHERE alpr.award_level_id = scoped.pay_level_id
                                AND alpr.employment_basis = scoped.employment_basis
                                AND alpr.penalty_kind = scoped.penalty_kind
                                AND (alpr.operative_from IS NULL OR alpr.operative_from <= scoped.segment_date)
                                AND (alpr.operative_to IS NULL OR alpr.operative_to >= scoped.segment_date)
                            ORDER BY alpr.operative_from DESC NULLS LAST, alpr.created_at DESC
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
                pw.pay_level_name,
                pw.award_fixed_id,
                pw.employment_basis,
                pw.pay_config_snapshot_id,
                pw.pay_config_snapshot_version,
                pw.pay_config_snapshot,
                sw.segment_name,
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
                END AS segment_minutes,
                pw.base_rate,
                sw.sort_index
            FROM paid_window pw
            CROSS JOIN segment_windows sw
        ) scoped
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
        FROM segment_rows sr
        GROUP BY sr.id
    ),
    segment_totals AS (
        SELECT
            sr.id,
            COALESCE(
                SUM(ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2))
                    FILTER (WHERE sr.segment_minutes > 0),
                0::NUMERIC(12,2)
            ) AS total_amount
        FROM segment_rows sr
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
            'payConfigSnapshotId', pw.pay_config_snapshot_id,
            'payConfigSnapshotVersion', pw.pay_config_snapshot_version,
            'breakMinutes', pw.break_minutes,
            'paidMinutes', pw.paid_minutes,
            'segments', sj.segments,
            'totals', jsonb_build_object(
                'paidMinutes', pw.paid_minutes,
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
