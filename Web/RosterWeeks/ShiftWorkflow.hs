{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.ShiftWorkflow
    ( RosterShiftDialogSubmission (..)
    , RosterShiftEditCompletion (..)
    , RosterStaffAssignmentCompletion (..)
    , assignRosterShiftStaff
    , duplicateRosterTimelineShift
    , ValidatedRosterShift (..)
    , createRosterShift
    , editRosterShift
    , applyValidatedRosterShift
    , defaultRosterShiftDialogValuesForVenue
    , rosterTimelineCreateDialogValues
    , fetchCurrentVenueRosterShiftTypesForDialog
    , fetchRosterSlotDefinitionForDialog
    , fetchRosterSlotEditContext
    , fetchRosterSlotForEdit
    , rosterShiftDialogForCreateHtml
    , rosterShiftDialogForEditHtml
    , validateRosterShiftDialogSubmission
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Controller
import Application.Helper.RosterGroups (staffIsEligibleForRosterGroup)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.VenueScopedQueries (fetchVenueShiftTypes)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment,
                                          copyRosterShiftAssignment)
import Application.VenueTime (RepeatedTimeOccurrence (..), VenueTimeError (..),
                              resolvedInstantFromUTC, resolvedInstantLocalTime,
                              resolvedInstantOccurrence)
import Application.VenueTime.Model
import Data.Coerce (coerce)
import Data.Either (fromRight)
import qualified Data.Map.Strict as Map
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified IHP.HSX.Markup as Markup
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.RosterWeeks.DateRange (RosterWindow (..), RosterWindowDay (..),
                                  RosterWindowScope (..), fetchRosterWindow,
                                  rosterWindowTarget)
import Web.RosterWeeks.DropWorkflow (MoveRosterTimelineShiftIntent (..),
                                     RosterTimelineDropBoundaryResolution (..),
                                     resolveRosterTimelineDropBoundaries)
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Mutations (RosterSlotMutationResult (..),
                                  duplicateRosterSlotMutation,
                                  saveRosterSlotMutation,
                                  updateRosterSlotMutation)
import Web.RosterWeeks.RenderData (currentRosterGridViewMode,
                                   currentRosterTimelineDate)
import Web.RosterWeeks.Rows (impactedRowKeysForSlotUpdate)
import Web.RosterWeeks.Service (fetchActiveStaffForCurrentVenue)
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates,
                                     fetchRosterShiftDialogStaff)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.ShiftDialog

duplicateRosterTimelineShift :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> MoveRosterTimelineShiftIntent -> IO (Either Text (LiveMutationResult RosterSlotMutationResult))
duplicateRosterTimelineShift scope intent =
    case resolveRosterTimelineDropBoundaries intent of
        RosterTimelineDropInvalid message -> pure (Left message)
        RosterTimelineDropBoundaryReady boundaries ->
            case copyRosterShiftAssignment intent.timelineSourceSlot (newRecord @RosterSlot) of
                Left message -> pure (Left message)
                Right assigned -> do
                    let copied = assigned
                            |> set #rosterDayId (unpackId intent.timelineTargetRosterDay.id)
                            |> set #rosterLaneId (unpackId intent.timelineTargetSlotDefinition.id)
                            |> set #slotSortOrder intent.timelineTargetSlotDefinition.sortOrder
                            |> set #rowIndex intent.timelineTargetRowIndex
                            |> set #shiftTypeId intent.timelineSourceSlot.shiftTypeId
                            |> applyRosterSlotBoundaries boundaries
                    duplicateRosterSlotMutation scope intent.timelineTargetRosterDay intent.timelineSourceSlot copied

data RosterShiftDialogSubmission = RosterShiftDialogSubmission
    { submittedRosterShiftStaffId         :: !(Maybe Text)
    , submittedRosterShiftStartTime       :: !(Maybe Text)
    , submittedRosterShiftEndTime         :: !(Maybe Text)
    , submittedRosterShiftTypeId          :: !(Maybe Text)
    , submittedRosterShiftStartOccurrence :: !Text
    , submittedRosterShiftEndOccurrence   :: !Text
    }

data ValidatedRosterShift = ValidatedRosterShift
    { validRosterShiftAssignment :: !RosterShiftAssignment
    , validRosterShiftBoundaries :: !AuthoritativeBoundaries
    , validRosterShiftTypeId     :: !UUID.UUID
    }

-- These operations run after the controller's ordered venue/calendar and
-- placement/access checks. Inputs are snapshots, not freshness guarantees:
-- Mutations retains its date/staff/slot locks and authoritative revalidation.
data RosterShiftEditCompletion = RosterShiftEditCompletion
    { rosterShiftEditMutation :: !(LiveMutationResult RosterSlotMutationResult)
    , rosterShiftEditImpactedRows :: ![(UUID.UUID, Int)]
    , rosterShiftEditWarnSourceTimesheetUnchanged :: !Bool
    }

data RosterStaffAssignmentCompletion = RosterStaffAssignmentCompletion
    { rosterStaffAssignmentMutation :: !(LiveMutationResult RosterSlotMutationResult)
    , rosterStaffAssignmentMaterializedWindow :: !Bool
    }

-- The drop validator has checked scope and assignment eligibility. Keep the
-- publication classification and complete slot update behind the workflow;
-- mutation locks still revalidate these snapshots before saving.
assignRosterShiftStaff :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> Staff -> IO (Either Text RosterStaffAssignmentCompletion)
assignRosterShiftStaff scope rosterDay rosterSlot staff = do
    window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
    let publishedFill = rosterDay.publicationState == Published
        materializeOnSave = not publishedFill && any (isNothing . (.persistedRosterDay)) window.rosterWindowProjectedDays
        updatedSlot = applyRosterShiftAssignment (StaffAssignment staff.id) rosterSlot
    mutation <- updateRosterSlotMutation scope rosterDay rosterSlot updatedSlot publishedFill materializeOnSave
    pure $ fmap (\result -> RosterStaffAssignmentCompletion
        { rosterStaffAssignmentMutation = result
        , rosterStaffAssignmentMaterializedWindow = materializeOnSave
        }) mutation

createRosterShift :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterLane -> Int -> Bool -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues (LiveMutationResult RosterSlotMutationResult))
createRosterShift scope rosterDay slotDefinition rowIndex materializedWindow submission = do
    existingSlot <- query @RosterSlot
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#rosterLaneId, unpackId slotDefinition.id)
        |> filterWhere (#rowIndex, rowIndex)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing
    let timelineCreation = isJust (currentRosterTimelineDate scope.rosterWindowStart)
    validation <- validateRosterShiftDialogSubmissionWithInterval (if timelineCreation then Just 5 else Nothing) scope.rosterWindowRosterGroupId rosterDay existingSlot submission
    case validation of
        Left values -> pure (Left values)
        Right valid -> do
            let newSlot =
                    fromMaybe
                        ( newRecord @RosterSlot
                        |> set #rosterDayId (unpackId rosterDay.id)
                        |> set #rosterLaneId (unpackId slotDefinition.id)
                        |> set #slotSortOrder slotDefinition.sortOrder
                        |> set #rowIndex rowIndex
                        )
                        existingSlot
                        |> applyValidatedRosterShift valid
            mutation <- saveRosterSlotMutation scope rosterDay existingSlot newSlot materializedWindow
            pure $ case mutation of
                Left message -> Left (rosterShiftDialogValuesFromSlot newSlot) { rosterShiftFormError = Just message }
                Right result -> Right result

editRosterShift :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterSlot -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues RosterShiftEditCompletion)
editRosterShift scope rosterDay rosterSlot submission = do
    -- Published fill restores the original values on persistence rejection;
    -- Draft edit restores the attempted values. Keep that distinction here.
    prepared <- if rosterDay.publicationState == Published
        then fmap (`applyRosterShiftAssignment` rosterSlot)
            <$> validateLiveOpenShiftFill scope.rosterWindowRosterGroupId rosterSlot submission
        else fmap (`applyValidatedRosterShift` rosterSlot)
            <$> validateRosterShiftDialogSubmission scope.rosterWindowRosterGroupId rosterDay (Just rosterSlot) submission
    case prepared of
        Left values -> pure (Left values)
        Right updatedSlot -> do
            let publishedFill = rosterDay.publicationState == Published
            mutation <- updateRosterSlotMutation scope rosterDay rosterSlot updatedSlot publishedFill False
            case mutation of
                Left message -> pure $ Left
                    (rosterShiftDialogValuesFromSlot (if publishedFill then rosterSlot else updatedSlot))
                        { rosterShiftFormError = Just message }
                Right result -> do
                    -- Impact reads deliberately happen after the mutation commits.
                    let previousStaffId = result.liveMutationValue.rosterSlotMutationPreviousStaffId
                    relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek scope (catMaybes [previousStaffId, updatedSlot.staffId])
                    pure $ Right RosterShiftEditCompletion
                        { rosterShiftEditMutation = result
                        , rosterShiftEditImpactedRows = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                        , rosterShiftEditWarnSourceTimesheetUnchanged = not publishedFill && result.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                        }

fetchRelatedSlotsForStaffIdsInRosterWeek :: (?modelContext :: ModelContext) => RosterWindowScope -> [UUID.UUID] -> IO [RosterSlot]
fetchRelatedSlotsForStaffIdsInRosterWeek scope staffIds =
    if null staffIds
        then pure []
        else do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterGroupId, unpackId scope.rosterWindowRosterGroupId)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, scope.rosterWindowStart)
                |> filterWhereLessThan (#operationalDate, scope.rosterWindowEnd)
                |> fetch
            if null rosterDays
                then pure []
                else query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> filterWhereIn (#staffId, map Just (nub staffIds))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

fetchRosterSlotDefinitionForDialog :: (?modelContext :: ModelContext, ?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterDay -> Id RosterLane -> IO RosterLane
fetchRosterSlotDefinitionForDialog scope rosterDay rosterLaneId = do
    window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
    let maybeTarget = rosterWindowTarget scope.rosterWindowVenueId scope.rosterWindowRosterGroupId window rosterDay.id
        maybeLane = maybeTarget >>= find ((== rosterLaneId) . (.id)) . snd
    accessDeniedUnless (isJust maybeLane)
    pure (fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized projected roster lane missing") maybeLane)

fetchRosterSlotForEdit :: (?modelContext :: ModelContext) => Id RosterSlot -> IO RosterSlot
fetchRosterSlotForEdit = fetch

fetchRosterSlotEditContext :: (?modelContext :: ModelContext) => RosterSlot -> IO RosterDay
fetchRosterSlotEditContext rosterSlot =
    fetch (coerce rosterSlot.rosterDayId :: Id RosterDay)

rosterShiftDialogForCreateHtml :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> RosterLane -> Int -> RosterShiftDialogValues -> IO Markup.Html
rosterShiftDialogForCreateHtml scope rosterDay slotDefinition rowIndex values = do
    (staffMembers, payInvalidStaffIds) <- fetchRosterShiftDialogStaff scope.rosterWindowRosterGroupId Nothing
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    let targetSlot =
            newRecord @RosterSlot
                |> set #rosterDayId (unpackId rosterDay.id)
                |> set #rosterLaneId (unpackId slotDefinition.id)
                |> set #slotSortOrder slotDefinition.sortOrder
                |> set #rowIndex rowIndex
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates scope.rosterWindowRosterGroupId rosterDay targetSlot staffMembers
    pure $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = NewRosterShiftDialog rosterDay.id slotDefinition.id scope.rosterWindowRosterGroupId rosterDay.operationalDate rowIndex
        , rosterShiftDialogTitle = "Add shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogPayInvalidStaffIds = payInvalidStaffIds
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogTimePickerStep = rosterDialogInterval venueConfig (if isJust (currentRosterTimelineDate scope.rosterWindowStart) then Just 5 else Nothing)
        , rosterShiftDialogValues = values
        , rosterShiftDialogAssignmentOnly = False
        , rosterShiftDialogTimelineOrientation = rosterTimelineOrientation (currentRosterGridViewMode scope.rosterWindowStart)
        , rosterShiftDialogTimelineDate = currentRosterTimelineDate scope.rosterWindowStart
        , rosterShiftDialogAnchorDate = startOfWeekFor venueConfig.rosterWeekStartsOn rosterDay.operationalDate
        , rosterShiftDialogCalendarRevision = venueConfig.rosterCalendarRevision
        }

rosterShiftDialogForEditHtml :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterSlot -> RosterDay -> RosterShiftDialogValues -> IO Markup.Html
rosterShiftDialogForEditHtml scope rosterSlot rosterDay values = do
    (staffMembers, payInvalidStaffIds) <- fetchRosterShiftDialogStaff scope.rosterWindowRosterGroupId rosterSlot.staffId
    shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
    venueConfig <- fetchVenueConfig
    staffOptionStates <- buildRosterShiftDialogStaffOptionStates scope.rosterWindowRosterGroupId rosterDay rosterSlot staffMembers
    pure $ renderRosterShiftDialog RosterShiftDialogData
        { rosterShiftDialogMode = EditRosterShiftDialog rosterSlot.id
        , rosterShiftDialogTitle = if rosterDay.publicationState == Published then "Fill Open shift" else "Edit shift"
        , rosterShiftDialogStaff = staffMembers
        , rosterShiftDialogStaffOptionStates = staffOptionStates
        , rosterShiftDialogPayInvalidStaffIds = payInvalidStaffIds
        , rosterShiftDialogShiftTypes = shiftTypes
        , rosterShiftDialogTimePickerStart = venueTimePickerStartTimeText venueConfig
        , rosterShiftDialogTimePickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        , rosterShiftDialogTimePickerStep = venueShiftTimeIntervalMinutes venueConfig
        , rosterShiftDialogValues = values
        , rosterShiftDialogAssignmentOnly = rosterDay.publicationState == Published
        , rosterShiftDialogTimelineOrientation = rosterTimelineOrientation (currentRosterGridViewMode scope.rosterWindowStart)
        , rosterShiftDialogTimelineDate = currentRosterTimelineDate scope.rosterWindowStart
        , rosterShiftDialogAnchorDate = startOfWeekFor venueConfig.rosterWeekStartsOn rosterDay.operationalDate
        , rosterShiftDialogCalendarRevision = venueConfig.rosterCalendarRevision
        }

rosterTimelineCreateDialogValues :: UTCTime -> RosterShiftDialogValues
rosterTimelineCreateDialogValues instant =
    let resolved = resolvedInstantFromUTC instant
        occurrence = resolvedInstantOccurrence resolved
     in emptyRosterShiftDialogValues
        { rosterShiftStartTime = timeOfDayToStorageValue (resolvedInstantLocalTime resolved).localTimeOfDay
        , rosterShiftStartOccurrence = occurrence
        , rosterShiftStartIsRepeated = isJust occurrence
        }

defaultRosterShiftDialogValuesForVenue :: VenueConfig -> RosterShiftDialogValues
defaultRosterShiftDialogValuesForVenue venueConfig =
    let (defaultStart, defaultEnd) = defaultShiftTimesForVenueConfig venueConfig
     in emptyRosterShiftDialogValues
            { rosterShiftStartTime = timeOfDayToStorageValue defaultStart
            , rosterShiftEndTime = timeOfDayToStorageValue defaultEnd
            }

buildRosterShiftDialogStaffOptionStates :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterDay -> RosterSlot -> [Staff] -> IO (Map.Map UUID.UUID RosterAssignmentOptionState)
buildRosterShiftDialogStaffOptionStates rosterGroupId targetDay targetSlot staffMembers = do
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
    let assignmentFiltersForDialog = assignmentFilters
            { hideStaffAlreadyAssignedToday = assignmentFilters.hideStaffAlreadyAssignedToday || paramOrDefault @Bool False "hideStaffAlreadyAssignedToday"
            }
    let weekStartDate = startOfWeekFor venueConfig.rosterWeekStartsOn targetDay.operationalDate
    rosterDays <- query @RosterDay
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, weekStartDate)
        |> filterWhereLessThanOrEqualTo (#operationalDate, Calendar.addDays 6 weekStartDate)
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
    let targetDayId = unpackId targetDay.id
    let rosterDaysForOptions = targetDay : filter (\day -> coerce day.id /= targetDayId) rosterDays
    optionStates <- buildRosterStaffOptionStates assignmentFiltersForDialog weekStartDate rosterDaysForOptions slotsForOptions staffMembers
    pure $ Map.fromList
        [ (coerce staff.id, optionState)
        | staff <- staffMembers
        , Just optionState <- [Map.lookup (targetSlotId, coerce staff.id) optionStates]
        ]

fetchCurrentVenueRosterShiftTypesForDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypesForDialog =
    fetchVenueShiftTypes currentVenueId

validateLiveOpenShiftFill :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterSlot -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues RosterShiftAssignment)
validateLiveOpenShiftFill rosterGroupId rosterSlot submission = do
    let parsedAssignment = parseSubmittedRosterShiftAssignment submission.submittedRosterShiftStaffId
    let parsedStaffId = case parsedAssignment of
            Just (StaffAssignment (Id staffId)) -> Just staffId
            _                                   -> Nothing
    maybeStaff <- maybe (pure Nothing) (fetchActiveStaffForCurrentVenue . Id) parsedStaffId
    staffEligible <- maybe (pure False) (\staffId -> staffIsEligibleForRosterGroup (Id staffId) rosterGroupId) parsedStaffId
    let assignmentError = case parsedAssignment of
            Just (StaffAssignment _) | isNothing maybeStaff -> Just "Choose a staff member for this venue."
            Just (StaffAssignment _) | not staffEligible -> Just "That staff member is not applicable to this roster group."
            Just (StaffAssignment _) -> Nothing
            Just OpenAssignment -> Just "Choose a staff member to fill this Open shift."
            Nothing -> Just "Choose a staff member to fill this Open shift."
    let protectedFieldsSubmitted =
            any isJust
                [ submission.submittedRosterShiftStartTime
                , submission.submittedRosterShiftEndTime
                , submission.submittedRosterShiftTypeId
                ]
                || submission.submittedRosterShiftStartOccurrence /= ""
                || submission.submittedRosterShiftEndOccurrence /= ""
    let formError = if protectedFieldsSubmitted then Just "Only Staff can be changed while filling a Published Open shift." else Nothing
    let values =
            (rosterShiftDialogValuesFromSlot rosterSlot)
                { rosterShiftSelectedAssignment = parsedAssignment
                , rosterShiftFormError = formError
                , rosterShiftStaffError = assignmentError
                }
    case (formError, assignmentError, parsedAssignment) of
        (Nothing, Nothing, Just assignment@StaffAssignment {}) -> pure (Right assignment)
        _ -> pure (Left values)

validateRosterShiftDialogSubmission :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> RosterDay -> Maybe RosterSlot -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues ValidatedRosterShift)
validateRosterShiftDialogSubmission = validateRosterShiftDialogSubmissionWithInterval Nothing

-- Timeline creation offers five-minute starts; its existing editor must accept
-- and expose that precision. Grid creation/editing retain their venue policy.
rosterDialogInterval :: VenueConfig -> Maybe Int -> Int
rosterDialogInterval venueConfig override =
    maybe (venueShiftTimeIntervalMinutes venueConfig) (min (venueShiftTimeIntervalMinutes venueConfig)) override

validateRosterShiftDialogSubmissionWithInterval :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe Int -> Id RosterGroup -> RosterDay -> Maybe RosterSlot -> RosterShiftDialogSubmission -> IO (Either RosterShiftDialogValues ValidatedRosterShift)
validateRosterShiftDialogSubmissionWithInterval intervalOverride rosterGroupId rosterDay maybeExistingSlot submission = do
    venueConfig <- fetchVenueConfig
    let rosterDate = rosterDay.operationalDate
    let staffParam = submission.submittedRosterShiftStaffId
    let startParam = submission.submittedRosterShiftStartTime
    let endParam = submission.submittedRosterShiftEndTime
    let shiftTypeParam = submission.submittedRosterShiftTypeId
    let parsedAssignment = parseSubmittedRosterShiftAssignment staffParam
    let parsedStaffId = case parsedAssignment of
            Just (StaffAssignment (Id staffId)) -> Just staffId
            _                                   -> Nothing
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
            { rosterShiftSelectedAssignment = parsedAssignment
            , rosterShiftStartTime = fromMaybe "" (normalizeOptionalText startParam)
            , rosterShiftEndTime = fromMaybe "" (normalizeOptionalText endParam)
            , rosterShiftTypeId = parsedShiftTypeId
            , rosterShiftStartOccurrence = startOccurrence
            , rosterShiftEndOccurrence = endOccurrence
            , rosterShiftStartIsRepeated = startIsRepeated
            , rosterShiftEndIsRepeated = endIsRepeated
            }
    let staffError
            | isNothing (normalizeOptionalText staffParam) = Just "Choose a staff member or Open shift."
            | parsedAssignment == Just OpenAssignment = Nothing
            | isNothing parsedStaffId || not staffInVenue = Just "Choose a staff member for this venue."
            | not staffEligible = Just "That staff member is not applicable to this roster group."
            | otherwise = Nothing
    let existingStartTime = maybeExistingSlot >>= rosterSlotStartTime
    let existingEndTime = maybeExistingSlot >>= rosterSlotEndTime
    let interval = rosterDialogInterval venueConfig intervalOverride
        intervalError time maybeExisting =
            if isTimeOnMinuteInterval interval time || Just time == maybeExisting
                then Nothing
                else Just (if interval == 1 then "Choose a whole-minute time." else "Choose a time on a " <> tshow interval <> "-minute increment.")
    let startError
            | isNothing (normalizeOptionalText startParam) = Just "Choose a start time."
            | isNothing parsedStartTime = Just "Choose a valid start time."
            | Just startTime <- parsedStartTime, Just message <- intervalError startTime existingStartTime = Just message
            | Left message <- parsedStartOccurrence = Just message
            | startIsRepeated && isNothing startOccurrence = Just "Choose whether this is the first or second occurrence."
            | otherwise = Nothing
    let endError
            | isNothing (normalizeOptionalText endParam) = Just "Choose an end time."
            | isNothing parsedEndTime = Just "Choose a valid end time."
            | Just endTime <- parsedEndTime, Just message <- intervalError endTime existingEndTime = Just message
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
    case (staffError, startError, endError, shiftTypeError, timingError, resolutionError, parsedAssignment, parsedShiftTypeId, maybeResolvedBoundaries) of
        (Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Just assignment, Just shiftTypeId, Just (Right boundaries)) ->
            pure (Right ValidatedRosterShift
                { validRosterShiftAssignment = assignment
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
    rosterBoundaryErrorMessage BoundaryShiftShapeInvalid = "Shift boundaries are incomplete."

parseSubmittedRosterShiftAssignment :: Maybe Text -> Maybe RosterShiftAssignment
parseSubmittedRosterShiftAssignment maybeValue =
    case normalizeOptionalText maybeValue of
        Just "open" -> Just OpenAssignment
        Just value  -> StaffAssignment . Id <$> parseUUIDText value
        Nothing     -> Nothing

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
        |> applyRosterShiftAssignment valid.validRosterShiftAssignment
        |> set #shiftTypeId (Just valid.validRosterShiftTypeId)
        |> applyRosterSlotBoundaries valid.validRosterShiftBoundaries
