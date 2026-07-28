-- Add explicit pay-assignment modes without discarding either existing rate reference.
-- The preflight aborts before backfill when intent is ambiguous or an imported
-- Xero reference crosses venue scope. Operators receive bounded row identifiers.
CREATE TYPE pay_assignment_mode_enum AS ENUM (
    'award_rate',
    'xero_rate',
    'roster_only',
    'staff_default',
    'legacy_unresolved'
);

ALTER TABLE staff ADD COLUMN pay_assignment_mode pay_assignment_mode_enum;
ALTER TABLE shift_types ADD COLUMN pay_assignment_mode pay_assignment_mode_enum;
ALTER TABLE staff_pay_versions ADD COLUMN pay_assignment_mode pay_assignment_mode_enum;
ALTER TABLE shift_type_pay_versions ADD COLUMN pay_assignment_mode pay_assignment_mode_enum;

DO $$
DECLARE
    anomaly_count BIGINT;
    anomaly_sample TEXT;
BEGIN
    WITH anomalies AS (
        SELECT 'staff:both_rate_ids' AS kind, s.id FROM staff s
        WHERE s.default_award_level_id IS NOT NULL AND s.imported_xero_pay_item_id IS NOT NULL
        UNION ALL
        SELECT 'shift_type:both_rate_ids', st.id FROM shift_types st
        WHERE st.override_award_level_id IS NOT NULL AND st.imported_xero_pay_item_id IS NOT NULL
        UNION ALL
        SELECT 'staff_pay_version:both_rate_ids', spv.id FROM staff_pay_versions spv
        WHERE spv.default_award_level_id IS NOT NULL AND spv.imported_xero_pay_item_id IS NOT NULL
        UNION ALL
        SELECT 'shift_type_pay_version:both_rate_ids', stpv.id FROM shift_type_pay_versions stpv
        WHERE stpv.override_award_level_id IS NOT NULL AND stpv.imported_xero_pay_item_id IS NOT NULL
        UNION ALL
        SELECT 'staff:cross_venue_xero', s.id FROM staff s
        JOIN xero_imported_pay_items item ON item.id = s.imported_xero_pay_item_id
        WHERE item.venue_id <> s.venue_id
        UNION ALL
        SELECT 'shift_type:cross_venue_xero', st.id FROM shift_types st
        JOIN xero_imported_pay_items item ON item.id = st.imported_xero_pay_item_id
        WHERE item.venue_id <> st.venue_id
        UNION ALL
        SELECT 'staff_pay_version:cross_venue_xero', spv.id FROM staff_pay_versions spv
        JOIN xero_imported_pay_items item ON item.id = spv.imported_xero_pay_item_id
        WHERE item.venue_id <> spv.venue_id
        UNION ALL
        SELECT 'shift_type_pay_version:cross_venue_xero', stpv.id FROM shift_type_pay_versions stpv
        JOIN xero_imported_pay_items item ON item.id = stpv.imported_xero_pay_item_id
        WHERE item.venue_id <> stpv.venue_id
        UNION ALL
        SELECT 'staff_pay_version:missing_or_cross_venue_staff', spv.id FROM staff_pay_versions spv
        LEFT JOIN staff s ON s.id = spv.staff_id
        WHERE s.id IS NULL OR s.venue_id <> spv.venue_id
        UNION ALL
        SELECT 'shift_type_pay_version:missing_or_cross_venue_shift_type', stpv.id FROM shift_type_pay_versions stpv
        LEFT JOIN shift_types st ON st.id = stpv.shift_type_id
        WHERE st.id IS NULL OR st.venue_id <> stpv.venue_id
    ), bounded AS (
        SELECT kind, id FROM anomalies ORDER BY kind, id LIMIT 50
    )
    SELECT
        (SELECT count(*) FROM anomalies),
        (SELECT string_agg(kind || '=' || id::TEXT, ', ' ORDER BY kind, id) FROM bounded)
    INTO anomaly_count, anomaly_sample;

    IF anomaly_count > 0 THEN
        RAISE EXCEPTION 'pay-assignment migration preflight found % anomalous rows', anomaly_count
            USING DETAIL = 'First 50: ' || COALESCE(anomaly_sample, '(none)');
    END IF;
END;
$$;

UPDATE staff
SET pay_assignment_mode = CASE
    WHEN imported_xero_pay_item_id IS NOT NULL THEN 'xero_rate'::pay_assignment_mode_enum
    WHEN default_award_level_id IS NOT NULL THEN 'award_rate'::pay_assignment_mode_enum
    WHEN user_id IS NULL THEN 'roster_only'::pay_assignment_mode_enum
    ELSE 'legacy_unresolved'::pay_assignment_mode_enum
END;

UPDATE shift_types
SET pay_assignment_mode = CASE
    WHEN imported_xero_pay_item_id IS NOT NULL THEN 'xero_rate'::pay_assignment_mode_enum
    WHEN override_award_level_id IS NOT NULL THEN 'award_rate'::pay_assignment_mode_enum
    ELSE 'staff_default'::pay_assignment_mode_enum
END;

UPDATE staff_pay_versions spv
SET pay_assignment_mode = CASE
    WHEN spv.imported_xero_pay_item_id IS NOT NULL THEN 'xero_rate'::pay_assignment_mode_enum
    WHEN spv.default_award_level_id IS NOT NULL THEN 'award_rate'::pay_assignment_mode_enum
    WHEN s.user_id IS NULL THEN 'roster_only'::pay_assignment_mode_enum
    ELSE 'legacy_unresolved'::pay_assignment_mode_enum
END
FROM staff s
WHERE s.id = spv.staff_id;

UPDATE shift_type_pay_versions
SET pay_assignment_mode = CASE
    WHEN imported_xero_pay_item_id IS NOT NULL THEN 'xero_rate'::pay_assignment_mode_enum
    WHEN override_award_level_id IS NOT NULL THEN 'award_rate'::pay_assignment_mode_enum
    ELSE 'staff_default'::pay_assignment_mode_enum
END;

ALTER TABLE staff ALTER COLUMN pay_assignment_mode SET DEFAULT 'roster_only';
ALTER TABLE staff ALTER COLUMN pay_assignment_mode SET NOT NULL;
ALTER TABLE shift_types ALTER COLUMN pay_assignment_mode SET DEFAULT 'staff_default';
ALTER TABLE shift_types ALTER COLUMN pay_assignment_mode SET NOT NULL;
ALTER TABLE staff_pay_versions ALTER COLUMN pay_assignment_mode SET DEFAULT 'roster_only';
ALTER TABLE staff_pay_versions ALTER COLUMN pay_assignment_mode SET NOT NULL;
ALTER TABLE shift_type_pay_versions ALTER COLUMN pay_assignment_mode SET DEFAULT 'staff_default';
ALTER TABLE shift_type_pay_versions ALTER COLUMN pay_assignment_mode SET NOT NULL;

ALTER TABLE staff ADD CONSTRAINT staff_pay_assignment_shape CHECK (
    (pay_assignment_mode = 'award_rate' AND default_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'xero_rate' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
    OR (pay_assignment_mode = 'roster_only' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'legacy_unresolved' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
);
ALTER TABLE shift_types ADD CONSTRAINT shift_types_pay_assignment_shape CHECK (
    (pay_assignment_mode = 'award_rate' AND override_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'xero_rate' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
    OR (pay_assignment_mode = 'roster_only' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'staff_default' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
);
ALTER TABLE staff_pay_versions ADD CONSTRAINT staff_pay_versions_assignment_shape CHECK (
    (pay_assignment_mode = 'award_rate' AND default_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'xero_rate' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
    OR (pay_assignment_mode = 'roster_only' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'legacy_unresolved' AND default_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
);
ALTER TABLE shift_type_pay_versions ADD CONSTRAINT shift_type_pay_versions_assignment_shape CHECK (
    (pay_assignment_mode = 'award_rate' AND override_award_level_id IS NOT NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'xero_rate' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NOT NULL)
    OR (pay_assignment_mode = 'roster_only' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
    OR (pay_assignment_mode = 'staff_default' AND override_award_level_id IS NULL AND imported_xero_pay_item_id IS NULL)
);

CREATE OR REPLACE FUNCTION prevent_locked_staff_pay_version_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND (
            NEW.pay_assignment_mode IS DISTINCT FROM OLD.pay_assignment_mode
            OR NEW.default_award_level_id IS DISTINCT FROM OLD.default_award_level_id
            OR NEW.imported_xero_pay_item_id IS DISTINCT FROM OLD.imported_xero_pay_item_id
        )
    THEN
        RAISE EXCEPTION 'locked staff pay assignment is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_locked_shift_pay_version_change()
RETURNS TRIGGER
AS $$
BEGIN
    IF OLD.locked_at IS NOT NULL
        AND (
            NEW.pay_assignment_mode IS DISTINCT FROM OLD.pay_assignment_mode
            OR NEW.override_award_level_id IS DISTINCT FROM OLD.override_award_level_id
            OR NEW.imported_xero_pay_item_id IS DISTINCT FROM OLD.imported_xero_pay_item_id
        )
    THEN
        RAISE EXCEPTION 'locked shift pay assignment is immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER prevent_locked_staff_pay_version_imported_item_update ON staff_pay_versions;
CREATE TRIGGER prevent_locked_staff_pay_version_imported_item_update
    BEFORE UPDATE ON staff_pay_versions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_staff_pay_version_change();

DROP TRIGGER prevent_locked_shift_pay_version_imported_item_update ON shift_type_pay_versions;
CREATE TRIGGER prevent_locked_shift_pay_version_imported_item_update
    BEFORE UPDATE ON shift_type_pay_versions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_locked_shift_pay_version_change();

DROP FUNCTION prevent_locked_pay_version_imported_item_change();
