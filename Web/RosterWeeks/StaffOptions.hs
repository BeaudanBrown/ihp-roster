module Web.RosterWeeks.StaffOptions
    ( buildRosterStaffOptionStates
    , fetchAssignedRosterWeekStaff
    , fetchRosterStaffPanelEntries
    , fetchRosterStaffPanelEntriesForScope
    , hasNoPreferredShiftsOnDay
    , isApprovedLeaveOn
    , rosterAssignmentOptionStateFor
    ) where

import Application.Helper.Controller (LeaveRequestStatus (..),
                                      parseLeaveRequestStatus, venueRoleToText)
import Application.Helper.Staff (isTrialStaff)
import Application.Helper.View (rosterableStaffForRosterPanel)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.PayAssignment (StaffPayAssignment (..),
                                  staffPayAssignmentRequiresRemediation)
import Data.Coerce (coerce)
import Data.List (find, nub, sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.RosterWeeks.AvailabilityInputs (fetchApprovedLeaveRequestsForRosterWindow,
                                           fetchRosterShiftPreferencesForWindow)
import Web.RosterWeeks.Types

fetchRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Staff] -> [RosterSlot] -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntries =
    fetchRosterStaffPanelEntriesForScope RosterStaffPanelCurrentGroup

fetchRosterStaffPanelEntriesForScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterStaffPanelScope -> [Staff] -> [RosterSlot] -> IO [RosterStaffPanelEntry]
fetchRosterStaffPanelEntriesForScope panelScope staffMembers allSlots = do
    let panelStaff = staffForPanelScope panelScope staffMembers
    let linkedUserIds = mapMaybe (.userId) panelStaff

    memberships <-
        if null linkedUserIds
            then pure []
            else query @VenueMembership
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#userId, linkedUserIds)
                |> filterWhere (#isActive, True)
                |> fetch

    activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
    activeImportedPayItems <- query @XeroImportedPayItem |> filterWhere (#venueId, unpackId currentVenueId) |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime) |> fetch
    let membershipsByUserId = Map.fromList [ (membership.userId, membership) | membership <- memberships ]
    let assignedShiftCountByStaffId = Map.fromListWith (+) [ (staffId, 1 :: Int) | slot <- allSlots, staffId <- maybeToList slot.staffId ]
    let activeAwardLevelIds = map (.id) activeAwardLevels
    let activeImportedPayItemIds = map (.id) activeImportedPayItems
    pure (map (buildPanelEntry activeAwardLevelIds activeImportedPayItemIds membershipsByUserId assignedShiftCountByStaffId) panelStaff)
    where
        buildPanelEntry activeAwardLevelIds activeImportedPayItemIds membershipsByUserId assignedShiftCountByStaffId staff =
            let staffId = coerce (get #id staff)
                assignedShiftCount = Map.findWithDefault 0 staffId assignedShiftCountByStaffId
                roleText = if isTrialStaff staff
                    then "trial"
                    else case staff.userId >>= (`Map.lookup` membershipsByUserId) of
                        Just membership -> inputValue membership.venueRole
                        Nothing         -> venueRoleToText WorkerRole
             in RosterStaffPanelEntry
                    { staff
                    , assignedShiftCount
                    , userRole = roleText
                    , staffPayConfigurationRequired = staffPayAssignmentRequiresRemediation activeAwardLevelIds activeImportedPayItemIds (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)
                    }

staffForPanelScope :: RosterStaffPanelScope -> [Staff] -> [Staff]
staffForPanelScope RosterStaffPanelCurrentGroup = rosterableStaffForRosterPanel
staffForPanelScope RosterStaffPanelAllVenue =
    sortBy sortStaff
        . filter (\staff -> staff.isActive && isNothing staff.archivedAt)
    where
        sortStaff left right =
            compare left.firstName right.firstName <> compare left.lastName right.lastName

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

buildRosterStaffOptionStates :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterAssignmentFilters -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> IO (Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState)
buildRosterStaffOptionStates _rosterGroupId assignmentFilters weekStartDate rosterDays visibleSlots staffMembers = do
    let staffIds = map (coerce . (.id)) staffMembers
    if null staffIds
        then pure Map.empty
        else do
            let weekEndExclusive = Calendar.addDays 7 weekStartDate
            let visibleWeekdayIndexes =
                    Set.toList $
                        Set.fromList
                            [ weekdayIndexForDay (Calendar.addDays (toInteger rosterDay.dayOffset) weekStartDate)
                            | rosterDay <- rosterDays
                            ]
            leaveRequests <- fetchApprovedLeaveRequestsForRosterWindow staffIds weekStartDate weekEndExclusive
            shiftPreferences <- fetchRosterShiftPreferencesForWindow staffIds visibleWeekdayIndexes

            let dayById = Map.fromList [ (coerce (get #id day), day) | day <- rosterDays ]
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
