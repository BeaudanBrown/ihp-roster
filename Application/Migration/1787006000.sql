-- Seal Operational-window payroll ownership while retaining historical ledger rows.
-- Existing approved calculations inherit the entry's persisted Operational date and
-- the venue boundary in force at deployment. Component dates remain nullable only
-- for historical ledgers; runtime reconstruction continues from sealed paid-time
-- segments until those entries are explicitly unapproved and reapproved.

ALTER TABLE timesheet_pay_calculations
    ADD COLUMN operational_date DATE,
    ADD COLUMN roster_window_start DATE,
    ADD COLUMN roster_week_starts_on INT;

-- Existing sealed ledgers are immutable at runtime. This transaction owns the
-- one controlled additive backfill and restores both guards before commit.
ALTER TABLE timesheet_pay_calculations
    DISABLE TRIGGER enforce_timesheet_pay_calculations_immutable;
ALTER TABLE timesheet_pay_earnings_components
    DISABLE TRIGGER enforce_timesheet_pay_earnings_components_immutable;

UPDATE timesheet_pay_calculations calculation
SET operational_date = entry.operational_date,
    roster_week_starts_on = config.roster_week_starts_on,
    roster_window_start = entry.operational_date
        - ((EXTRACT(DOW FROM entry.operational_date)::INT - config.roster_week_starts_on + 7) % 7)
FROM timesheet_entries entry
JOIN venue_config config ON config.venue_id = entry.venue_id
WHERE entry.id = calculation.timesheet_entry_id;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM timesheet_pay_calculations
        WHERE operational_date IS NULL
           OR roster_window_start IS NULL
           OR roster_week_starts_on IS NULL
    ) THEN
        RAISE EXCEPTION 'Cannot seal Operational-window facts for every approved Timesheet calculation';
    END IF;
END
$$;

ALTER TABLE timesheet_pay_calculations
    ALTER COLUMN operational_date SET NOT NULL,
    ALTER COLUMN roster_window_start SET NOT NULL,
    ALTER COLUMN roster_week_starts_on SET NOT NULL,
    ADD CONSTRAINT timesheet_pay_calculations_roster_week_starts_on_check
        CHECK (roster_week_starts_on >= 0 AND roster_week_starts_on <= 6);

ALTER TABLE timesheet_pay_earnings_components
    ADD COLUMN component_date DATE DEFAULT NULL,
    ADD COLUMN resolved_rate_boundary_date DATE DEFAULT NULL,
    ADD COLUMN xero_local_bucket_key TEXT DEFAULT NULL,
    ADD COLUMN xero_earnings_rate_id TEXT DEFAULT NULL,
    ADD COLUMN xero_mapping_legacy_fallback BOOLEAN DEFAULT TRUE NOT NULL;

ALTER TABLE timesheet_pay_earnings_components
    ALTER COLUMN xero_mapping_legacy_fallback SET DEFAULT FALSE;

UPDATE timesheet_pay_earnings_components component
SET resolved_rate_boundary_date = rate.operative_from
    + ((calculation.roster_week_starts_on - EXTRACT(DOW FROM rate.operative_from)::INT + 7) % 7)
FROM timesheet_pay_calculations calculation, award_level_base_rates rate
WHERE calculation.id = component.timesheet_pay_calculation_id
  AND component.source_rate_identity LIKE 'bepis-projection:award_level_base_rates:%'
  AND rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
  AND rate.operative_from IS NOT NULL;

UPDATE timesheet_pay_earnings_components component
SET resolved_rate_boundary_date = rate.operative_from
    + ((calculation.roster_week_starts_on - EXTRACT(DOW FROM rate.operative_from)::INT + 7) % 7)
FROM timesheet_pay_calculations calculation, award_level_penalty_rates rate
WHERE calculation.id = component.timesheet_pay_calculation_id
  AND component.source_rate_identity LIKE 'bepis-projection:award_level_penalty_rates:%'
  AND rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
  AND rate.operative_from IS NOT NULL;

UPDATE timesheet_pay_earnings_components component
SET resolved_rate_boundary_date = rate.operative_from
    + ((calculation.roster_week_starts_on - EXTRACT(DOW FROM rate.operative_from)::INT + 7) % 7)
FROM timesheet_pay_calculations calculation, award_time_penalty_allowances rate
WHERE calculation.id = component.timesheet_pay_calculation_id
  AND component.source_rate_identity LIKE 'bepis-projection:award_time_penalty_allowances:%'
  AND rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
  AND rate.operative_from IS NOT NULL;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM timesheet_pay_earnings_components component
        WHERE component.calculation_source = 'hospitality_award'
          AND component.source_rate_identity IS NOT NULL
          AND component.resolved_rate_boundary_date IS NULL
          AND NOT (
              (component.source_rate_identity LIKE 'bepis-projection:award_level_base_rates:%' AND EXISTS (
                  SELECT 1 FROM award_level_base_rates rate
                  WHERE rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
                    AND rate.operative_from IS NULL
              ))
              OR (component.source_rate_identity LIKE 'bepis-projection:award_level_penalty_rates:%' AND EXISTS (
                  SELECT 1 FROM award_level_penalty_rates rate
                  WHERE rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
                    AND rate.operative_from IS NULL
              ))
              OR (component.source_rate_identity LIKE 'bepis-projection:award_time_penalty_allowances:%' AND EXISTS (
                  SELECT 1 FROM award_time_penalty_allowances rate
                  WHERE rate.id = split_part(split_part(component.source_rate_identity, '/source:', 1), ':', 3)::UUID
                    AND rate.operative_from IS NULL
              ))
          )
    ) THEN
        RAISE EXCEPTION 'Cannot seal every historical approved component rate boundary';
    END IF;
END
$$;

COMMENT ON COLUMN timesheet_pay_earnings_components.component_date IS
    'Explicit immutable component date for calculations approved after the date-native payroll cutover; NULL only on retained historical ledgers reconstructed from sealed paid-time segments.';
COMMENT ON COLUMN timesheet_pay_earnings_components.resolved_rate_boundary_date IS
    'Venue-window-normalized effective rate boundary sealed at approval; NULL for imported rates and retained historical ledgers.';
COMMENT ON COLUMN timesheet_pay_earnings_components.xero_local_bucket_key IS
    'Exact local Xero earnings bucket sealed at approval when a provider mapping is available.';
COMMENT ON COLUMN timesheet_pay_earnings_components.xero_earnings_rate_id IS
    'Exact provider EarningsRateID snapshot paired with xero_local_bucket_key at approval.';
COMMENT ON COLUMN timesheet_pay_earnings_components.xero_mapping_legacy_fallback IS
    'TRUE only for retained historical ledgers that predate approval-time Xero mapping snapshots.';

ALTER TABLE timesheet_pay_earnings_components
    ADD CONSTRAINT timesheet_pay_components_xero_mapping_pair_check
        CHECK ((xero_local_bucket_key IS NULL) = (xero_earnings_rate_id IS NULL));

ALTER TABLE timesheet_pay_calculations
    ENABLE TRIGGER enforce_timesheet_pay_calculations_immutable;
ALTER TABLE timesheet_pay_earnings_components
    ENABLE TRIGGER enforce_timesheet_pay_earnings_components_immutable;

CREATE OR REPLACE FUNCTION enforce_timesheet_active_pay_calculation_integrity()
RETURNS TRIGGER
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM timesheet_entries entry
        WHERE entry.id = NEW.id
            AND (
                (entry.is_approved = FALSE AND entry.active_pay_calculation_id IS NULL AND entry.legacy_pay_backfill_pending = FALSE)
                OR (
                    entry.is_approved = TRUE
                    AND (
                        (entry.legacy_pay_backfill_pending = TRUE AND entry.active_pay_calculation_id IS NULL)
                        OR (
                            entry.legacy_pay_backfill_pending = FALSE
                            AND entry.active_pay_calculation_id IS NOT NULL
                            AND EXISTS (
                                SELECT 1 FROM timesheet_pay_calculations calculation
                                WHERE calculation.id = entry.active_pay_calculation_id
                                    AND calculation.timesheet_entry_id = entry.id
                                    AND calculation.operational_date = entry.operational_date
                                    AND calculation.sealed_at IS NOT NULL
                            )
                        )
                    )
                )
            )
    ) THEN
        RAISE EXCEPTION 'timesheet approval requires a sealed same-entry active pay calculation with matching Operational date';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
