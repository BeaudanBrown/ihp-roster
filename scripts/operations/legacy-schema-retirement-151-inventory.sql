WITH
report_definition_groups AS (
    SELECT
        venue_id::TEXT AS venue_id,
        engine,
        is_active,
        (archived_at IS NOT NULL) AS is_archived,
        COUNT(*)::BIGINT AS row_count
    FROM report_definitions
    GROUP BY venue_id, engine, is_active, (archived_at IS NOT NULL)
),
report_filter_groups AS (
    SELECT
        definitions.venue_id::TEXT AS venue_id,
        (filters.deleted_at IS NOT NULL) AS is_deleted,
        COUNT(*)::BIGINT AS row_count
    FROM report_definition_shift_type_filters AS filters
    JOIN report_definitions AS definitions ON definitions.id = filters.report_definition_id
    GROUP BY definitions.venue_id, (filters.deleted_at IS NOT NULL)
),
xero_selection_groups AS (
    SELECT
        selections.venue_id::TEXT AS venue_id,
        selections.calendar_status,
        COUNT(*)::BIGINT AS row_count,
        COUNT(*) FILTER (WHERE selections.xero_payroll_calendar_id IS NOT NULL)::BIGINT AS rows_with_calendar_id,
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1
                FROM xero_payroll_calendars AS calendars
                WHERE calendars.xero_connection_id = selections.xero_connection_id
                    AND calendars.xero_payroll_calendar_id = selections.xero_payroll_calendar_id
            )
        )::BIGINT AS rows_matching_retained_calendar,
        COUNT(*) FILTER (
            WHERE EXISTS (
                SELECT 1
                FROM xero_pay_runs AS pay_runs
                WHERE pay_runs.xero_connection_id = selections.xero_connection_id
                    AND pay_runs.xero_payroll_calendar_id = selections.xero_payroll_calendar_id
            )
        )::BIGINT AS rows_matching_retained_pay_run
    FROM xero_payroll_calendar_selections AS selections
    GROUP BY selections.venue_id, selections.calendar_status
),
integrity AS (
    SELECT JSONB_BUILD_OBJECT(
        'reportFiltersMissingDefinition', (
            SELECT COUNT(*)
            FROM report_definition_shift_type_filters AS filters
            LEFT JOIN report_definitions AS definitions ON definitions.id = filters.report_definition_id
            WHERE definitions.id IS NULL
        ),
        'reportFiltersMissingShiftType', (
            SELECT COUNT(*)
            FROM report_definition_shift_type_filters AS filters
            LEFT JOIN shift_types ON shift_types.id = filters.shift_type_id
            WHERE shift_types.id IS NULL
        ),
        'reportFilterVenueMismatches', (
            SELECT COUNT(*)
            FROM report_definition_shift_type_filters AS filters
            JOIN report_definitions AS definitions ON definitions.id = filters.report_definition_id
            JOIN shift_types ON shift_types.id = filters.shift_type_id
            WHERE definitions.venue_id <> shift_types.venue_id
        ),
        'xeroSelectionsMissingConnection', (
            SELECT COUNT(*)
            FROM xero_payroll_calendar_selections AS selections
            LEFT JOIN xero_connections AS connections ON connections.id = selections.xero_connection_id
            WHERE connections.id IS NULL
        ),
        'xeroSelectionVenueMismatches', (
            SELECT COUNT(*)
            FROM xero_payroll_calendar_selections AS selections
            JOIN xero_connections AS connections ON connections.id = selections.xero_connection_id
            WHERE connections.venue_id <> selections.venue_id
        )
    ) AS value
),
fingerprints AS (
    SELECT
        'report_definitions'::TEXT AS table_name,
        COUNT(*)::BIGINT AS row_count,
        MD5(COALESCE(STRING_AGG(MD5(TO_JSONB(row_value)::TEXT), '' ORDER BY row_value.id::TEXT), '')) AS content_fingerprint
    FROM report_definitions AS row_value

    UNION ALL

    SELECT
        'report_definition_shift_type_filters'::TEXT,
        COUNT(*)::BIGINT,
        MD5(COALESCE(STRING_AGG(MD5(TO_JSONB(row_value)::TEXT), '' ORDER BY row_value.id::TEXT), ''))
    FROM report_definition_shift_type_filters AS row_value

    UNION ALL

    SELECT
        'xero_payroll_calendar_selections'::TEXT,
        COUNT(*)::BIGINT,
        MD5(COALESCE(STRING_AGG(MD5(TO_JSONB(row_value)::TEXT), '' ORDER BY row_value.id::TEXT), ''))
    FROM xero_payroll_calendar_selections AS row_value
)
SELECT JSONB_PRETTY(JSONB_BUILD_OBJECT(
    'capture', JSONB_BUILD_OBJECT(
        'capturedAt', CURRENT_TIMESTAMP,
        'database', CURRENT_DATABASE(),
        'databaseUser', CURRENT_USER,
        'serverAddress', COALESCE(INET_SERVER_ADDR()::TEXT, 'local-socket'),
        'serverPort', INET_SERVER_PORT(),
        'serverVersion', CURRENT_SETTING('server_version'),
        'transactionReadOnly', CURRENT_SETTING('transaction_read_only')
    ),
    'tableCounts', JSONB_BUILD_OBJECT(
        'report_definitions', (SELECT COUNT(*) FROM report_definitions),
        'report_definition_shift_type_filters', (SELECT COUNT(*) FROM report_definition_shift_type_filters),
        'xero_payroll_calendar_selections', (SELECT COUNT(*) FROM xero_payroll_calendar_selections)
    ),
    'reportDefinitionsByVenue', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(group_row) ORDER BY group_row.venue_id, group_row.engine, group_row.is_active, group_row.is_archived)
        FROM report_definition_groups AS group_row
    ), '[]'::JSONB),
    'reportFiltersByVenue', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(group_row) ORDER BY group_row.venue_id, group_row.is_deleted)
        FROM report_filter_groups AS group_row
    ), '[]'::JSONB),
    'xeroSelectionsByVenue', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(group_row) ORDER BY group_row.venue_id, group_row.calendar_status)
        FROM xero_selection_groups AS group_row
    ), '[]'::JSONB),
    'integrityAnomalies', (SELECT value FROM integrity),
    'fingerprints', COALESCE((
        SELECT JSONB_AGG(TO_JSONB(fingerprint_row) ORDER BY fingerprint_row.table_name)
        FROM fingerprints AS fingerprint_row
    ), '[]'::JSONB)
));
