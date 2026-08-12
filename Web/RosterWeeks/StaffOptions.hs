module Web.RosterWeeks.StaffOptions
    ( buildRosterStaffOptionStates
    , fetchAssignedRosterWeekStaff
    , fetchRosterStaffPanelEntries
    , fetchRosterShiftDialogStaff
    , fetchRosterStaffPanelEntriesForScope
    , fetchStaffPayConfigurationRequiredIds
    , hasNoPreferredShiftsOnDay
    , rosterAssignmentOptionStateFor
    , rosterAssignmentOptionStatesFor
    ) where

import Application.Helper.Controller (venueRoleToText)
import Application.Helper.RosterGroups (fetchEligibleRosterGroupStaff)
import Application.Helper.Staff (isTrialStaff, sortStaffForDisplay)
import Application.Helper.View (rosterableStaffForRosterPanel)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Application.PayAssignment (StaffPayAssignment (..),
                                  staffPayAssignmentRequiresRemediation)
import Application.RosterShiftAssignment (rosterShiftIsStaffAssigned)
import Data.Coerce (coerce)
import Data.List (find, nub)
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

    payConfigurationRequiredIds <- fetchStaffPayConfigurationRequiredIds panelStaff
    let membershipsByUserId = Map.fromList [ (membership.userId, membership) | membership <- memberships ]
    let assignedShiftCountByStaffId = Map.fromListWith (+) [ (staffId, 1 :: Int) | slot <- filter rosterShiftIsStaffAssigned allSlots, staffId <- maybeToList slot.staffId ]
    pure (map (buildPanelEntry payConfigurationRequiredIds membershipsByUserId assignedShiftCountByStaffId) panelStaff)
    where
        buildPanelEntry payConfigurationRequiredIds membershipsByUserId assignedShiftCountByStaffId staff =
            let staffId = coerce (get #id staff)
                assignedShiftCount = Map.findWithDefault 0 staffId assignedShiftCountByStaffId
                roleText = if isTrialStaff staff
                    then "trial"
                    else case staff.userId >>= (`Map.lookup` membershipsByUserId) of
                        Just membership -> inputValue membership.venueRole
                        Nothing         -> venueRoleToText Worker
             in RosterStaffPanelEntry
                    { staff
                    , assignedShiftCount
                    , userRole = roleText
                    , staffPayConfigurationRequired = staffId `Set.member` payConfigurationRequiredIds
                    }

fetchRosterShiftDialogStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Maybe UUID.UUID -> IO ([Staff], Set.Set UUID.UUID)
fetchRosterShiftDialogStaff rosterGroupId currentStaffId = do
    groupStaff <- fetchEligibleRosterGroupStaff rosterGroupId
    maybeCurrentStaff <- case currentStaffId of
        Nothing -> pure Nothing
        Just staffId ->
            query @Staff
                |> filterWhere (#id, Id staffId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> fetchOneOrNothing
    let dialogStaff = groupStaff <> [staff | staff <- maybeToList maybeCurrentStaff, all ((/= staff.id) . (.id)) groupStaff]
    payInvalidStaffIds <- fetchStaffPayConfigurationRequiredIds dialogStaff
    let validStaff = filter (not . (`Set.member` payInvalidStaffIds) . coerce . (.id)) dialogStaff
    let currentInvalidStaff =
            [ staff
            | staff <- dialogStaff
            , coerce staff.id `Set.member` payInvalidStaffIds
            , Just (coerce staff.id) == currentStaffId
            ]
    pure (sortStaffForDisplay (validStaff <> currentInvalidStaff), Set.fromList (map (coerce . (.id)) currentInvalidStaff))

fetchStaffPayConfigurationRequiredIds :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Staff] -> IO (Set.Set UUID.UUID)
fetchStaffPayConfigurationRequiredIds staffMembers = do
    activeAwardLevels <- query @AwardLevel |> filterWhere (#isActive, True) |> fetch
    activeImportedPayItems <- query @XeroImportedPayItem |> filterWhere (#venueId, unpackId currentVenueId) |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime) |> filterWhere (#providerAvailable, True) |> fetch
    let activeAwardLevelIds = map (.id) activeAwardLevels
    let activeImportedPayItemIds = map (.id) activeImportedPayItems
    pure $ Set.fromList
        [ coerce staff.id
        | staff <- staffMembers
        , staffPayAssignmentRequiresRemediation activeAwardLevelIds activeImportedPayItemIds
            (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)
        ]

staffForPanelScope :: RosterStaffPanelScope -> [Staff] -> [Staff]
staffForPanelScope RosterStaffPanelCurrentGroup = rosterableStaffForRosterPanel
staffForPanelScope RosterStaffPanelAllVenue =
    sortStaffForDisplay
        . filter (\staff -> staff.isActive && isNothing staff.archivedAt)

fetchAssignedRosterWeekStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [RosterSlot] -> IO [Staff]
fetchAssignedRosterWeekStaff allSlots = do
    let assignedStaffIds = nub (mapMaybe (.staffId) (filter rosterShiftIsStaffAssigned allSlots))
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

            let approvedLeaveByStaffAndDay =
                    Set.fromList
                        [ (leaveRequest.staffId, dayDate)
                        | leaveRequest <- leaveRequests
                        , leaveRequest.status == LeaveRequestStatusEnumApproved
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
            pure (rosterAssignmentOptionStatesFor assignmentFilters weekStartDate rosterDays visibleSlots staffMembers approvedLeaveByStaffAndDay preferredVisibleDays)

rosterAssignmentOptionStatesFor :: RosterAssignmentFilters -> Calendar.Day -> [RosterDay] -> [RosterSlot] -> [Staff] -> Set.Set (UUID.UUID, Calendar.Day) -> Set.Set (UUID.UUID, Int) -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState
rosterAssignmentOptionStatesFor assignmentFilters weekStartDate rosterDays visibleSlots staffMembers approvedLeaveByStaffAndDay preferredVisibleDays =
    Map.fromList
        [ ((coerce slot.id, coerce staff.id), rosterAssignmentOptionStateFor assignmentFilters weekStartDate dayById assignedShiftCountByStaffId assignedDayCountByStaffId approvedLeaveByStaffAndDay preferredVisibleDays slot staff)
        | slot <- visibleSlots
        , staff <- staffMembers
        ]
  where
    dayById = Map.fromList [(coerce day.id, day) | day <- rosterDays]
    staffAssignedSlots = filter rosterShiftIsStaffAssigned visibleSlots
    assignedShiftCountByStaffId = Map.fromListWith (+) [(staffId, 1 :: Int) | slot <- staffAssignedSlots, staffId <- maybeToList slot.staffId]
    assignedDayCountByStaffId = Map.fromListWith (+) [((slot.rosterDayId, staffId), 1 :: Int) | slot <- staffAssignedSlots, staffId <- maybeToList slot.staffId]

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


hasNoPreferredShiftsOnDay :: UUID.UUID -> Set.Set (UUID.UUID, Int) -> Calendar.Day -> Bool
hasNoPreferredShiftsOnDay staffId preferredVisibleDays rosterDayDate =
    not (Set.member (staffId, weekdayIndexForDay rosterDayDate) preferredVisibleDays)
