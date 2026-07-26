-- Keep the remote Xero identity referenced by immutable staff/shift pay versions
-- stable while still allowing metadata, freshness, rate and archive updates.
CREATE OR REPLACE FUNCTION prevent_xero_imported_pay_item_identity_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF NEW.venue_id IS DISTINCT FROM OLD.venue_id
        OR NEW.xero_connection_id IS DISTINCT FROM OLD.xero_connection_id
        OR NEW.xero_earnings_rate_id IS DISTINCT FROM OLD.xero_earnings_rate_id
    THEN
        RAISE EXCEPTION 'imported Xero pay item identity is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_xero_imported_pay_item_identity_update ON xero_imported_pay_items;
CREATE TRIGGER prevent_xero_imported_pay_item_identity_update
    BEFORE UPDATE ON xero_imported_pay_items
    FOR EACH ROW
    EXECUTE FUNCTION prevent_xero_imported_pay_item_identity_change();

CREATE OR REPLACE FUNCTION prevent_locked_pay_version_imported_item_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND NEW.imported_xero_pay_item_id IS DISTINCT FROM OLD.imported_xero_pay_item_id
    THEN
        RAISE EXCEPTION 'locked pay version imported Xero item is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_locked_staff_pay_version_imported_item_update ON staff_pay_versions;
CREATE TRIGGER prevent_locked_staff_pay_version_imported_item_update
    BEFORE UPDATE ON staff_pay_versions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_pay_version_imported_item_change();

DROP TRIGGER IF EXISTS prevent_locked_shift_pay_version_imported_item_update ON shift_type_pay_versions;
CREATE TRIGGER prevent_locked_shift_pay_version_imported_item_update
    BEFORE UPDATE ON shift_type_pay_versions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_pay_version_imported_item_change();

CREATE OR REPLACE FUNCTION prevent_locked_shift_pay_version_label_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND NEW.payroll_label IS DISTINCT FROM OLD.payroll_label
    THEN
        RAISE EXCEPTION 'locked shift pay version payroll label is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_locked_shift_pay_version_payroll_label_update ON shift_type_pay_versions;
CREATE TRIGGER prevent_locked_shift_pay_version_payroll_label_update
    BEFORE UPDATE ON shift_type_pay_versions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_shift_pay_version_label_change();
