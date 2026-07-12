WITH fingerprints AS (
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
SELECT table_name, row_count, content_fingerprint
FROM fingerprints
ORDER BY table_name;
