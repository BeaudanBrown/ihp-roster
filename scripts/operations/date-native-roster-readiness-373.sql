\set ON_ERROR_STOP on

BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

WITH
violation_rows(check_name, entity_id) AS (
    SELECT 'roster_day_cross_scope', day.id::text
    FROM roster_days day
    LEFT JOIN roster_groups roster_group ON roster_group.id = day.roster_group_id
    LEFT JOIN roster_weeks legacy_week ON legacy_week.id = day.roster_week_id
    WHERE roster_group.id IS NULL
       OR roster_group.venue_id IS DISTINCT FROM day.venue_id
       OR (legacy_week.id IS NOT NULL AND (
            legacy_week.venue_id IS DISTINCT FROM day.venue_id
            OR legacy_week.roster_group_id IS DISTINCT FROM day.roster_group_id
       ))

    UNION ALL
    SELECT 'roster_day_identity_collision', min(day.id::text)
    FROM roster_days day
    GROUP BY day.roster_group_id, day.operational_date
    HAVING count(*) <> 1

    UNION ALL
    SELECT 'roster_slot_operational_day_contradiction', slot.id::text
    FROM roster_slots slot
    JOIN roster_days day ON day.id = slot.roster_day_id
    WHERE slot.starts_at IS NOT NULL
      AND ((slot.starts_at AT TIME ZONE slot.timezone) - INTERVAL '6 hours')::date
            IS DISTINCT FROM day.operational_date

    UNION ALL
    SELECT 'roster_lane_day_mismatch', slot.id::text
    FROM roster_slots slot
    LEFT JOIN roster_lanes lane ON lane.id = slot.roster_lane_id
    WHERE lane.id IS NULL OR lane.roster_day_id IS DISTINCT FROM slot.roster_day_id

    UNION ALL
    SELECT 'roster_slot_legacy_definition_mismatch', slot.id::text
    FROM roster_slots slot
    JOIN roster_lanes lane ON lane.id = slot.roster_lane_id
    WHERE slot.roster_week_slot_definition_id IS DISTINCT FROM lane.legacy_roster_week_slot_definition_id

    UNION ALL
    SELECT 'legacy_lane_definition_mismatch', lane.id::text
    FROM roster_lanes lane
    JOIN roster_days day ON day.id = lane.roster_day_id
    JOIN roster_week_slot_definitions definition
      ON definition.id = lane.legacy_roster_week_slot_definition_id
    WHERE day.roster_week_id IS DISTINCT FROM definition.roster_week_id

    UNION ALL
    SELECT 'template_weekday_identity', template_day.id::text
    FROM roster_template_days template_day
    JOIN roster_template_designs design ON design.id = template_day.roster_template_design_id
    WHERE (design.scale::text = 'week' AND template_day.weekday_index IS NULL)
       OR (design.scale::text = 'day' AND (
            template_day.weekday_index IS NOT NULL OR template_day.day_index <> 0
       ))

    UNION ALL
    SELECT 'template_weekday_duplicate', min(template_day.id::text)
    FROM roster_template_days template_day
    JOIN roster_template_designs design ON design.id = template_day.roster_template_design_id
    WHERE design.scale::text = 'week'
    GROUP BY design.id, template_day.weekday_index
    HAVING count(*) <> 1

    UNION ALL
    SELECT 'template_weekday_identity', design.id::text
    FROM roster_template_designs design
    LEFT JOIN roster_template_days template_day
      ON template_day.roster_template_design_id = design.id
    GROUP BY design.id, design.scale
    HAVING (design.scale::text = 'week' AND (
                count(template_day.id) <> 7
                OR count(DISTINCT template_day.weekday_index) <> 7
           ))
        OR (design.scale::text = 'day' AND count(template_day.id) <> 1)

    UNION ALL
    SELECT 'timesheet_source_operational_day_mismatch', entry.id::text
    FROM timesheet_entries entry
    JOIN roster_slots slot ON slot.id = entry.source_roster_slot_id
    JOIN roster_days day ON day.id = slot.roster_day_id
    WHERE entry.venue_id IS DISTINCT FROM day.venue_id
       OR entry.operational_date IS DISTINCT FROM day.operational_date

    UNION ALL
    SELECT 'approved_entry_active_ledger_mismatch', entry.id::text
    FROM timesheet_entries entry
    LEFT JOIN timesheet_pay_calculations calculation
      ON calculation.id = entry.active_pay_calculation_id
    WHERE entry.is_approved
      AND NOT (entry.legacy_pay_backfill_pending AND entry.active_pay_calculation_id IS NULL)
      AND (
        calculation.id IS NULL
        OR calculation.timesheet_entry_id IS DISTINCT FROM entry.id
        OR calculation.operational_date IS DISTINCT FROM entry.operational_date
        OR calculation.roster_window_start > calculation.operational_date
        OR calculation.operational_date >= calculation.roster_window_start + 7
        OR EXTRACT(DOW FROM calculation.roster_window_start)::int
              IS DISTINCT FROM calculation.roster_week_starts_on
      )

    UNION ALL
    SELECT 'approved_entry_active_ledger_mismatch', calculation.id::text
    FROM timesheet_pay_calculations calculation
    JOIN timesheet_entries entry ON entry.id = calculation.timesheet_entry_id
    WHERE calculation.operational_date IS DISTINCT FROM entry.operational_date
       OR calculation.roster_window_start > calculation.operational_date
       OR calculation.operational_date >= calculation.roster_window_start + 7
       OR EXTRACT(DOW FROM calculation.roster_window_start)::int
            IS DISTINCT FROM calculation.roster_week_starts_on

    UNION ALL
    SELECT 'approved_entry_active_ledger_mismatch', component.id::text
    FROM timesheet_pay_earnings_components component
    WHERE NOT component.xero_mapping_legacy_fallback
      AND component.component_date IS NULL

    UNION ALL
    SELECT 'current_publication_window_mixed', min(day.id::text)
    FROM roster_days day
    JOIN venue_config config ON config.venue_id = day.venue_id
    GROUP BY
        day.venue_id,
        day.roster_group_id,
        day.operational_date
          - ((EXTRACT(DOW FROM day.operational_date)::int - config.roster_week_starts_on + 7) % 7)
    HAVING count(*) FILTER (WHERE day.publication_state::text = 'published') > 0
       AND count(*) FILTER (WHERE day.publication_state::text = 'draft') > 0

    UNION ALL
    SELECT 'notification_window_invalid', run.id::text
    FROM roster_notification_runs run
    WHERE run.window_end IS DISTINCT FROM run.week_start + 7
       OR run.snapshot_schema_version < 1
),
check_catalog(check_name) AS (
    VALUES
        ('roster_day_cross_scope'),
        ('roster_day_identity_collision'),
        ('roster_slot_operational_day_contradiction'),
        ('roster_lane_day_mismatch'),
        ('roster_slot_legacy_definition_mismatch'),
        ('legacy_lane_definition_mismatch'),
        ('template_weekday_identity'),
        ('template_weekday_duplicate'),
        ('timesheet_source_operational_day_mismatch'),
        ('approved_entry_active_ledger_mismatch'),
        ('current_publication_window_mixed'),
        ('notification_window_invalid')
),
check_results AS (
    SELECT
        catalog.check_name,
        (SELECT count(*) FROM violation_rows violation WHERE violation.check_name = catalog.check_name) AS violation_count,
        COALESCE(
            (
                SELECT jsonb_agg(sample.entity_id ORDER BY sample.entity_id)
                FROM (
                    SELECT violation.entity_id
                    FROM violation_rows violation
                    WHERE violation.check_name = catalog.check_name
                    ORDER BY violation.entity_id
                    LIMIT 25
                ) sample
            ),
            '[]'::jsonb
        ) AS sample_entity_ids
    FROM check_catalog catalog
),
counts AS (
    SELECT jsonb_build_object(
        'venues', (SELECT count(*) FROM venue_config),
        'rosterGroups', (SELECT count(*) FROM roster_groups),
        'legacyRosterWeeks', (SELECT count(*) FROM roster_weeks),
        'rosterDays', (SELECT count(*) FROM roster_days),
        'rosterLanes', (SELECT count(*) FROM roster_lanes),
        'activeRosterSlots', (SELECT count(*) FROM roster_slots WHERE deleted_at IS NULL),
        'retainedRosterSlots', (SELECT count(*) FROM roster_slots WHERE deleted_at IS NOT NULL),
        'templateDesigns', (SELECT count(*) FROM roster_template_designs),
        'timesheetEntries', (SELECT count(*) FROM timesheet_entries WHERE deleted_at IS NULL),
        'approvedTimesheetEntries', (SELECT count(*) FROM timesheet_entries WHERE deleted_at IS NULL AND is_approved),
        'notificationRuns', (SELECT count(*) FROM roster_notification_runs)
    ) AS value
),
observations AS (
    SELECT jsonb_build_object(
        'sparseRosterWindows', (
            SELECT count(*)
            FROM (
                SELECT day.roster_group_id, day.roster_week_id
                FROM roster_days day
                GROUP BY day.roster_group_id, day.roster_week_id
                HAVING count(*) < 7
            ) sparse
        ),
        'roughLaneUnionWindows', (
            SELECT count(*)
            FROM (
                SELECT
                    day.roster_group_id,
                    day.operational_date
                      - ((EXTRACT(DOW FROM day.operational_date)::int - config.roster_week_starts_on + 7) % 7) AS window_start
                FROM roster_days day
                JOIN venue_config config ON config.venue_id = day.venue_id
                LEFT JOIN roster_lanes lane ON lane.roster_day_id = day.id AND lane.deleted_at IS NULL
                GROUP BY day.roster_group_id, window_start
                HAVING count(DISTINCT (lane.name, lane.sort_order)) > count(DISTINCT lane.name)
            ) rough
        ),
        'historicalAdHocLocalDateDifferences', (
            SELECT count(*)
            FROM timesheet_entries entry
            WHERE entry.source_roster_slot_id IS NULL
              AND entry.operational_date IS DISTINCT FROM (entry.starts_at AT TIME ZONE entry.timezone)::date
        ),
        'legacyApprovedEntriesPendingPayBackfill', (
            SELECT count(*)
            FROM timesheet_entries entry
            WHERE entry.is_approved
              AND entry.legacy_pay_backfill_pending
              AND entry.active_pay_calculation_id IS NULL
        ),
        'legacyLedgerComponents', (
            SELECT count(*)
            FROM timesheet_pay_earnings_components component
            WHERE component.xero_mapping_legacy_fallback
        ),
        'activeNotificationRuns', (
            SELECT count(DISTINCT run.id)
            FROM roster_notification_runs run
            JOIN app_jobs job
              ON job.related_table = 'roster_notification_runs'
             AND job.related_id = run.id
             AND job.job_kind = 'roster_notification_delivery'
            WHERE job.status::text IN ('job_status_not_started', 'job_status_running', 'job_status_retry')
        )
    ) AS value
)
SELECT jsonb_pretty(jsonb_build_object(
    'schema', 'date-native-roster-readiness-v1',
    'capture', jsonb_build_object(
        'database', current_database(),
        'transactionReadOnly', current_setting('transaction_read_only'),
        'capturedAt', to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
    ),
    'counts', counts.value,
    'observations', observations.value,
    'checks', (
        SELECT jsonb_agg(jsonb_build_object(
            'name', result.check_name,
            'violationCount', result.violation_count,
            'sampleEntityIds', result.sample_entity_ids
        ) ORDER BY result.check_name)
        FROM check_results result
    ),
    'totalViolationCount', (SELECT sum(result.violation_count) FROM check_results result)
))
FROM counts, observations;

COMMIT;
