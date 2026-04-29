CREATE OR REPLACE FUNCTION enforce_roster_week_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM roster_groups rg
        WHERE rg.id = NEW.roster_group_id
            AND rg.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'roster week venue_id must match roster_group_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_slot_name_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM roster_groups rg
        WHERE rg.id = NEW.roster_group_id
            AND rg.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'slot name venue_id must match roster_group_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_roster_group_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        JOIN roster_groups rg ON rg.id = NEW.roster_group_id
        WHERE s.id = NEW.staff_id
            AND s.venue_id = rg.venue_id
    ) THEN
        RAISE EXCEPTION 'staff roster group assignment must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_availability_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'staff availability venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_staff_shift_preference_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        JOIN roster_groups rg ON rg.id = NEW.roster_group_id
        JOIN slot_names sn ON sn.id = NEW.slot_name_id
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
            AND rg.venue_id = NEW.venue_id
            AND sn.venue_id = NEW.venue_id
            AND sn.roster_group_id = NEW.roster_group_id
    ) THEN
        RAISE EXCEPTION 'staff shift preference staff, roster group, and slot name must stay within one venue and group';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_leave_request_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'leave request venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

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

    IF NEW.pay_config_snapshot_id IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM pay_config_snapshots pcs
            WHERE pcs.id = NEW.pay_config_snapshot_id
                AND pcs.venue_id = NEW.venue_id
        )
    THEN
        RAISE EXCEPTION 'timesheet entry venue_id must match pay_config_snapshot_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_report_definition_filter_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM report_definitions rd
        JOIN shift_types st ON st.id = NEW.shift_type_id
        WHERE rd.id = NEW.report_definition_id
            AND rd.venue_id = st.venue_id
    ) THEN
        RAISE EXCEPTION 'report definition shift type filter must stay within one venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_xero_connection_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM xero_connections xc
        WHERE xc.id = NEW.xero_connection_id
            AND xc.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero child row venue_id must match xero_connection_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_xero_staff_mapping_venue_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM xero_connections xc
        WHERE xc.id = NEW.xero_connection_id
            AND xc.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero child row venue_id must match xero_connection_id venue';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM staff s
        WHERE s.id = NEW.staff_id
            AND s.venue_id = NEW.venue_id
    ) THEN
        RAISE EXCEPTION 'xero staff mapping venue_id must match staff_id venue';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS enforce_roster_week_venue_integrity ON roster_weeks;
CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks FOR EACH ROW EXECUTE FUNCTION enforce_roster_week_venue_integrity();
DROP TRIGGER IF EXISTS enforce_slot_name_venue_integrity ON slot_names;
CREATE TRIGGER enforce_slot_name_venue_integrity BEFORE INSERT OR UPDATE ON slot_names FOR EACH ROW EXECUTE FUNCTION enforce_slot_name_venue_integrity();
DROP TRIGGER IF EXISTS enforce_staff_roster_group_venue_integrity ON staff_roster_groups;
CREATE TRIGGER enforce_staff_roster_group_venue_integrity BEFORE INSERT OR UPDATE ON staff_roster_groups FOR EACH ROW EXECUTE FUNCTION enforce_staff_roster_group_venue_integrity();
DROP TRIGGER IF EXISTS enforce_staff_availability_venue_integrity ON staff_availability;
CREATE TRIGGER enforce_staff_availability_venue_integrity BEFORE INSERT OR UPDATE ON staff_availability FOR EACH ROW EXECUTE FUNCTION enforce_staff_availability_venue_integrity();
DROP TRIGGER IF EXISTS enforce_staff_shift_preference_venue_integrity ON staff_shift_preferences;
CREATE TRIGGER enforce_staff_shift_preference_venue_integrity BEFORE INSERT OR UPDATE ON staff_shift_preferences FOR EACH ROW EXECUTE FUNCTION enforce_staff_shift_preference_venue_integrity();
DROP TRIGGER IF EXISTS enforce_leave_request_venue_integrity ON leave_requests;
CREATE TRIGGER enforce_leave_request_venue_integrity BEFORE INSERT OR UPDATE ON leave_requests FOR EACH ROW EXECUTE FUNCTION enforce_leave_request_venue_integrity();
DROP TRIGGER IF EXISTS enforce_timesheet_entry_venue_integrity ON timesheet_entries;
CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries FOR EACH ROW EXECUTE FUNCTION enforce_timesheet_entry_venue_integrity();
DROP TRIGGER IF EXISTS enforce_report_definition_filter_venue_integrity ON report_definition_shift_type_filters;
CREATE TRIGGER enforce_report_definition_filter_venue_integrity BEFORE INSERT OR UPDATE ON report_definition_shift_type_filters FOR EACH ROW EXECUTE FUNCTION enforce_report_definition_filter_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_sync_runs_venue_integrity ON xero_sync_runs;
CREATE TRIGGER enforce_xero_sync_runs_venue_integrity BEFORE INSERT OR UPDATE ON xero_sync_runs FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_employees_venue_integrity ON xero_employees;
CREATE TRIGGER enforce_xero_employees_venue_integrity BEFORE INSERT OR UPDATE ON xero_employees FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_earnings_rates_venue_integrity ON xero_earnings_rates;
CREATE TRIGGER enforce_xero_earnings_rates_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rates FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_payroll_calendars_venue_integrity ON xero_payroll_calendars;
CREATE TRIGGER enforce_xero_payroll_calendars_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendars FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_staff_mappings_venue_integrity ON xero_staff_mappings;
CREATE TRIGGER enforce_xero_staff_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_staff_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_staff_mapping_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_earnings_rate_mappings_venue_integrity ON xero_earnings_rate_mappings;
CREATE TRIGGER enforce_xero_earnings_rate_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_earnings_rate_mappings FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_payroll_calendar_selections_venue_integrity ON xero_payroll_calendar_selections;
CREATE TRIGGER enforce_xero_payroll_calendar_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_payroll_calendar_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_pay_item_account_code_selections_venue_integrity ON xero_pay_item_account_code_selections;
CREATE TRIGGER enforce_xero_pay_item_account_code_selections_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_account_code_selections FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
DROP TRIGGER IF EXISTS enforce_xero_pay_item_requirement_records_venue_integrity ON xero_pay_item_requirement_records;
CREATE TRIGGER enforce_xero_pay_item_requirement_records_venue_integrity BEFORE INSERT OR UPDATE ON xero_pay_item_requirement_records FOR EACH ROW EXECUTE FUNCTION enforce_xero_connection_venue_integrity();
