{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.ShiftWorkflow
    ( RosterShiftDialogSubmission (..)
    , ValidatedRosterShift (..)
    , applyValidatedRosterShift
    , defaultRosterShiftDialogValuesForVenue
    , fetchCurrentVenueRosterShiftTypesForDialog
    , fetchRosterSlotCreateContext
    , fetchRosterSlotDefinitionForCreate
    , fetchRosterSlotEditContext
    , fetchRosterSlotForEdit
    , rosterShiftDialogForCreateHtml
    , rosterShiftDialogForEditHtml
    , validateRosterShiftDialogSubmission
    ) where

import Application.Helper.Controller
import Application.Helper.RosterGroups (staffIsEligibleForRosterGroup)
import Application.Helper.TimeRules (defaultShiftTimesForVenueConfig,
                                     isValidRosterShiftTimePair,
                                     rosterShiftStartDate,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Application.VenueTime (RepeatedTimeOccurrence (..), VenueTimeError (..))
import Application.VenueTime.Model
import Data.Coerce (coerce)
import Data.Either (fromRight)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust)
import qualified Data.Set as Set
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Service (fetchActiveStaffForCurrentVenue)
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates,
                                     fetchRosterShiftDialogStaff)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.ShiftDialog

data RosterShiftDialogSubmission = RosterShiftDialogSubmission
    { submittedRosterShiftStaffId         :: !(Maybe Text)
    , submittedRosterShiftStartTime       :: !(Maybe Text)
    , submittedRosterShiftEndTime         :: !(Maybe Text)
    , submittedRosterShiftTypeId          :: !(Maybe Text)
    , submittedRosterShiftStartOccurrence :: !Text
    , submittedRosterShiftEndOccurrence   :: !Text
    }

data ValidatedRosterShift = ValidatedRosterShift
    { validRosterShiftStaffId    :: !UUID.UUID
    , validRosterShiftBoundaries :: !AuthoritativeBoundaries
    , validRosterShiftTypeId     :: !UUID.UUID
    }

fetchRosterSlotCreateContext :: (?modelContext :: ModelContext) => Id RosterDay -> IO (RosterDay, RosterWeek)
fetchRosterSlotCreateContext rosterDayId = do
    rosterDay <- fetch rosterDayId
    let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
    rosterWeek <- fetch rosterWeekId
    pure (rosterDay, rosterWeek)

fetchRosterSlotDefinitionForCreate :: (?modelContext :: ModelContext) => Id RosterWeekSlotDefinition -> IO RosterWeekSlotDefinition
fetchRosterSlotDefinitionForCreate = fetch

fetchRosterSlotForEdit :: (?modelContext :: ModelContext) => Id RosterSlot -> IO RosterSlot
fetchRosterSlotForEdit = fetch

fetchRosterSlotEditContext :: (?modelContext :: ModelContext) => RosterSlot -> IO (RosterDay, RosterWeek)
fetchRosterSlotEditContext rosterSlot = do
    let rosterDayId = (coerce rosterSlot.rosterDayId :: Id RosterDay)
    rosterDay <- fetch rosterDayId
    let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
    rosterWeek <- fetch rosterWeekId
    pure (rosterDay, rosterWeek)

rosterShiftDialogForCreateHtml :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO Blaze.Html
rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values = do
    (staffMembers, payInvalidStaffIds) <- fetchRosterShiftDialogStaff (coerce rosterWeek.rosterGroupId) Nothing
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    let targetSlot =
            newRecord @RosterSlot
                |> set #rosterDayId (unpackId rosterDay.id)
                |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                |> set #slotSortOrder slotDefinition.sortOrder
                |> set #rowIndex rowIndex
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek targetSlot staffMembers
    pure $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = NewRosterShiftDialog rosterDay.id slotDefinition.id rowIndex
        , rosterShiftDialogTitle = "Add shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogPayInvalidStaffIds = payInvalidStaffIds
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogValues = values
        }

rosterShiftDialogForEditHtml :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterSlot -> RosterWeek -> RosterShiftDialogValues -> IO Blaze.Html
rosterShiftDialogForEditHtml rosterSlot rosterWeek values = do
    (staffMembers, payInvalidStaffIds) <- fetchRosterShiftDialogStaff (coerce rosterWeek.rosterGroupId) rosterSlot.staffId
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates (coerce rosterWeek.rosterGroupId) rosterWeek rosterSlot staffMembers
    pure $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = EditRosterShiftDialog rosterSlot.id
        , rosterShiftDialogTitle = "Edit shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogPayInvalidStaffIds = payInvalidStaffIds
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogValues = values
        }

defaultRosterShiftDialogValuesForVenue :: VenueConfig -> RosterShiftDialogValues
defaultRosterShiftDialogValuesForVenue venueConfig =
    let (defaultStart, defaultEnd) = defaultShiftTimesForVenueConfig venueConfig
     in emptyRosterShiftDialogValues
            { rosterShiftStartTime = timeOfDayToStorageValue defaultStart
            , rosterShiftEndTime = timeOfDayToStorageValue defaultEnd
            }

buildRosterShiftDialogStaffOptionStates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterSlot -> [Staff] -> IO (Map.Map UUID.UUID RosterAssignmentOptionState)
buildRosterShiftDialogStaffOptionStates rosterGroupId rosterWeek targetSlot staffMembers = do
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
    let weekStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
        |> fetch
    visibleSlots <-
        if null rosterDays
            then pure []
            else query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
    let targetSlotId = coerce targetSlot.id
    let slotsForOptions = targetSlot : filter (\slot -> coerce slot.id /= targetSlotId) visibleSlots
    optionStates <- buildRosterStaffOptionStates rosterGroupId assignmentFilters weekStartDate rosterDays slotsForOptions staffMembers
    pure $ Map.fromList
        [ (coerce staff.id, optionState)
        | staff <- staffMembers
        , Just optionState <- [Map.lookup (targetSlotId, coerce staff.id) optionStates]
        ]

fetchCurrentVenueRosterShiftTypesForDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesForDialog =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

validateRosterShiftDialogSubmission :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterDay -> RosterWeek -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues ValidatedRosterShift)
validateRosterShiftDialogSubmission rosterGroupId rosterDay rosterWeek submission = do
    venueConfig <- fetchVenueConfig
    let rosterDate = Calendar.addDays (toInteger rosterDay.dayOffset) (venueWeekStartDate venueConfig rosterWeek.weekOffset)
    let staffParam = submission.submittedRosterShiftStaffId
    let startParam = submission.submittedRosterShiftStartTime
    let endParam = submission.submittedRosterShiftEndTime
    let shiftTypeParam = submission.submittedRosterShiftTypeId
    let parsedStaffId = parseOptionalStaffId staffParam
    let parsedStartTime = parseOptionalTime startParam
    let parsedEndTime = parseOptionalTime endParam
    let parsedShiftTypeId = parseOptionalShiftTypeId shiftTypeParam
    let shiftDate = maybe rosterDate (rosterShiftStartDate rosterDate) parsedStartTime
    let parsedStartOccurrence = parseOccurrenceParam submission.submittedRosterShiftStartOccurrence
    let parsedEndOccurrence = parseOccurrenceParam submission.submittedRosterShiftEndOccurrence
    maybeStaff <- maybe (pure Nothing) (fetchActiveStaffForCurrentVenue . Id) parsedStaffId
    let staffInVenue = isJust maybeStaff
    staffEligible <- maybe (pure False) (\staffId -> staffIsEligibleForRosterGroup (Id staffId) rosterGroupId) parsedStaffId
    shiftTypeInVenue <- maybe (pure False) shiftTypeIdIsInCurrentVenue parsedShiftTypeId
    let startIsRepeated = maybe False (civilBoundaryIsRepeated shiftDate) parsedStartTime
    let repeatedPairCanShareDate = case (parsedStartTime, parsedEndTime) of
            (Just startTime, Just endTime) -> repeatedEndpointPairCanShareDate shiftDate startTime endTime
            _ -> False
    let endDate = case (parsedStartTime, parsedEndTime) of
            (Just startTime, Just endTime) -> Calendar.addDays (if endTime <= startTime && not repeatedPairCanShareDate then 1 else 0) shiftDate
            _ -> shiftDate
    let endIsRepeated = maybe False (civilBoundaryIsRepeated endDate) parsedEndTime
    let startOccurrence = fromRight Nothing parsedStartOccurrence
    let endOccurrence = fromRight Nothing parsedEndOccurrence
    let baseValues = emptyRosterShiftDialogValues
            { rosterShiftStaffId = parsedStaffId
            , rosterShiftStartTime = fromMaybe "" (normalizeOptionalText startParam)
            , rosterShiftEndTime = fromMaybe "" (normalizeOptionalText endParam)
            , rosterShiftTypeId = parsedShiftTypeId
            , rosterShiftStartOccurrence = startOccurrence
            , rosterShiftEndOccurrence = endOccurrence
            , rosterShiftStartIsRepeated = startIsRepeated
            , rosterShiftEndIsRepeated = endIsRepeated
            }
    let staffError
            | isNothing (normalizeOptionalText staffParam) = Just "Choose a staff member."
            | isNothing parsedStaffId || not staffInVenue = Just "Choose a staff member for this venue."
            | not staffEligible = Just "That staff member is not applicable to this roster group."
            | otherwise = Nothing
    let startError
            | isNothing (normalizeOptionalText startParam) = Just "Choose a start time."
            | isNothing parsedStartTime = Just "Choose a valid start time."
            | Left message <- parsedStartOccurrence = Just message
            | startIsRepeated && isNothing startOccurrence = Just "Choose whether this is the first or second occurrence."
            | otherwise = Nothing
    let endError
            | isNothing (normalizeOptionalText endParam) = Just "Choose an end time."
            | isNothing parsedEndTime = Just "Choose a valid end time."
            | Left message <- parsedEndOccurrence = Just message
            | endIsRepeated && isNothing endOccurrence = Just "Choose whether this is the first or second occurrence."
            | otherwise = Nothing
    let shiftTypeError
            | isNothing (normalizeOptionalText shiftTypeParam) = Just "Choose a shift type."
            | isNothing parsedShiftTypeId || not shiftTypeInVenue = Just "Choose a shift type for this venue."
            | otherwise = Nothing
    let timingError =
            case (parsedStartTime, parsedEndTime) of
                (Just startTime, Just endTime)
                    | not repeatedPairCanShareDate && not (isValidRosterShiftTimePair startTime endTime) -> Just invalidRosterSlotTimingMessage
                _ -> Nothing
    let maybeResolvedBoundaries = do
            startTime <- parsedStartTime
            endTime <- parsedEndTime
            let input = ShiftBoundaryInput
                    { shiftBoundaryDate = shiftDate
                    , shiftBoundaryStartTime = startTime
                    , shiftBoundaryStartOccurrence = if startIsRepeated && isNothing startOccurrence then Just FirstOccurrence else startOccurrence
                    , shiftBoundaryEndTime = endTime
                    , shiftBoundaryEndOccurrence =
                        if endIsRepeated && isNothing endOccurrence
                            then Just (if repeatedPairCanShareDate then SecondOccurrence else FirstOccurrence)
                            else endOccurrence
                    , shiftBoundaryBreak = Nothing
                    }
            pure (resolveShiftBoundaries venueConfig.timezone input)
    let resolutionError = either (Just . rosterBoundaryErrorMessage) (const Nothing) =<< maybeResolvedBoundaries
    let valuesWithErrors = baseValues
            { rosterShiftFormError = timingError <|> resolutionError
            , rosterShiftStaffError = staffError
            , rosterShiftStartError = startError <|> boundaryStartError maybeResolvedBoundaries
            , rosterShiftEndError = endError <|> timingError <|> boundaryEndError maybeResolvedBoundaries
            , rosterShiftTypeError = shiftTypeError
            }
    case (staffError, startError, endError, shiftTypeError, timingError, resolutionError, parsedStaffId, parsedShiftTypeId, maybeResolvedBoundaries) of
        (Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Just staffId, Just shiftTypeId, Just (Right boundaries)) ->
            pure (Right ValidatedRosterShift
                { validRosterShiftStaffId = staffId
                , validRosterShiftBoundaries = boundaries
                , validRosterShiftTypeId = shiftTypeId
                })
        _ -> pure (Left valuesWithErrors)
  where
    boundaryStartError (Just (Left (BoundaryCivilTimeError (NonexistentCivilTime _)))) = Just "This local time does not exist because clocks move forward."
    boundaryStartError (Just (Left (BoundaryCivilTimeError (RepeatedTimeOccurrenceNotApplicable _ _)))) = Just "First/second occurrence applies only while clocks repeat."
    boundaryStartError _ = Nothing

    boundaryEndError (Just (Left (BoundaryCivilTimeError (NonPositiveResolvedInterval _ _)))) = Just "Shift end must be after shift start."
    boundaryEndError _ = Nothing

    rosterBoundaryErrorMessage (BoundaryUnsupportedTimezone _) = "This venue timezone is not supported for roster shifts."
    rosterBoundaryErrorMessage (BoundaryCivilTimeError (NonexistentCivilTime _)) = "A selected local time does not exist because clocks move forward."
    rosterBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedTimeOccurrenceNotApplicable _ _)) = "An occurrence choice was supplied for a time that does not repeat."
    rosterBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)) = "Choose whether the repeated time is its first or second occurrence."
    rosterBoundaryErrorMessage (BoundaryCivilTimeError (InvalidCivilTimeOfDay _)) = "Choose valid roster times."
    rosterBoundaryErrorMessage (BoundaryCivilTimeError (NonPositiveResolvedInterval _ _)) = "Shift end must be after shift start."
    rosterBoundaryErrorMessage BoundaryBreakNotContained = "Break boundaries are not valid for this roster shift."
    rosterBoundaryErrorMessage BoundaryBreakShapeInvalid = "Break boundaries are incomplete."

shiftTypeIdIsInCurrentVenue :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO Bool
shiftTypeIdIsInCurrentVenue shiftTypeId =
    query @ShiftType
        |> filterWhere (#id, Id shiftTypeId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetchExists

applyValidatedRosterShift :: ValidatedRosterShift -> RosterSlot -> RosterSlot
applyValidatedRosterShift valid slot =
    slot
        |> set #staffId (Just valid.validRosterShiftStaffId)
        |> set #shiftTypeId (Just valid.validRosterShiftTypeId)
        |> applyRosterSlotBoundaries valid.validRosterShiftBoundaries
