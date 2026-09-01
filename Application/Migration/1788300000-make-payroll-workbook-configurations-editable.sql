-- Remove the original five-family storage ceiling, add optimistic edit
-- revisions, and materialize the former row-free built-in as an ordinary
-- deletable venue configuration. Existing export-job snapshots are untouched.
ALTER TABLE payroll_workbook_configuration_families
    DROP CONSTRAINT payroll_workbook_configuration_families_family_key_check,
    DROP CONSTRAINT payroll_workbook_configuration_families_position_check;

ALTER TABLE payroll_workbook_configuration_families
    ADD CHECK (position >= 0);

ALTER TABLE payroll_workbook_configurations
    ADD COLUMN revision INT DEFAULT 0 NOT NULL,
    ADD CHECK (revision >= 0);

WITH configuration_owners AS (
    SELECT DISTINCT ON (venue_id)
        venue_id,
        user_id
    FROM venue_memberships
    WHERE is_active = TRUE
      AND archived_at IS NULL
    ORDER BY
        venue_id,
        CASE venue_role WHEN 'venue_owner' THEN 0 WHEN 'venue_admin' THEN 1 ELSE 2 END,
        created_at,
        id
), inserted_configurations AS (
    INSERT INTO payroll_workbook_configurations (
        venue_id,
        name,
        definition_version,
        revision,
        created_by_user_id
    )
    SELECT
        venue_id,
        'Payroll Workbook',
        1,
        0,
        user_id
    FROM configuration_owners
    ON CONFLICT (venue_id, lower(name)) DO NOTHING
    RETURNING id
)
INSERT INTO payroll_workbook_configuration_families (configuration_id, family_key, position)
SELECT
    inserted_configurations.id,
    family.family_key,
    family.position
FROM inserted_configurations
CROSS JOIN (VALUES
    ('summary', 0),
    ('employee-pay-bucket-hours', 1),
    ('shift-type-hours', 2),
    ('employee-pay-bucket-wages', 3),
    ('shift-type-wages', 4)
) AS family (family_key, position);
