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

    pure (map (buildPanelEntry memberships) linkedStaff)
    where
        buildPanelEntry memberships staff =
            let assignedShiftCount = length (filter (\slot -> slot.staffId == Just (coerce (get #id staff))) allSlots)
                roleText = case staff.userId >>= \userId -> find (\membership -> membership.userId == userId) memberships of
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

            let dayById = Map.fromList (map (\day -> (coerce (get #id day), day)) rosterDays)
            pure $
                Map.fromList
                    [ ((coerce (get #id slot), coerce (get #id staff)), rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById visibleSlots leaveRequests shiftPreferences slot staff)
                    | slot <- visibleSlots
                    , staff <- staffMembers
                    ]

rosterAssignmentOptionStateFor :: RosterAssignmentFilters -> Calendar.Day -> Map.Map UUID.UUID RosterDay -> [RosterSlot] -> [LeaveRequest] -> [StaffShiftPreference] -> RosterSlot -> Staff -> RosterAssignmentOptionState
rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById visibleSlots leaveRequests shiftPreferences slot staff =
    let staffId = coerce (get #id staff)
        visibleSlotNameIds = nub (map (.slotNameId) visibleSlots)
        rosterDayDate =
            case Map.lookup slot.rosterDayId dayById of
                Just rosterDay -> Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate
                Nothing -> weekStartDate
        assignedShiftCount = length (filter (\candidate -> candidate.staffId == Just staffId) visibleSlots)
        assignedToday = any (\candidate -> candidate.rosterDayId == slot.rosterDayId && candidate.staffId == Just staffId && get #id candidate /= get #id slot) visibleSlots
        unavailable = hasNoPreferredShiftsOnDay staffId visibleSlotNameIds rosterDayDate shiftPreferences
        onApprovedLeave = any (isApprovedLeaveOn rosterDayDate staffId) leaveRequests
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

hasNoPreferredShiftsOnDay :: UUID.UUID -> [UUID.UUID] -> Calendar.Day -> [StaffShiftPreference] -> Bool
hasNoPreferredShiftsOnDay staffId visibleSlotNameIds rosterDayDate shiftPreferences =
    null
        [ preference
        | preference <- shiftPreferences
        , preference.staffId == staffId
        , preference.slotNameId `elem` visibleSlotNameIds
        , preference.weekdayIndex == weekdayIndexForDay rosterDayDate
        ]
