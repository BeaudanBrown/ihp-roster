module Web.RosterWeeks.StaffOptions
    ( buildRosterStaffOptionStates
    , fetchAssignedRosterWeekStaff
    , fetchRosterStaffPanelEntries
    , hasNoPreferredShiftsOnDay
    , isApprovedLeaveOn
    , rosterAssignmentOptionStateFor
    ) where

import Application.Helper.Conflict (weekdayIndexForDay)
import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus, venueRoleToText)
import Application.Helper.View (linkedActiveStaffForRosterPanel)
import Data.Coerce (coerce)
import Data.List (find, nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.Types

fetchRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Staff] -> [RosterSlot] -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntries staffMembers allSlots = do
    let linkedStaff = linkedActiveStaffForRosterPanel staffMembers
    let linkedUserIds = mapMaybe (.userId) linkedStaff

    memberships <-
        if null linkedUserIds
            then pure []
            else query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch

    let membershipsByUserId = Map.fromList [ (membership.userId, membership) | membership <- memberships ]
    let assignedShiftCountByStaffId = Map.fromListWith (+) [ (staffId, 1 :: Int) | slot <- allSlots, staffId <- maybeToList slot.staffId ]
    pure (map (buildPanelEntry membershipsByUserId assignedShiftCountByStaffId) linkedStaff)
    where
        buildPanelEntry membershipsByUserId assignedShiftCountByStaffId staff =
            let staffId = coerce (get #id staff)
                assignedShiftCount = Map.findWithDefault 0 staffId assignedShiftCountByStaffId
                roleText = case staff.userId >>= (`Map.lookup` membershipsByUserId) of
                    Just membership -> inputValue membership.venueRole
                    Nothing         -> venueRoleToText WorkerRole
             in RosterStaffPanelEntry
                    { staff
                    , assignedShiftCount
                    , userRole = roleText
                    }

fetchAssignedRosterWeekStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [RosterSlot] -> IO [Staff]
fetchAssignedRosterWeekStaff allSlots = do
    let assignedStaffIds = nub (mapMaybe (.staffId) allSlots)
    if null assignedStaffIds
        then pure []
        else
            query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#id, map Id assignedStaffIds)
                |> orderBy #lastName
                |> fetch

buildRosterStaffOptionStates :: (?modelContext :: ModelContext) => RosterAssignmentFilters -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStates assignmentFilters weekStartDate rosterDays visibleSlots staffMembers = do
    let staffIds = map (coerce . (.id)) staffMembers
    if null staffIds
        then pure Map.empty
        else do
            leaveRequests <- query @LeaveRequest
                |> filterWhereIn (#staffId, staffIds)
                |> fetch
            shiftPreferences <- query @StaffShiftPreference
                |> filterWhereIn (#staffId, staffIds)
                |> fetch

            let dayById = Map.fromList [ (coerce (get #id day), day) | day <- rosterDays ]
            let visibleSlotNameIds = Set.fromList (map (.slotNameId) visibleSlots)
            let assignedShiftCountByStaffId = Map.fromListWith (+) [ (staffId, 1 :: Int) | slot <- visibleSlots, staffId <- maybeToList slot.staffId ]
            let assignedDayCountByStaffId = Map.fromListWith (+) [ ((slot.rosterDayId, staffId), 1 :: Int) | slot <- visibleSlots, staffId <- maybeToList slot.staffId ]
            let approvedLeaveByStaffAndDay =
                    Set.fromList
                        [ (leaveRequest.staffId, dayDate)
                        | leaveRequest <- leaveRequests
                        , parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
                        , rosterDay <- rosterDays
                        , let dayDate = Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
                        , dayDate >= leaveRequest.startDate
                        , dayDate < leaveRequest.endDate
                        ]
            let preferredVisibleDays =
                    Set.fromList
                        [ (preference.staffId, preference.weekdayIndex)
                        | preference <- shiftPreferences
                        , preference.slotNameId `Set.member` visibleSlotNameIds
                        ]
            pure $
                Map.fromList
                    [ ((coerce (get #id slot), coerce (get #id staff)), rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById assignedShiftCountByStaffId assignedDayCountByStaffId approvedLeaveByStaffAndDay preferredVisibleDays slot staff)
                    | slot <- visibleSlots
                    , staff <- staffMembers
                    ]

rosterAssignmentOptionStateFor :: RosterAssignmentFilters -> Calendar.Day -> Map.Map UUID.UUID RosterDay -> Map.Map UUID.UUID Int -> Map.Map (UUID.UUID, UUID.UUID) Int -> Set.Set (UUID.UUID, Calendar.Day) -> Set.Set (UUID.UUID, Int) -> RosterSlot -> Staff -> RosterAssignmentOptionState
rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById assignedShiftCountByStaffId assignedDayCountByStaffId approvedLeaveByStaffAndDay preferredVisibleDays slot staff =
    let staffId = coerce (get #id staff)
        rosterDayDate =
            case Map.lookup slot.rosterDayId dayById of
                Just rosterDay -> Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
                Nothing -> weekStartDate
        assignedShiftCount = Map.findWithDefault 0 staffId assignedShiftCountByStaffId
        assignedTodayCount = Map.findWithDefault 0 (slot.rosterDayId, staffId) assignedDayCountByStaffId
        currentSlotContribution = if slot.staffId == Just staffId then 1 else 0
        assignedToday = assignedTodayCount > currentSlotContribution
        unavailable = hasNoPreferredShiftsOnDay staffId preferredVisibleDays rosterDayDate
        onApprovedLeave = Set.member (staffId, rosterDayDate) approvedLeaveByStaffAndDay
        hiddenByIdeal = assignmentFilters.hideStaffAtIdealShifts && assignedShiftCount >= staff.idealShiftsPerWeek
        hiddenByUnavailable = assignmentFilters.hideStaffUnavailable && unavailable
        hiddenByLeave = assignmentFilters.hideStaffOnApprovedLeave && onApprovedLeave
        hiddenByAssignedToday = assignmentFilters.hideStaffAlreadyAssignedToday && assignedToday
    in RosterAssignmentOptionState
        { optionHidden = hiddenByIdeal || hiddenByUnavailable || hiddenByLeave || hiddenByAssignedToday
        , optionAssignedShiftCount = assignedShiftCount
        , optionHiddenByIdeal = hiddenByIdeal
        , optionHiddenByUnavailable = hiddenByUnavailable
        , optionHiddenByLeave = hiddenByLeave
        , optionHiddenByAssignedToday = hiddenByAssignedToday
        }

isApprovedLeaveOn :: Calendar.Day -> UUID.UUID -> LeaveRequest -> Bool
isApprovedLeaveOn rosterDayDate staffId leaveRequest =
    leaveRequest.staffId == staffId
        && parseLeaveRequestStatus leaveRequest.status == Just LeaveApproved
        && rosterDayDate >= leaveRequest.startDate
        && rosterDayDate < leaveRequest.endDate

hasNoPreferredShiftsOnDay :: UUID.UUID -> Set.Set (UUID.UUID, Int) -> Calendar.Day -> Bool
hasNoPreferredShiftsOnDay staffId preferredVisibleDays rosterDayDate =
    not (Set.member (staffId, weekdayIndexForDay rosterDayDate) preferredVisibleDays)
