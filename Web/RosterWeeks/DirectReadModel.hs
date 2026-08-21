{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.DirectReadModel
    ( RosterBaseFacts (..)
    , buildRosterStaffOptionStatesDirect
    , buildRosterStaffOptionStatesForSlotsDirect
    , buildSlotConflictsDirect
    , buildSlotConflictsForSlotsDirect
    , fetchRosterBaseFactsDirect
    , fetchRosterNotificationWindowDays
    , fetchRosterStaffPanelEntriesDirect
    ) where

import Application.Helper.Conflict
import Application.Helper.Profiling
import Application.Helper.RosterGroups (fetchCurrentVenueActiveStaff)
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Data.Coerce (coerce)
import Data.List (nubBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlQuery)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange
import Web.RosterWeeks.LegacyCompatibility (fetchLegacyRosterWeekForScope,
                                            legacyPlanningRosterWeekForScope)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types

fetchRosterNotificationWindowDays :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Day -> Day -> IO [RosterDay]
fetchRosterNotificationWindowDays venueId rosterGroupId windowStart windowEnd =
    query @RosterDay
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
        |> filterWhereLessThan (#operationalDate, windowEnd)
        |> orderByAsc #operationalDate
        |> fetch

-- Database-near base facts for roster read-model rendering. These reads are
-- request-local and do not use a cross-request HTML/read-model cache.
data RosterBaseFacts = RosterBaseFacts
    { baseRosterWeek             :: !(Maybe RosterWeek)
    , baseRosterDays             :: ![RosterDay]
    , baseAllSlots               :: ![RosterSlot]
    , baseVisibleSlots           :: ![RosterSlot]
    , baseOrderedSlotDefinitions :: ![RosterWindowLane]
    , baseShiftTypes             :: ![ShiftType]
    , baseEligibleStaff          :: ![Staff]
    , basePanelStaff             :: ![Staff]
    , baseAssignedStaff          :: ![Staff]
    , baseStaffMembers           :: ![Staff]
    }

fetchRosterBaseFactsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> IO (Maybe RosterBaseFacts)
fetchRosterBaseFactsDirect scope =
    profileActionSpan "roster.direct.base_facts" do
        let rosterGroupId = scope.rosterWindowRosterGroupId
        venueConfig <- query @VenueConfig
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOne
        rosterGroupInVenue <- profileActionSpan "roster.direct.validate_group_scope" do
            query @RosterGroup
                |> filterWhere (#id, rosterGroupId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchExists
        if not (rosterWindowScopeMatchesConfig venueConfig scope) || not rosterGroupInVenue
            then pure Nothing
            else Just <$> fetchRosterBaseFactsForScopeDirect scope

fetchRosterBaseFactsForScopeDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterWindowScope -> IO RosterBaseFacts
fetchRosterBaseFactsForScopeDirect scope =
    profileActionSpan "roster.direct.base_facts_for_date_range" do
        let rosterGroupId = scope.rosterWindowRosterGroupId
        let windowStartDate = scope.rosterWindowStart
        let windowEndDate = scope.rosterWindowEnd
        rosterWeekOrNothing <- profileActionSpan "roster.direct.fetch_legacy_week" (fetchLegacyRosterWeekForScope scope)
        window <- profileActionSpan "roster.direct.fetch_dated_window" (fetchRosterWindow scope.rosterWindowVenueId rosterGroupId windowStartDate)
        let rosterDays =
                map
                    (projectedRosterDay scope.rosterWindowVenueId rosterGroupId (get #id <$> rosterWeekOrNothing) windowStartDate)
                    window.rosterWindowProjectedDays
        let windowIsPublished = rosterWindowIsPublished window
        planningWeek <- case rosterWeekOrNothing of
            Just rosterWeek -> pure (rosterWeek |> set #isLive windowIsPublished)
            Nothing -> legacyPlanningRosterWeekForScope scope windowIsPublished
        allSlots <- profileActionSpan "roster.direct.fetch_dated_slots" do
            orderedSlotIds :: [PG.Only UUID.UUID] <- sqlQuery
                "SELECT roster_slots.id \
                \FROM roster_slots \
                \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                \WHERE roster_days.venue_id = ? \
                \AND roster_days.roster_group_id = ? \
                \AND roster_days.operational_date >= ? \
                \AND roster_days.operational_date < ? \
                \AND roster_slots.deleted_at IS NULL \
                \ORDER BY roster_days.operational_date, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at"
                (unpackId currentVenueId, unpackId rosterGroupId, windowStartDate, windowEndDate)
            fetchRosterSlotsInIdOrder orderedSlotIds
        let orderedSlotDefinitions = window.rosterWindowLanes
        let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
        eligibleStaffMembers <- profileActionSpan "roster.direct.fetch_eligible_staff" (fetchEligibleRosterGroupStaffDirect rosterGroupId)
        panelStaffMembers <- profileActionSpan "roster.direct.fetch_panel_staff" (fetchRosterGroupStaffForPanelDirect rosterGroupId)
        assignedStaffMembers <- profileActionSpan "roster.direct.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
        shiftTypes <- profileActionSpan "roster.direct.fetch_shift_types" fetchCurrentVenueRosterShiftTypesDirect
        let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
        pure RosterBaseFacts
            { baseRosterWeek = Just planningWeek
            , baseRosterDays = rosterDays
            , baseAllSlots = allSlots
            , baseVisibleSlots = visibleSlots
            , baseOrderedSlotDefinitions = orderedSlotDefinitions
            , baseShiftTypes = shiftTypes
            , baseEligibleStaff = eligibleStaffMembers
            , basePanelStaff = panelStaffMembers
            , baseAssignedStaff = assignedStaffMembers
            , baseStaffMembers = staffMembers
            }

fetchEligibleRosterGroupStaffDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchEligibleRosterGroupStaffDirect rosterGroupId = do
    orderedStaffIds :: [PG.Only UUID.UUID] <- sqlQuery
        "SELECT staff.id \
        \FROM staff \
        \JOIN staff_roster_groups ON staff_roster_groups.staff_id = staff.id \
        \WHERE staff_roster_groups.roster_group_id = ? \
        \AND staff_roster_groups.deleted_at IS NULL \
        \AND staff.venue_id = ? \
        \AND staff.is_active = TRUE \
        \AND staff.archived_at IS NULL \
        \AND (staff.pay_assignment_mode = 'roster_only' \
        \     OR (staff.pay_assignment_mode = 'award_rate' AND EXISTS (SELECT 1 FROM award_levels WHERE award_levels.id = staff.default_award_level_id AND award_levels.is_active = TRUE)) \
        \     OR (staff.pay_assignment_mode = 'xero_rate' AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE xero_imported_pay_items.id = staff.imported_xero_pay_item_id AND xero_imported_pay_items.venue_id = staff.venue_id AND xero_imported_pay_items.archived_at IS NULL AND xero_imported_pay_items.provider_available = TRUE)) \
        \ ) \
        \ORDER BY staff.last_name"
        (unpackId rosterGroupId, unpackId currentVenueId)
    fetchStaffInIdOrder orderedStaffIds

fetchRosterStaffPanelEntriesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterStaffPanelScope -> RosterWindowScope -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntriesDirect panelScope scope = do
    baseFactsOrNothing <- fetchRosterBaseFactsDirect scope
    case baseFactsOrNothing of
        Nothing -> pure []
        Just baseFacts -> do
            panelStaffMembers <-
                case panelScope of
                    RosterStaffPanelCurrentGroup -> pure baseFacts.basePanelStaff
                    RosterStaffPanelAllVenue     -> fetchCurrentVenueActiveStaff
            fetchRosterStaffPanelEntriesForScope panelScope panelStaffMembers baseFacts.baseVisibleSlots

fetchRosterSlotsInIdOrder :: (?modelContext :: ModelContext) => [PG.Only UUID.UUID] -> IO [RosterSlot]
fetchRosterSlotsInIdOrder [] = pure []
fetchRosterSlotsInIdOrder orderedIds = do
    records <- query @RosterSlot
        |> filterWhereIn (#id, [Id recordId | PG.Only recordId <- orderedIds])
        |> fetch
    let recordsById = Map.fromList [(unpackId record.id, record) | record <- records]
    pure (mapMaybe (\(PG.Only recordId) -> Map.lookup recordId recordsById) orderedIds)

fetchStaffInIdOrder :: (?modelContext :: ModelContext) => [PG.Only UUID.UUID] -> IO [Staff]
fetchStaffInIdOrder [] = pure []
fetchStaffInIdOrder orderedIds = do
    records <- query @Staff
        |> filterWhereIn (#id, [Id recordId | PG.Only recordId <- orderedIds])
        |> fetch
    let recordsById = Map.fromList [(unpackId record.id, record) | record <- records]
    pure (mapMaybe (\(PG.Only recordId) -> Map.lookup recordId recordsById) orderedIds)



fetchRosterGroupStaffForPanelDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchRosterGroupStaffForPanelDirect rosterGroupId = do
    orderedStaffIds :: [PG.Only UUID.UUID] <- sqlQuery
        "SELECT staff.id \
        \FROM staff \
        \JOIN staff_roster_groups ON staff_roster_groups.staff_id = staff.id \
        \WHERE staff_roster_groups.roster_group_id = ? \
        \AND staff_roster_groups.deleted_at IS NULL \
        \AND staff.venue_id = ? \
        \AND staff.is_active = TRUE \
        \AND staff.archived_at IS NULL \
        \ORDER BY staff.last_name"
        (unpackId rosterGroupId, unpackId currentVenueId)
    fetchStaffInIdOrder orderedStaffIds

fetchCurrentVenueRosterShiftTypesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesDirect = do
    shiftTypeIds :: [PG.Only UUID.UUID] <- sqlQuery
        "SELECT shift_types.id \
        \FROM shift_types \
        \WHERE shift_types.venue_id = ? \
        \AND shift_types.archived_at IS NULL \
        \AND shift_types.is_active = TRUE \
        \AND (shift_types.pay_assignment_mode IN ('staff_default', 'roster_only') \
        \     OR (shift_types.pay_assignment_mode = 'award_rate' AND EXISTS (SELECT 1 FROM award_levels WHERE award_levels.id = shift_types.override_award_level_id AND award_levels.is_active = TRUE)) \
        \     OR (shift_types.pay_assignment_mode = 'xero_rate' AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE xero_imported_pay_items.id = shift_types.imported_xero_pay_item_id AND xero_imported_pay_items.venue_id = shift_types.venue_id AND xero_imported_pay_items.archived_at IS NULL AND xero_imported_pay_items.provider_available = TRUE)) \
        \ ) \
        \ORDER BY shift_types.sort_order, shift_types.created_at"
        (PG.Only (unpackId currentVenueId))
    records <- query @ShiftType |> filterWhereIn (#id, [Id shiftTypeId | PG.Only shiftTypeId <- shiftTypeIds]) |> fetch
    let recordsById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- records]
    pure (mapMaybe (\(PG.Only shiftTypeId) -> Map.lookup shiftTypeId recordsById) shiftTypeIds)

buildRosterStaffOptionStatesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStatesDirect assignmentFilters weekStartDate visibleSlots =
    buildRosterStaffOptionStatesForSlotsDirect assignmentFilters weekStartDate visibleSlots visibleSlots

buildRosterStaffOptionStatesForSlotsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterSlot] -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStatesForSlotsDirect assignmentFilters _weekStartDate factSlots targetSlots staffMembers
    | null targetSlots || null staffMembers = pure Map.empty
    | otherwise =
        Map.fromList . map optionStateEntry <$> (sqlQuery
            "WITH params AS ( \
            \    SELECT ?::uuid AS venue_id, ?::boolean AS hide_ideal, ?::boolean AS hide_unavailable, ?::boolean AS hide_leave, ?::boolean AS hide_today \
            \), fact_slots AS ( \
            \    SELECT roster_slots.id, roster_slots.roster_day_id, roster_slots.assignment_state, roster_slots.staff_id, COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date) AS roster_date, EXTRACT(DOW FROM COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date))::int AS weekday_index \
            \    FROM roster_slots \
            \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \    CROSS JOIN params \
            \    WHERE roster_slots.id = ANY(?) AND roster_slots.deleted_at IS NULL \
            \), target_slots AS ( \
            \    SELECT id, roster_day_id, assignment_state, staff_id, roster_date, weekday_index FROM fact_slots WHERE id = ANY(?) \
            \), staff_scope AS ( \
            \    SELECT staff.id, staff.ideal_shifts_per_week FROM staff CROSS JOIN params WHERE staff.id = ANY(?) AND staff.venue_id = params.venue_id \
            \), shift_counts AS ( \
            \    SELECT staff_id, COUNT(*)::int AS assigned_count FROM fact_slots WHERE assignment_state = 'staff' AND staff_id IS NOT NULL GROUP BY staff_id \
            \), day_counts AS ( \
            \    SELECT roster_day_id, staff_id, COUNT(*)::int AS assigned_day_count FROM fact_slots WHERE assignment_state = 'staff' AND staff_id IS NOT NULL GROUP BY roster_day_id, staff_id \
            \) \
            \SELECT target_slots.id, staff_scope.id, COALESCE(shift_counts.assigned_count, 0)::int, \
            \       ((CASE WHEN params.hide_ideal AND COALESCE(shift_counts.assigned_count, 0) >= staff_scope.ideal_shifts_per_week THEN 1 ELSE 0 END) + \
            \        (CASE WHEN params.hide_unavailable AND NOT EXISTS ( \
            \           SELECT 1 FROM staff_shift_preferences \
            \           WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = staff_scope.id \
            \             AND staff_shift_preferences.weekday_index = target_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \        ) THEN 2 ELSE 0 END) + \
            \        (CASE WHEN params.hide_leave AND EXISTS ( \
            \           SELECT 1 FROM leave_requests \
            \           WHERE leave_requests.venue_id = params.venue_id AND leave_requests.staff_id = staff_scope.id AND leave_requests.status = 'approved' \
            \             AND leave_requests.deleted_at IS NULL AND leave_requests.start_date <= target_slots.roster_date AND leave_requests.end_date > target_slots.roster_date \
            \        ) THEN 4 ELSE 0 END) + \
            \        (CASE WHEN params.hide_today AND (COALESCE(day_counts.assigned_day_count, 0) - CASE WHEN target_slots.staff_id = staff_scope.id THEN 1 ELSE 0 END) > 0 THEN 8 ELSE 0 END))::int \
            \FROM target_slots \
            \CROSS JOIN staff_scope \
            \CROSS JOIN params \
            \LEFT JOIN shift_counts ON shift_counts.staff_id = staff_scope.id \
            \LEFT JOIN day_counts ON day_counts.roster_day_id = target_slots.roster_day_id AND day_counts.staff_id = staff_scope.id \
            \ORDER BY target_slots.id, staff_scope.id"
            ( unpackId currentVenueId
            , assignmentFilters.hideStaffAtIdealShifts
            , assignmentFilters.hideStaffUnavailable
            , assignmentFilters.hideStaffOnApprovedLeave
            , assignmentFilters.hideStaffAlreadyAssignedToday
            , map (coerce . (.id)) factSlots :: [UUID.UUID]
            , map (coerce . (.id)) targetSlots :: [UUID.UUID]
            , map (coerce . (.id)) staffMembers :: [UUID.UUID]
            ) :: IO [(UUID.UUID, UUID.UUID, Int, Int)])
    where
        optionStateEntry (slotId, staffId, assignedShiftCount, hiddenFlags) =
            let hiddenByIdeal = hiddenFlags `mod` 2 == 1
                hiddenByUnavailable = hiddenFlags `div` 2 `mod` 2 == 1
                hiddenByLeave = hiddenFlags `div` 4 `mod` 2 == 1
                hiddenByToday = hiddenFlags `div` 8 `mod` 2 == 1
                hidden = hiddenFlags /= 0
             in ( (slotId, staffId)
                , RosterAssignmentOptionState
                    { optionHidden = hidden
                    , optionAssignedShiftCount = assignedShiftCount
                    , optionHiddenByIdeal = hiddenByIdeal
                    , optionHiddenByUnavailable = hiddenByUnavailable
                    , optionHiddenByLeave = hiddenByLeave
                    , optionHiddenByAssignedToday = hiddenByToday
                    }
                )

buildSlotConflictsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Calendar.Day -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsDirect rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate visibleSlots =
    buildSlotConflictsForSlotsDirect rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate visibleSlots visibleSlots

buildSlotConflictsForSlotsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> Calendar.Day -> [RosterSlot] -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsForSlotsDirect _rosterGroupId lateToEarlyMinStartGapMinutes _weekStartDate factSlots targetSlots
    | null assignedSlotIds || null targetSlotIds = pure []
    | otherwise = do
        rows <- (sqlQuery
            "WITH params AS ( \
            \    SELECT ?::uuid AS venue_id, ?::int AS late_gap_seconds \
            \), assigned_slots AS ( \
            \    SELECT roster_slots.id, roster_slots.roster_day_id, roster_slots.staff_id, roster_slots.starts_at, roster_slots.timezone, COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date) AS roster_date, \
            \           EXTRACT(DOW FROM COALESCE((roster_slots.starts_at AT TIME ZONE roster_slots.timezone)::date, roster_days.operational_date))::int AS weekday_index, \
            \           EXTRACT(EPOCH FROM roster_slots.starts_at) AS start_second_of_week \
            \    FROM roster_slots \
            \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \    CROSS JOIN params \
            \    WHERE roster_slots.id = ANY(?) AND roster_slots.assignment_state = 'staff' AND roster_slots.staff_id IS NOT NULL AND roster_slots.deleted_at IS NULL \
            \), week_counts AS ( \
            \    SELECT staff_id, COUNT(*)::int AS week_count FROM assigned_slots GROUP BY staff_id \
            \), day_counts AS ( \
            \    SELECT roster_day_id, staff_id, COUNT(*)::int AS day_count FROM assigned_slots GROUP BY roster_day_id, staff_id \
            \), timeline AS ( \
            \    SELECT id, start_second_of_week - LAG(start_second_of_week) OVER (PARTITION BY staff_id ORDER BY start_second_of_week, id) AS previous_gap, \
            \           LEAD(start_second_of_week) OVER (PARTITION BY staff_id ORDER BY start_second_of_week, id) - start_second_of_week AS next_gap \
            \    FROM assigned_slots WHERE starts_at IS NOT NULL \
            \), facts AS ( \
            \    SELECT assigned_slots.id, 'duplicate_assignment'::text AS conflict_type, 1 AS priority \
            \    FROM assigned_slots JOIN day_counts ON day_counts.roster_day_id = assigned_slots.roster_day_id AND day_counts.staff_id = assigned_slots.staff_id \
            \    WHERE day_counts.day_count > 1 \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'leave_conflict'::text, 2 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE EXISTS ( \
            \        SELECT 1 FROM leave_requests \
            \        WHERE leave_requests.venue_id = params.venue_id AND leave_requests.staff_id = assigned_slots.staff_id AND leave_requests.status = 'approved' \
            \          AND leave_requests.deleted_at IS NULL AND leave_requests.start_date <= assigned_slots.roster_date AND leave_requests.end_date > assigned_slots.roster_date \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'late_to_early'::text, 3 \
            \    FROM assigned_slots JOIN timeline ON timeline.id = assigned_slots.id CROSS JOIN params \
            \    WHERE params.late_gap_seconds > 0 AND (COALESCE(timeline.previous_gap, params.late_gap_seconds) < params.late_gap_seconds OR COALESCE(timeline.next_gap, params.late_gap_seconds) < params.late_gap_seconds) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'preference_day_unavailable'::text, 4 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE NOT EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'preference_slot_mismatch'::text, 5 \
            \    FROM assigned_slots CROSS JOIN params \
            \    WHERE assigned_slots.starts_at IS NOT NULL \
            \      AND EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \    ) \
            \      AND NOT EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \          AND (EXTRACT(HOUR FROM (assigned_slots.starts_at AT TIME ZONE assigned_slots.timezone))::int * 60 + EXTRACT(MINUTE FROM (assigned_slots.starts_at AT TIME ZONE assigned_slots.timezone))::int) BETWEEN staff_shift_preferences.preferred_start_hour * 60 AND staff_shift_preferences.preferred_end_hour * 60 \
            \    ) \
            \    UNION ALL \
            \    SELECT assigned_slots.id, 'ideal_shift_threshold'::text, 6 \
            \    FROM assigned_slots \
            \    JOIN week_counts ON week_counts.staff_id = assigned_slots.staff_id \
            \    CROSS JOIN params \
            \    JOIN staff ON staff.id = assigned_slots.staff_id AND staff.venue_id = params.venue_id \
            \    WHERE week_counts.week_count > staff.ideal_shifts_per_week \
            \) \
            \SELECT id, conflict_type FROM facts WHERE id = ANY(?) ORDER BY id, priority"
            ( unpackId currentVenueId
            , lateToEarlyMinStartGapMinutes * 60
            , assignedSlotIds
            , targetSlotIds
            ) :: IO [(UUID.UUID, Text)])
        let conflictsBySlot = Map.fromListWith (<>) [(Id slotId, [conflictForType conflictTypeText]) | (slotId, conflictTypeText) <- rows]
        pure (Map.toList (Map.map sort conflictsBySlot))
    where
        assignedSlotIds = map (coerce . (.id)) (filter rosterShiftIsStaffAssigned factSlots) :: [UUID.UUID]
        targetSlotIds = map (coerce . (.id)) targetSlots :: [UUID.UUID]

conflictForType :: Text -> RosterConflict
conflictForType "duplicate_assignment" = rosterConflict DuplicateAssignment "Multiple shifts rostered on the same day."
conflictForType "leave_conflict" = rosterConflict LeaveConflict "Staff member has an approved unavailable period."
conflictForType "late_to_early" = rosterConflict LateToEarlyConflict "Start-to-start gap is below venue minimum."
conflictForType "preference_day_unavailable" = rosterConflict ShiftPreferenceDayUnavailable "Preference conflict"
conflictForType "preference_slot_mismatch" = rosterConflict ShiftPreferenceSlotMismatch "Preferred start window conflict"
conflictForType "ideal_shift_threshold" = rosterConflict IdealShiftThresholdExceeded "Ideal shifts exceeded"
conflictForType other = error ("Unknown roster conflict type from direct SQL: " <> cs other)

rosterConflict :: ConflictType -> Text -> RosterConflict
rosterConflict conflictType message =
    RosterConflict
        { conflictType
        , severity = getConflictSeverity conflictType
        , message
        }
