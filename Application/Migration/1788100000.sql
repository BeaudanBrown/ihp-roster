-- GitHub #374: retire the observed, read-only roster offset compatibility schema.
--
-- This migration is intentionally destructive only to redundant compatibility
-- identity. Authoritative Operational dates, date-local lanes and slots,
-- publication state, explicit notification windows/snapshots, Timesheets,
-- exports, payroll evidence and Xero evidence remain in their owning tables.
-- Deployment requires the separately approved issue-374 runbook and backup.

DO $$
DECLARE
    issue_summary TEXT;
BEGIN
    SELECT string_agg(issue, '; ' ORDER BY issue)
    INTO issue_summary
    FROM (
        SELECT 'roster day venue/group scope mismatch: ' || count(*)::TEXT AS issue
        FROM roster_days day
        LEFT JOIN roster_groups roster_group ON roster_group.id = day.roster_group_id
        WHERE roster_group.id IS NULL OR roster_group.venue_id <> day.venue_id
        HAVING count(*) > 0

        UNION ALL

        SELECT 'roster lane missing its date-native day: ' || count(*)::TEXT
        FROM roster_lanes lane
        LEFT JOIN roster_days day ON day.id = lane.roster_day_id
        WHERE day.id IS NULL
        HAVING count(*) > 0

        UNION ALL

        SELECT 'roster slot date-local lane mismatch: ' || count(*)::TEXT
        FROM roster_slots slot
        LEFT JOIN roster_lanes lane ON lane.id = slot.roster_lane_id
        WHERE lane.id IS NULL OR lane.roster_day_id <> slot.roster_day_id
        HAVING count(*) > 0

        UNION ALL

        SELECT 'roster notification lacks an explicit seven-day window: ' || count(*)::TEXT
        FROM roster_notification_runs run
        WHERE run.window_end <> run.week_start + 7
        HAVING count(*) > 0
    ) contradictions;

    IF issue_summary IS NOT NULL THEN
        RAISE EXCEPTION 'legacy roster retirement preflight blocked: %', issue_summary;
    END IF;
END;
$$;

-- Remove compatibility writers and immutability guards before their columns.
DROP TRIGGER project_legacy_roster_slot_lane ON roster_slots;
DROP TRIGGER prevent_legacy_roster_lane_identity_change ON roster_lanes;
DROP TRIGGER validate_roster_lane_scope ON roster_lanes;
DROP TRIGGER project_legacy_roster_day_lanes ON roster_days;
DROP TRIGGER project_legacy_roster_day ON roster_days;
DROP TRIGGER project_legacy_roster_week_definition_lanes ON roster_week_slot_definitions;
DROP TRIGGER prevent_legacy_roster_definition_week_change ON roster_week_slot_definitions;
DROP TRIGGER refresh_legacy_roster_week_day_projections ON roster_weeks;
DROP TRIGGER enforce_roster_week_venue_integrity ON roster_weeks;
DROP TRIGGER prevent_hard_delete_roster_weeks ON roster_weeks;

DROP FUNCTION project_legacy_roster_slot_lane();
DROP FUNCTION project_legacy_roster_day_lanes();
DROP FUNCTION project_legacy_roster_week_definition_lanes();
DROP FUNCTION project_legacy_roster_lane(UUID, UUID);
DROP FUNCTION project_legacy_roster_day();
DROP FUNCTION prevent_legacy_roster_lane_identity_change();
DROP FUNCTION prevent_legacy_roster_definition_week_change();
DROP FUNCTION refresh_legacy_roster_week_day_projections();
DROP FUNCTION enforce_roster_week_venue_integrity();
DROP FUNCTION validate_roster_lane_scope();

-- Drop all inbound compatibility references before retiring weekly identity.
ALTER TABLE roster_slots DROP COLUMN roster_week_slot_definition_id;
ALTER TABLE roster_lanes DROP COLUMN legacy_roster_week_slot_definition_id;
ALTER TABLE roster_notification_runs
    DROP COLUMN roster_week_id,
    DROP COLUMN week_offset;
ALTER TABLE roster_days
    DROP COLUMN roster_week_id,
    DROP COLUMN day_offset;
ALTER TABLE venue_config DROP COLUMN week_offset_epoch;

DROP TABLE roster_week_slot_definitions;
DROP TABLE roster_weeks;
