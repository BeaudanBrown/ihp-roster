{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.DirectReadModel
    ( RosterBaseFacts (..)
    , buildSlotConflictsDirect
    , buildSlotConflictsForSlotsDirect
    , RosterConflictDecodeError (..)
    , decodeRosterConflictType
    , unavailableRosterConflict
    , fetchRosterBaseFactsDirect
    , fetchRosterNotificationWindowDays
    ) where

import Application.Error.Domain
import Application.Error.Telemetry (recordAppError)
import Application.Helper.Conflict
import Application.Helper.Profiling
import Application.PayAssignment (PayAssignmentScope (..), PayReferenceRequirement (..), payAssignmentModesRequiring)
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Data.Coerce (coerce)
import Data.List (nubBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import GHC.Generics (Generic)
import IHP.ModelSupport (columnNames, unsafeSqlQuery)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange
import Web.RosterWeeks.Rows
import Web.RosterWeeks.StaffOptions (fetchAssignedRosterWeekStaff)
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
    { baseRosterWeek             :: !(Maybe RosterWindowState)
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
        window <- profileActionSpan "roster.direct.fetch_dated_window" (fetchRosterWindow scope.rosterWindowVenueId rosterGroupId windowStartDate)
        let rosterDays =
                map
                    (projectedRosterDay scope.rosterWindowVenueId rosterGroupId)
                    window.rosterWindowProjectedDays
        let windowState = RosterWindowState
                { windowRosterGroupId = unpackId rosterGroupId
                , windowIsPublished = rosterWindowIsPublished window
                , windowHasPublishedDays = any ((== Published) . (.publicationState)) rosterDays
                }
        allSlots <- profileActionSpan "roster.direct.fetch_dated_slots" do
            orderedSlotIds :: [PG.Only UUID.UUID] <- unsafeSqlQuery
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
            { baseRosterWeek = Just windowState
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
fetchEligibleRosterGroupStaffDirect rosterGroupId =
    unsafeSqlQuery
        (rosterGroupStaffSelect <> " AND (staff.pay_assignment_mode = ANY (?::pay_assignment_mode_enum[]) \
        \     OR (staff.pay_assignment_mode = ANY (?::pay_assignment_mode_enum[]) AND EXISTS (SELECT 1 FROM award_levels WHERE award_levels.id = staff.default_award_level_id AND award_levels.is_active = TRUE)) \
        \     OR (staff.pay_assignment_mode = ANY (?::pay_assignment_mode_enum[]) AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE xero_imported_pay_items.id = staff.imported_xero_pay_item_id AND xero_imported_pay_items.venue_id = staff.venue_id AND xero_imported_pay_items.archived_at IS NULL AND xero_imported_pay_items.provider_available = TRUE)) \
        \ ) \
        \ORDER BY staff.last_name")
        ( unpackId rosterGroupId, unpackId currentVenueId
        , payAssignmentModesRequiring StaffPayScope NoPayReference
        , payAssignmentModesRequiring StaffPayScope ActiveAwardReference
        , payAssignmentModesRequiring StaffPayScope AvailableXeroReference
        )

fetchRosterSlotsInIdOrder :: (?modelContext :: ModelContext) => [PG.Only UUID.UUID] -> IO [RosterSlot]
fetchRosterSlotsInIdOrder [] = pure []
fetchRosterSlotsInIdOrder orderedIds = do
    records <- query @RosterSlot
        |> filterWhereIn (#id, [Id recordId | PG.Only recordId <- orderedIds])
        |> fetch
    let recordsById = Map.fromList [(unpackId record.id, record) | record <- records]
    pure (mapMaybe (\(PG.Only recordId) -> Map.lookup recordId recordsById) orderedIds)

-- IHP innerJoin requires identical field types, but this schema exposes Staff.id
-- as Id Staff and StaffRosterGroup.staffId as UUID. Keep that join SQL-local;
-- return generated-order columns directly, never physical-order SELECT * or an
-- ordered-ID refetch. Membership multiplicity and PostgreSQL name ties survive.
rosterGroupStaffSelect :: PG.Query
rosterGroupStaffSelect =
    "SELECT " <> fromString (cs (Text.intercalate ", " (map ("staff." <>) (columnNames @Staff)))) <>
    " FROM staff \
    \JOIN staff_roster_groups ON staff_roster_groups.staff_id = staff.id \
    \WHERE staff_roster_groups.roster_group_id = ? \
    \AND staff_roster_groups.deleted_at IS NULL \
    \AND staff.venue_id = ? \
    \AND staff.is_active = TRUE \
    \AND staff.archived_at IS NULL"


fetchRosterGroupStaffForPanelDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchRosterGroupStaffForPanelDirect rosterGroupId =
    unsafeSqlQuery
        (rosterGroupStaffSelect <> " ORDER BY staff.last_name")
        (unpackId rosterGroupId, unpackId currentVenueId)

fetchCurrentVenueRosterShiftTypesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesDirect =
    -- Keep EXISTS so PostgreSQL can hash reference inventories once. Correlated
    -- IN can rescan an inventory per row. The nullable field anchor is required
    -- by filterWhereSql; its IS NOT NULL guard is implied by the equality below.
    query @ShiftType
        |> queryOr
            (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope NoPayReference))
            (queryOr
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope ActiveAwardReference)
                    . filterWhereSql (#overrideAwardLevelId, "IS NOT NULL AND EXISTS (SELECT 1 FROM award_levels WHERE id = shift_types.override_award_level_id AND is_active = TRUE)"))
                (filterWhereIn (#payAssignmentMode, payAssignmentModesRequiring ShiftTypePayScope AvailableXeroReference)
                    . filterWhereSql (#importedXeroPayItemId, "IS NOT NULL AND EXISTS (SELECT 1 FROM xero_imported_pay_items WHERE id = shift_types.imported_xero_pay_item_id AND venue_id = shift_types.venue_id AND archived_at IS NULL AND provider_available = TRUE)")))
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
        |> filterWhere (#isActive, True)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

buildSlotConflictsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsDirect lateToEarlyMinStartGapMinutes visibleSlots =
    buildSlotConflictsForSlotsDirect lateToEarlyMinStartGapMinutes visibleSlots visibleSlots

buildSlotConflictsForSlotsDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> [RosterSlot] -> [RosterSlot] -> IO [(Id RosterSlot, [RosterConflict])]
buildSlotConflictsForSlotsDirect lateToEarlyMinStartGapMinutes factSlots targetSlots
    | null assignedSlotIds || null targetSlotIds = pure []
    | otherwise = do
        rows <- (unsafeSqlQuery
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
        decodedRows <- forM rows \(slotId, conflictTypeText) ->
            case decodeRosterConflictType conflictTypeText of
                Right conflict -> pure (Id slotId, [conflict])
                Left decodeError -> do
                    recordAppError (projectDomainError decodeError)
                    pure (Id slotId, [unavailableRosterConflict])
        let conflictsBySlot = Map.fromListWith (<>) decodedRows
        pure (Map.toList (Map.map sort conflictsBySlot))
    where
        assignedSlotIds = map (coerce . (.id)) (filter rosterShiftIsStaffAssigned factSlots) :: [UUID.UUID]
        targetSlotIds = map (coerce . (.id)) targetSlots :: [UUID.UUID]

data RosterConflictDecodeError
    = UnknownRosterConflictType
    deriving (Eq, Generic, Show)

instance DomainError RosterConflictDecodeError where
    appErrorProjection UnknownRosterConflictType =
        terminalErrorProjection "Conflict details unavailable"

decodeRosterConflictType :: Text -> Either RosterConflictDecodeError RosterConflict
decodeRosterConflictType "duplicate_assignment" = Right (rosterConflict DuplicateAssignment "Multiple shifts rostered on the same day.")
decodeRosterConflictType "leave_conflict" = Right (rosterConflict LeaveConflict "Staff member has an approved unavailable period.")
decodeRosterConflictType "late_to_early" = Right (rosterConflict LateToEarlyConflict "Start-to-start gap is below venue minimum.")
decodeRosterConflictType "preference_day_unavailable" = Right (rosterConflict ShiftPreferenceDayUnavailable "Preference conflict")
decodeRosterConflictType "preference_slot_mismatch" = Right (rosterConflict ShiftPreferenceSlotMismatch "Preferred start window conflict")
decodeRosterConflictType "ideal_shift_threshold" = Right (rosterConflict IdealShiftThresholdExceeded "Ideal shifts exceeded")
decodeRosterConflictType _ = Left UnknownRosterConflictType

unavailableRosterConflict :: RosterConflict
unavailableRosterConflict = rosterConflict ConflictDetailsUnavailable "Conflict details unavailable"

rosterConflict :: ConflictType -> Text -> RosterConflict
rosterConflict conflictType message =
    RosterConflict
        { conflictType
        , severity = getConflictSeverity conflictType
        , message
        }
