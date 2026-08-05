module Application.RosterTemplates.Mutations
    ( lockRosterTemplateApplicationRows
    , lockRosterTemplateContentReferenceRows
    , lockRosterTemplateDraftDesign
    , lockRosterTemplateDraftSlot
    , lockRosterTemplateName
    , lockRosterTemplateReferenceRows
    , lockRosterTemplateVersion
    ) where

import qualified Data.Text as Text
import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (sqlQuery, sqlQueryScalar, unpackId)
import IHP.Prelude

lockRosterTemplateDraftSlot :: (?modelContext :: ModelContext) => Id User -> IO ()
lockRosterTemplateDraftSlot userId = do
    let lockKey = "roster-template-draft-slot:" <> tshow (unpackId userId)
    lockResults :: [Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_template_draft_slot_lock"
        (Only lockKey)
    unless (lockResults == [Only True]) do
        error "Unable to lock roster template draft slot"

lockRosterTemplateDraftDesign ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplateDesign ->
    IO Bool
lockRosterTemplateDraftDesign designId = do
    locked :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_template_designs WHERE id = ? FOR UPDATE"
        (Only (unpackId designId))
    pure (locked == [Only (unpackId designId)])

lockRosterTemplateContentReferenceRows ::
    (?modelContext :: ModelContext) =>
    Id RosterGroup ->
    [Id ShiftType] ->
    [Id Staff] ->
    IO ()
lockRosterTemplateContentReferenceRows rosterGroupId shiftTypeIds staffIds = do
    let shiftTypeUuids = map unpackId shiftTypeIds
    let staffUuids = map unpackId staffIds
    _shiftTypeLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM shift_types WHERE id = ANY(?) ORDER BY id FOR UPDATE"
        (Only shiftTypeUuids)
    _staffLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM staff WHERE id = ANY(?) ORDER BY id FOR UPDATE"
        (Only staffUuids)
    _membershipLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM staff_roster_groups \
        \WHERE roster_group_id = ? AND staff_id = ANY(?) \
        \ORDER BY id FOR UPDATE"
        (unpackId rosterGroupId, staffUuids)
    _awardLevelLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM award_levels \
        \WHERE id IN ( \
        \    SELECT default_award_level_id FROM staff WHERE id = ANY(?) \
        \    UNION \
        \    SELECT override_award_level_id FROM shift_types WHERE id = ANY(?) \
        \) ORDER BY id FOR UPDATE"
        (staffUuids, shiftTypeUuids)
    _importedPayItemLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM xero_imported_pay_items \
        \WHERE id IN ( \
        \    SELECT imported_xero_pay_item_id FROM staff WHERE id = ANY(?) \
        \    UNION \
        \    SELECT imported_xero_pay_item_id FROM shift_types WHERE id = ANY(?) \
        \) ORDER BY id FOR UPDATE"
        (staffUuids, shiftTypeUuids)
    pure ()

lockRosterTemplateReferenceRows ::
    (?modelContext :: ModelContext) =>
    Id RosterWeek ->
    Maybe Int ->
    IO ()
lockRosterTemplateReferenceRows rosterWeekId selectedDayOffset = do
    -- Parent FOR UPDATE locks conflict with PostgreSQL's foreign-key FOR KEY SHARE
    -- checks, so concurrent day, definition, and slot inserts cannot become phantoms
    -- while the locked reference snapshot is read and copied.
    _weekLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_weeks WHERE id = ? FOR UPDATE"
        (Only (unpackId rosterWeekId))
    _dayLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_days \
        \WHERE roster_week_id = ? \
        \AND (?::int IS NULL OR day_offset = ?::int) \
        \ORDER BY id FOR UPDATE"
        (unpackId rosterWeekId, selectedDayOffset, selectedDayOffset)
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
        (unpackId rosterWeekId, selectedDayOffset, selectedDayOffset)
    pure ()

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
    _awardLevelLocks :: [Only UUID] <- sqlQuery
        "SELECT award_levels.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \LEFT JOIN staff ON staff.id = roster_template_shifts.staff_id \
        \JOIN shift_types ON shift_types.id = roster_template_shifts.shift_type_id \
        \JOIN award_levels ON award_levels.id = staff.default_award_level_id \
        \    OR award_levels.id = shift_types.override_award_level_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY award_levels.id \
        \FOR UPDATE OF award_levels"
        (Only (unpackId templateId))
    _importedPayItemLocks :: [Only UUID] <- sqlQuery
        "SELECT xero_imported_pay_items.id \
        \FROM roster_templates \
        \JOIN roster_template_designs ON roster_template_designs.template_id = roster_templates.id \
        \    AND roster_template_designs.version_number = roster_templates.current_version \
        \JOIN roster_template_shifts ON roster_template_shifts.roster_template_design_id = roster_template_designs.id \
        \LEFT JOIN staff ON staff.id = roster_template_shifts.staff_id \
        \JOIN shift_types ON shift_types.id = roster_template_shifts.shift_type_id \
        \JOIN xero_imported_pay_items ON xero_imported_pay_items.id = staff.imported_xero_pay_item_id \
        \    OR xero_imported_pay_items.id = shift_types.imported_xero_pay_item_id \
        \WHERE roster_templates.id = ? \
        \ORDER BY xero_imported_pay_items.id \
        \FOR UPDATE OF xero_imported_pay_items"
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
