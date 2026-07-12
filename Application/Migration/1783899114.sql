-- GitHub #151: retire configuration tables whose runtime callers have shipped.
-- Deployment remains operator-gated by the reviewed backup/restore runbook.
-- Fail closed if rows appeared after the approved Stage A review.

LOCK TABLE
    report_definition_shift_type_filters,
    report_definitions,
    xero_payroll_calendar_selections
IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM report_definition_shift_type_filters LIMIT 1)
        OR EXISTS (SELECT 1 FROM report_definitions LIMIT 1)
        OR EXISTS (SELECT 1 FROM xero_payroll_calendar_selections LIMIT 1)
    THEN
        RAISE EXCEPTION 'legacy schema retirement #151 stopped because reviewed tables are no longer empty';
    END IF;
END;
$$ LANGUAGE plpgsql;

DROP TABLE report_definition_shift_type_filters;
DROP FUNCTION enforce_report_definition_filter_venue_integrity();
DROP TABLE report_definitions;
DROP TABLE xero_payroll_calendar_selections;
