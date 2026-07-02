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
    , fetchRosterBaseFactsForWeekDirect
    , fetchRosterStaffPanelEntriesDirect
    ) where

import Application.Helper.Conflict
import Application.Helper.Profiling
import Application.Helper.RosterGroups (fetchCurrentVenueActiveStaff)
import Data.Coerce (coerce)
import Data.List (nubBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlQuery)
import Web.Controller.Prelude
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types

-- Database-near base facts for roster read-model rendering. These reads are
-- request-local and do not use a cross-request HTML/read-model cache.
data RosterBaseFacts = RosterBaseFacts
    { baseRosterWeek             :: !RosterWeek
    , baseRosterDays             :: ![RosterDay]
    , baseAllSlots               :: ![RosterSlot]
    , baseVisibleSlots           :: ![RosterSlot]
    , baseOrderedSlotDefinitions :: ![RosterWeekSlotDefinition]
    , baseShiftTypes             :: ![ShiftType]
    , baseEligibleStaff          :: ![Staff]
    , baseAssignedStaff          :: ![Staff]
    , baseStaffMembers           :: ![Staff]
    }

fetchRosterBaseFactsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Int -> IO (Maybe RosterBaseFacts)
fetchRosterBaseFactsDirect rosterGroupId weekOffset =
    profileActionSpan "roster.direct.base_facts" do
        rosterGroupInVenue <- profileActionSpan "roster.direct.validate_group_scope" do
            query @RosterGroup
                |> filterWhere (#id, rosterGroupId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchExists
        if not rosterGroupInVenue
            then pure Nothing
            else do
                _ <- profileActionSpan "roster.direct.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
                rosterWeekOrNothing <- profileActionSpan "roster.direct.fetch_week" do
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                        |> filterWhere (#weekOffset, weekOffset)
                        |> fetchOneOrNothing
                case rosterWeekOrNothing of
                    Nothing -> pure Nothing
                    Just rosterWeek -> Just <$> fetchRosterBaseFactsForWeekDirect rosterGroupId rosterWeek

fetchRosterBaseFactsForWeekDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterWeek -> IO RosterBaseFacts
fetchRosterBaseFactsForWeekDirect rosterGroupId rosterWeek =
    profileActionSpan "roster.direct.base_facts_for_week" do
        rosterDays <- profileActionSpan "roster.direct.fetch_days" do
            query @RosterDay
                |> filterWhere (#rosterWeekId, coerce (get #id rosterWeek))
                |> orderBy #dayOffset
                |> fetch

        allSlots <- profileActionSpan "roster.direct.fetch_slots" do
            sqlQuery
                "SELECT roster_slots.* \
                \FROM roster_slots \
                \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
                \WHERE roster_days.roster_week_id = ? \
                \AND roster_slots.deleted_at IS NULL \
                \ORDER BY roster_days.day_offset, roster_slots.row_index, roster_slots.slot_sort_order, roster_slots.created_at"
                (PG.Only (unpackId rosterWeek.id))

        orderedSlotDefinitions <- profileActionSpan "roster.direct.fetch_slot_definitions" do
            query @RosterWeekSlotDefinition
                |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                |> filterWhere (#deletedAt, Nothing)
                |> orderByAsc #sortOrder
                |> orderByAsc #createdAt
                |> fetch

        let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
        eligibleStaffMembers <- profileActionSpan "roster.direct.fetch_eligible_staff" (fetchEligibleRosterGroupStaffDirect rosterGroupId)
        assignedStaffMembers <- profileActionSpan "roster.direct.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
        shiftTypes <- profileActionSpan "roster.direct.fetch_shift_types" fetchCurrentVenueRosterShiftTypesDirect
        let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
        pure RosterBaseFacts
            { baseRosterWeek = rosterWeek
            , baseRosterDays = rosterDays
            , baseAllSlots = allSlots
            , baseVisibleSlots = visibleSlots
            , baseOrderedSlotDefinitions = orderedSlotDefinitions
            , baseShiftTypes = shiftTypes
            , baseEligibleStaff = eligibleStaffMembers
            , baseAssignedStaff = assignedStaffMembers
            , baseStaffMembers = staffMembers
            }

fetchEligibleRosterGroupStaffDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchEligibleRosterGroupStaffDirect rosterGroupId =
    sqlQuery
        "SELECT staff.* \
        \FROM staff \
        \JOIN staff_roster_groups ON staff_roster_groups.staff_id = staff.id \
        \WHERE staff_roster_groups.roster_group_id = ? \
        \AND staff_roster_groups.deleted_at IS NULL \
        \AND staff.venue_id = ? \
        \AND staff.is_active = TRUE \
        \AND staff.archived_at IS NULL \
        \ORDER BY staff.last_name"
        (unpackId rosterGroupId, unpackId currentVenueId)

fetchRosterStaffPanelEntriesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterStaffPanelScope -> Id RosterGroup -> RosterWeek -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntriesDirect panelScope rosterGroupId rosterWeek = do
    panelStaffMembers <-
        case panelScope of
            RosterStaffPanelCurrentGroup -> fetchEligibleRosterGroupStaffDirect rosterGroupId
            RosterStaffPanelAllVenue     -> fetchCurrentVenueActiveStaff
    visibleSlots <- fetchVisibleRosterWeekSlotsDirect rosterWeek
    fetchRosterStaffPanelEntriesForScope panelScope panelStaffMembers visibleSlots

fetchVisibleRosterWeekSlotsDirect :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterSlot]
fetchVisibleRosterWeekSlotsDirect rosterWeek = do
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterWeekId, coerce (get #id rosterWeek))
            |> fetch
    slots <-
        sqlQuery
            "SELECT roster_slots.* \
            \FROM roster_slots \
            \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \WHERE roster_days.roster_week_id = ? \
            \AND roster_slots.deleted_at IS NULL"
            (PG.Only (unpackId rosterWeek.id))
    pure (filterVisibleRosterSlots rosterDays slots)

fetchAssignedShiftCountsDirect :: (?modelContext :: ModelContext) => RosterWeek -> IO [(UUID.UUID, Int)]
fetchAssignedShiftCountsDirect rosterWeek =
    sqlQuery
        "SELECT roster_slots.staff_id, COUNT(*)::int \
        \FROM roster_slots \
        \JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
        \WHERE roster_days.roster_week_id = ? \
        \AND roster_days.is_closed = FALSE \
        \AND roster_slots.deleted_at IS NULL \
        \AND roster_slots.staff_id IS NOT NULL \
        \GROUP BY roster_slots.staff_id"
        (PG.Only (unpackId rosterWeek.id))

fetchLinkedVenueMembershipsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Staff] -> IO [VenueMembership]
fetchLinkedVenueMembershipsDirect staffMembers = do
    let linkedUserIds = mapMaybe (.userId) staffMembers
    if null linkedUserIds
        then pure []
        else
            query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch

fetchCurrentVenueRosterShiftTypesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesDirect =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

buildRosterStaffOptionStatesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStatesDirect assignmentFilters weekStartDate visibleSlots =
    buildRosterStaffOptionStatesForSlotsDirect assignmentFilters weekStartDate visibleSlots visibleSlots

buildRosterStaffOptionStatesForSlotsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterSlot] -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStatesForSlotsDirect assignmentFilters weekStartDate factSlots targetSlots staffMembers
    | null targetSlots || null staffMembers = pure Map.empty
    | otherwise =
        Map.fromList . map optionStateEntry <$> (sqlQuery
            "WITH params AS ( \
            \    SELECT ?::date AS week_start, ?::uuid AS venue_id, ?::boolean AS hide_ideal, ?::boolean AS hide_unavailable, ?::boolean AS hide_leave, ?::boolean AS hide_today \
            \), fact_slots AS ( \
            \    SELECT roster_slots.*, roster_days.day_offset, (params.week_start + roster_days.day_offset) AS roster_date, EXTRACT(DOW FROM (params.week_start + roster_days.day_offset))::int AS weekday_index \
            \    FROM roster_slots \
            \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \    CROSS JOIN params \
            \    WHERE roster_slots.id = ANY(?) AND roster_slots.deleted_at IS NULL \
            \), target_slots AS ( \
            \    SELECT * FROM fact_slots WHERE id = ANY(?) \
            \), staff_scope AS ( \
            \    SELECT staff.id, staff.ideal_shifts_per_week FROM staff CROSS JOIN params WHERE staff.id = ANY(?) AND staff.venue_id = params.venue_id \
            \), shift_counts AS ( \
            \    SELECT staff_id, COUNT(*)::int AS assigned_count FROM fact_slots WHERE staff_id IS NOT NULL GROUP BY staff_id \
            \), day_counts AS ( \
            \    SELECT roster_day_id, staff_id, COUNT(*)::int AS assigned_day_count FROM fact_slots WHERE staff_id IS NOT NULL GROUP BY roster_day_id, staff_id \
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
            ( weekStartDate
            , unpackId currentVenueId
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
buildSlotConflictsForSlotsDirect _rosterGroupId lateToEarlyMinStartGapMinutes weekStartDate factSlots targetSlots
    | null assignedSlotIds || null targetSlotIds = pure []
    | otherwise = do
        rows <- (sqlQuery
            "WITH params AS ( \
            \    SELECT ?::date AS week_start, ?::uuid AS venue_id, ?::int AS late_gap_minutes \
            \), assigned_slots AS ( \
            \    SELECT roster_slots.*, roster_days.day_offset, (params.week_start + roster_days.day_offset) AS roster_date, \
            \           EXTRACT(DOW FROM (params.week_start + roster_days.day_offset))::int AS weekday_index, \
            \           (roster_days.day_offset * 1440 + EXTRACT(HOUR FROM roster_slots.start_time)::int * 60 + EXTRACT(MINUTE FROM roster_slots.start_time)::int) AS start_minute_of_week \
            \    FROM roster_slots \
            \    JOIN roster_days ON roster_days.id = roster_slots.roster_day_id \
            \    CROSS JOIN params \
            \    WHERE roster_slots.id = ANY(?) AND roster_slots.staff_id IS NOT NULL AND roster_slots.deleted_at IS NULL \
            \), week_counts AS ( \
            \    SELECT staff_id, COUNT(*)::int AS week_count FROM assigned_slots GROUP BY staff_id \
            \), day_counts AS ( \
            \    SELECT roster_day_id, staff_id, COUNT(*)::int AS day_count FROM assigned_slots GROUP BY roster_day_id, staff_id \
            \), timeline AS ( \
            \    SELECT id, start_minute_of_week - LAG(start_minute_of_week) OVER (PARTITION BY staff_id ORDER BY start_minute_of_week, id) AS previous_gap, \
            \           LEAD(start_minute_of_week) OVER (PARTITION BY staff_id ORDER BY start_minute_of_week, id) - start_minute_of_week AS next_gap \
            \    FROM assigned_slots WHERE start_time IS NOT NULL \
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
            \    WHERE params.late_gap_minutes > 0 AND (COALESCE(timeline.previous_gap, params.late_gap_minutes) < params.late_gap_minutes OR COALESCE(timeline.next_gap, params.late_gap_minutes) < params.late_gap_minutes) \
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
            \    WHERE assigned_slots.start_time IS NOT NULL \
            \      AND EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \    ) \
            \      AND NOT EXISTS ( \
            \        SELECT 1 FROM staff_shift_preferences \
            \        WHERE staff_shift_preferences.venue_id = params.venue_id AND staff_shift_preferences.staff_id = assigned_slots.staff_id \
            \          AND staff_shift_preferences.weekday_index = assigned_slots.weekday_index AND staff_shift_preferences.deleted_at IS NULL \
            \          AND (EXTRACT(HOUR FROM assigned_slots.start_time)::int * 60 + EXTRACT(MINUTE FROM assigned_slots.start_time)::int) BETWEEN staff_shift_preferences.preferred_start_hour * 60 AND staff_shift_preferences.preferred_end_hour * 60 \
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
            ( weekStartDate
            , unpackId currentVenueId
            , lateToEarlyMinStartGapMinutes
            , assignedSlotIds
            , targetSlotIds
            ) :: IO [(UUID.UUID, Text)])
        let conflictsBySlot = Map.fromListWith (<>) [(Id slotId, [conflictForType conflictTypeText]) | (slotId, conflictTypeText) <- rows]
        pure (Map.toList (Map.map sort conflictsBySlot))
    where
        assignedSlotIds = map (coerce . (.id)) (filter (isJust . (.staffId)) factSlots) :: [UUID.UUID]
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
