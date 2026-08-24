module Application.RosterTemplates.Mutations
    ( lockRosterTemplate
    , lockRosterTemplateApplicationRows
    , lockRosterTemplateCaptureGroup
    , lockRosterTemplateContentReferenceRows
    , lockRosterTemplateName
    , lockRosterTemplateReferenceRows
    ) where

import qualified Data.Text as Text
import Database.PostgreSQL.Simple (Only (..))
import Generated.Types
import IHP.ModelSupport (sqlQuery, unpackId)
import IHP.Prelude

lockRosterTemplateCaptureGroup :: (?modelContext :: ModelContext) => Id RosterGroup -> IO Bool
lockRosterTemplateCaptureGroup rosterGroupId = do
    locked :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_groups WHERE id = ? FOR UPDATE"
        (Only (unpackId rosterGroupId))
    pure (locked == [Only (unpackId rosterGroupId)])

lockRosterTemplate :: (?modelContext :: ModelContext) => Id RosterTemplate -> IO Bool
lockRosterTemplate templateId = do
    locked :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_templates WHERE id = ? FOR UPDATE"
        (Only (unpackId templateId))
    pure (locked == [Only (unpackId templateId)])

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
        "SELECT id FROM staff_roster_groups WHERE roster_group_id = ? AND staff_id = ANY(?) ORDER BY id FOR UPDATE"
        (unpackId rosterGroupId, staffUuids)
    _awardLevelLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM award_levels WHERE id IN (SELECT default_award_level_id FROM staff WHERE id = ANY(?) UNION SELECT override_award_level_id FROM shift_types WHERE id = ANY(?)) ORDER BY id FOR UPDATE"
        (staffUuids, shiftTypeUuids)
    _importedPayItemLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM xero_imported_pay_items WHERE id IN (SELECT imported_xero_pay_item_id FROM staff WHERE id = ANY(?) UNION SELECT imported_xero_pay_item_id FROM shift_types WHERE id = ANY(?)) ORDER BY id FOR UPDATE"
        (staffUuids, shiftTypeUuids)
    pure ()

lockRosterTemplateReferenceRows ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    Maybe Day ->
    IO ()
lockRosterTemplateReferenceRows venueId rosterGroupId windowStart windowEnd selectedDate = do
    lockTargetRows venueId rosterGroupId windowStart windowEnd selectedDate

lockRosterTemplateApplicationRows ::
    (?modelContext :: ModelContext) =>
    Id RosterTemplate ->
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    Maybe Day ->
    [Id ShiftType] ->
    IO ()
lockRosterTemplateApplicationRows templateId venueId rosterGroupId windowStart windowEnd targetDate mappedShiftTypeIds = do
    _ <- lockRosterTemplate templateId
    _groupLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_groups WHERE id = ? AND venue_id = ? FOR UPDATE"
        (unpackId rosterGroupId, unpackId venueId)
    _configLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM venue_config WHERE venue_id = ? FOR UPDATE"
        (Only (unpackId venueId))
    lockTargetRows venueId rosterGroupId windowStart windowEnd targetDate
    _timesheetLocks :: [Only UUID] <- sqlQuery
        "SELECT timesheet_entries.id FROM timesheet_entries JOIN roster_slots ON roster_slots.id = timesheet_entries.source_roster_slot_id JOIN roster_days ON roster_days.id = roster_slots.roster_day_id WHERE roster_days.venue_id = ? AND roster_days.roster_group_id = ? AND roster_days.operational_date >= ? AND roster_days.operational_date < ? AND (?::date IS NULL OR roster_days.operational_date = ?::date) AND timesheet_entries.deleted_at IS NULL ORDER BY timesheet_entries.id FOR UPDATE OF timesheet_entries"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd, targetDate, targetDate)
    _shiftTypeLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM shift_types WHERE id IN (SELECT shift_type_id FROM roster_template_shifts WHERE roster_template_id = ?) OR id = ANY(?) ORDER BY id FOR UPDATE"
        (unpackId templateId, map unpackId mappedShiftTypeIds)
    _staffLocks :: [Only UUID] <- sqlQuery
        "SELECT staff.id FROM roster_template_shifts JOIN staff ON staff.id = roster_template_shifts.staff_id WHERE roster_template_shifts.roster_template_id = ? ORDER BY staff.id FOR UPDATE OF staff"
        (Only (unpackId templateId))
    _leaveLocks :: [Only UUID] <- sqlQuery
        "SELECT leave_requests.id FROM leave_requests JOIN roster_template_shifts ON roster_template_shifts.staff_id = leave_requests.staff_id WHERE roster_template_shifts.roster_template_id = ? AND leave_requests.venue_id = ? AND leave_requests.status = 'approved' AND leave_requests.start_date < ? AND leave_requests.end_date > ? ORDER BY leave_requests.id FOR UPDATE OF leave_requests"
        (unpackId templateId, unpackId venueId, windowEnd, windowStart)
    _membershipLocks :: [Only UUID] <- sqlQuery
        "SELECT staff_roster_groups.id FROM roster_template_shifts JOIN roster_templates ON roster_templates.id = roster_template_shifts.roster_template_id JOIN staff_roster_groups ON staff_roster_groups.staff_id = roster_template_shifts.staff_id AND staff_roster_groups.roster_group_id = roster_templates.roster_group_id WHERE roster_templates.id = ? AND staff_roster_groups.deleted_at IS NULL ORDER BY staff_roster_groups.id FOR UPDATE OF staff_roster_groups"
        (Only (unpackId templateId))
    _awardLevelLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM award_levels WHERE id IN (SELECT staff.default_award_level_id FROM roster_template_shifts JOIN staff ON staff.id = roster_template_shifts.staff_id WHERE roster_template_shifts.roster_template_id = ? UNION SELECT shift_types.override_award_level_id FROM shift_types WHERE shift_types.id IN (SELECT shift_type_id FROM roster_template_shifts WHERE roster_template_id = ?) OR shift_types.id = ANY(?)) ORDER BY id FOR UPDATE"
        (unpackId templateId, unpackId templateId, map unpackId mappedShiftTypeIds)
    _importedPayItemLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM xero_imported_pay_items WHERE id IN (SELECT staff.imported_xero_pay_item_id FROM roster_template_shifts JOIN staff ON staff.id = roster_template_shifts.staff_id WHERE roster_template_shifts.roster_template_id = ? UNION SELECT shift_types.imported_xero_pay_item_id FROM shift_types WHERE shift_types.id IN (SELECT shift_type_id FROM roster_template_shifts WHERE roster_template_id = ?) OR shift_types.id = ANY(?)) ORDER BY id FOR UPDATE"
        (unpackId templateId, unpackId templateId, map unpackId mappedShiftTypeIds)
    pure ()

lockTargetRows ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    Maybe Day ->
    IO ()
lockTargetRows venueId rosterGroupId windowStart windowEnd selectedDate = do
    _dayLocks :: [Only UUID] <- sqlQuery
        "SELECT id FROM roster_days WHERE venue_id = ? AND roster_group_id = ? AND operational_date >= ? AND operational_date < ? AND (?::date IS NULL OR operational_date = ?::date) ORDER BY operational_date FOR UPDATE"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd, selectedDate, selectedDate)
    _laneLocks :: [Only UUID] <- sqlQuery
        "SELECT roster_lanes.id FROM roster_lanes JOIN roster_days ON roster_days.id = roster_lanes.roster_day_id WHERE roster_days.venue_id = ? AND roster_days.roster_group_id = ? AND roster_days.operational_date >= ? AND roster_days.operational_date < ? AND (?::date IS NULL OR roster_days.operational_date = ?::date) ORDER BY roster_lanes.id FOR UPDATE OF roster_lanes"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd, selectedDate, selectedDate)
    _slotLocks :: [Only UUID] <- sqlQuery
        "SELECT roster_slots.id FROM roster_slots JOIN roster_days ON roster_days.id = roster_slots.roster_day_id WHERE roster_days.venue_id = ? AND roster_days.roster_group_id = ? AND roster_days.operational_date >= ? AND roster_days.operational_date < ? AND (?::date IS NULL OR roster_days.operational_date = ?::date) AND roster_slots.deleted_at IS NULL ORDER BY roster_slots.id FOR UPDATE OF roster_slots"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd, selectedDate, selectedDate)
    pure ()

lockRosterTemplateName :: (?modelContext :: ModelContext) => Id RosterGroup -> Text -> IO ()
lockRosterTemplateName rosterGroupId normalizedName = do
    let lockKey = "roster-template-name:" <> tshow (unpackId rosterGroupId) <> ":" <> Text.toCaseFold normalizedName
    _lockResults :: [Only Bool] <- sqlQuery
        "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_template_name_lock"
        (Only lockKey)
    pure ()
