-- One-off operator audit. Required psql variables: venue_id, range_start,
-- range_end (inclusive Operational dates). No names, comments or payroll amounts.
\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '15s';

WITH scope AS (
    SELECT :'venue_id'::uuid AS venue_id,
           :'range_start'::date AS range_start,
           :'range_end'::date AS range_end
), intervals AS (
    SELECT 'timesheet_shift'::text AS kind, t.id, t.operational_date,
           t.starts_at, t.ends_at
    FROM timesheet_entries t CROSS JOIN scope s
    WHERE t.venue_id = s.venue_id AND t.deleted_at IS NULL
      AND t.operational_date BETWEEN s.range_start AND s.range_end
    UNION ALL
    SELECT 'timesheet_break', t.id, t.operational_date,
           t.break_starts_at, t.break_ends_at
    FROM timesheet_entries t CROSS JOIN scope s
    WHERE t.venue_id = s.venue_id AND t.deleted_at IS NULL
      AND t.operational_date BETWEEN s.range_start AND s.range_end
      AND t.break_starts_at IS NOT NULL AND t.break_ends_at IS NOT NULL
    UNION ALL
    SELECT 'paid_segment', p.id, t.operational_date, p.starts_at, p.ends_at
    FROM timesheet_entries t
    JOIN timesheet_pay_time_segments p
      ON p.timesheet_pay_calculation_id = t.active_pay_calculation_id
    CROSS JOIN scope s
    WHERE t.venue_id = s.venue_id AND t.deleted_at IS NULL
      AND t.operational_date BETWEEN s.range_start AND s.range_end
    UNION ALL
    SELECT 'roster_shift', r.id, d.operational_date, r.starts_at, r.ends_at
    FROM roster_slots r JOIN roster_days d ON d.id = r.roster_day_id
    CROSS JOIN scope s
    WHERE d.venue_id = s.venue_id AND r.deleted_at IS NULL
      AND d.operational_date BETWEEN s.range_start AND s.range_end
      AND r.starts_at IS NOT NULL AND r.ends_at IS NOT NULL
), measured AS (
    SELECT *, EXTRACT(EPOCH FROM (ends_at - starts_at)) AS elapsed_seconds,
           MOD(EXTRACT(EPOCH FROM (ends_at - starts_at)), 1) <> 0 AS fractional_duration,
           MOD(EXTRACT(EPOCH FROM starts_at), 1) <> 0
             OR MOD(EXTRACT(EPOCH FROM ends_at), 1) <> 0 AS fractional_endpoint
    FROM intervals
), ranked AS (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY kind ORDER BY (fractional_duration OR fractional_endpoint) DESC, operational_date, id
    ) AS sample_rank
    FROM measured
)
SELECT kind, COUNT(*) AS intervals_checked,
       COUNT(*) FILTER (WHERE fractional_duration) AS fractional_durations,
       COUNT(*) FILTER (WHERE fractional_endpoint) AS fractional_endpoints,
       COALESCE(JSONB_AGG(JSONB_BUILD_OBJECT(
           'id', id, 'operational_date', operational_date,
           'elapsed_seconds', elapsed_seconds,
           'rounded_seconds', ROUND(elapsed_seconds),
           'fractional_endpoint', fractional_endpoint
       ) ORDER BY operational_date, id)
       FILTER (WHERE (fractional_duration OR fractional_endpoint) AND sample_rank <= 100), '[]'::jsonb) AS examples
FROM ranked
GROUP BY kind
ORDER BY kind;

ROLLBACK;
