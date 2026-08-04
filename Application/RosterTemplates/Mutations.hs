module Application.RosterTemplates.Mutations
    ( lockRosterTemplateApplicationRows
    , lockRosterTemplateName
    , lockRosterTemplateVersion
    ) where

import qualified Data.Text as Text
import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (sqlQuery, sqlQueryScalar, unpackId)
import IHP.Prelude

lockRosterTemplateApplicationRows ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplate ->
    Id RosterWeek ->
    Maybe Int ->
    IO ()
lockRosterTemplateApplicationRows templateId rosterWeekId targetDayOffset = do
    _templateLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_templates WHERE id = ? FOR UPDATE"
        (Only (unpackId templateId))
    _weekLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_weeks WHERE id = ? FOR UPDATE"
        (Only (unpackId rosterWeekId))
    _dayLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_days \
        \WHERE roster_week_id = ? \
        \AND (?::int IS NULL OR day_offset = ?::int) \
        \ORDER BY id FOR UPDATE"
        (unpackId rosterWeekId, targetDayOffset, targetDayOffset)
    _definitionLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_week_slot_definitions \
        \WHERE roster_week_id = ? AND deleted_at IS NULL \
        \ORDER BY id FOR UPDATE"
        (Only (unpackId rosterWeekId))
    _slotLocks :: [Only UUID] <- sqlQuery
        "SELECT roster_slots.id FROM roster_slots \
        \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
        \WHERE roster_days.roster_week_id = ? \
        \AND (?::int IS NULL OR roster_days.day_offset = ?::int) \
        \AND roster_slots.deleted_at IS NULL \
        \ORDER BY roster_slots.id FOR UPDATE OF roster_slots"
        (unpackId rosterWeekId, targetDayOffset, targetDayOffset)
    _timesheetLocks :: [Only UUID] <- sqlQuery
        "SELECT timesheet_entries.id FROM timesheet_entries \
        \JOIN roster_slots ON roster_slots.id = timesheet_entries.source_roster_slot_id \
        \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
        \WHERE roster_days.roster_week_id = ? \
        \AND (?::int IS NULL OR roster_days.day_offset = ?::int) \
        \AND timesheet_entries.deleted_at IS NULL \
        \ORDER BY timesheet_entries.id FOR UPDATE OF timesheet_entries"
        (unpackId rosterWeekId, targetDayOffset, targetDayOffset)
    _shiftTypeLocks :: [Only UUID] <- sqlQuery
        "SELECT shift_types.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \JOIN shift_types ON shift_types.id = roster_template_shifts.shift_type_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY shift_types.id \
        \FOR UPDATE OF shift_types"
        (Only (unpackId templateId))
    _staffLocks :: [Only UUID] <- sqlQuery
        "SELECT staff.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \JOIN staff ON staff.id = roster_template_shifts.staff_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY staff.id \
        \FOR UPDATE OF staff"
        (Only (unpackId templateId))
    _membershipLocks :: [Only UUID] <- sqlQuery
        "SELECT staff_roster_groups.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \JOIN staff_roster_groups ON staff_roster_groups.staff_id = roster_template_shifts.staff_id \
        \    AND staff_roster_groups.roster_group_id = roster_templates.roster_group_id \
        \WHERE roster_templates.id = ? AND staff_roster_groups.deleted_at IS NULL \
        \ORDER BY staff_roster_groups.id \
        \FOR UPDATE OF staff_roster_groups"
        (Only (unpackId templateId))
    pure ()

-- PostgreSQL row locking is intentionally isolated here; ordinary template reads
-- use IHP QueryBuilder.
lockRosterTemplateName :: (?modelContext :: ModelContext) => Id RosterGroup -> Text -> IO ()
lockRosterTemplateName rosterGroupId normalizedName = do
    let lockKey = "roster-template-name:" <> tshow (unpackId rosterGroupId) <> ":" <> Text.toCaseFold normalizedName
    lockResults :: [Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_template_name_lock"
        (Only (Text.take 300 lockKey))
    unless (lockResults == [Only True]) do
        error "Unable to lock roster template name key"

lockRosterTemplateVersion :: (?modelContext :: ModelContext) => Id RosterTemplate -> IO Int
lockRosterTemplateVersion templateId =
    sqlQueryScalar
        "SELECT current_version FROM roster_templates WHERE id = ? FOR UPDATE"
        (Only (unpackId templateId))
