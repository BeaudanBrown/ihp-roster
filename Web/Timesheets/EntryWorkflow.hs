module Web.Timesheets.EntryWorkflow
    ( TimesheetRequestContext (..)
    , TimesheetCreationBlocker (..)
    , TimesheetCreateOutcome (..)
    , TimesheetEditOutcome (..)
    , fetchEditableTimesheetEntry
    , prepareChosenBlankTimesheetForm
    , prepareNewTimesheetForm
    , prepareTimesheetChooser
    , TimesheetChooserOutcome (..)
    , prepareEditTimesheetForm
    , createOrdinaryTimesheetEntry
    , editOrdinaryTimesheetEntry
    , TimesheetRosterPrefillOutcome (..)
    , TimesheetRosterPrefillFormOutcome (..)
    , TimesheetReviewIntent (..)
    , TimesheetReviewOutcome (..)
    , prepareRosterPrefillTimesheetForm
    , createRosterPrefillTimesheetEntry
    , reviewTimesheetEntry
    ) where

import Application.Error.Types (AppError)
import Application.Helper.SurfaceResource (LiveMutationResult)
import Application.Helper.View.Timesheets (TimesheetFormInputs)
import Application.PayAssignment (StaffPayAssignment (..), staffAssignmentSuppressesTimesheets)
import Application.VenueTime.Model
import Control.Monad (filterM, guard)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..))
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (newTimesheetEntryFromRosterPrefillUrl)
import Web.Timesheets.Projection
import Web.Timesheets.RosterGroupClassification
import Web.Timesheets.RosterPrefill (newTimesheetEntryFromRosterPrefill,
                                  timesheetRosterPrefillEndTime,
                                  timesheetRosterPrefillOperationalDate,
                                  timesheetRosterPrefillStartTime)
import Web.Timesheets.Validation
import Web.View.Timesheets.Chooser (TimesheetBlankChoice (..),
                                    TimesheetChooserRenderModel (..))
import Web.View.Timesheets.New (NewTimesheetRenderModel (..))
import Web.View.Timesheets.RosterPrefillNew (RosterPrefillTimesheetRenderModel (..))

-- Canonical response context, not authorization evidence. Existing-entry scope
-- checks must precede reading the mutation calendar and canonicalizing filters.
data TimesheetRequestContext = TimesheetRequestContext
    { timesheetScope   :: TimesheetWeekScopeValue
    , timesheetFilters :: TimesheetViewFilters
    }

data TimesheetCreationBlocker
    = NoTimesheetStaff
    | NoEnabledTimesheetStaff
    | ViewerTimesheetsDisabled
    | TimesheetStaffConfigurationRequired
    | NoTimesheetShiftTypes
    | NoTimesheetDay
    | TimesheetTimingUnavailable

data TimesheetCreateOutcome
    = TimesheetCreateBlocked TimesheetCreationBlocker
    | TimesheetCreateInvalid NewTimesheetRenderModel
    | TimesheetCreateCompleted (Either TimesheetCalendarConflict (LiveMutationResult TimesheetEntry))

data TimesheetEditOutcome
    = TimesheetEditInvalid TimesheetFormInputs
    | TimesheetEditCompleted (Either TimesheetCalendarConflict (Bool, LiveMutationResult TimesheetEntry))

data TimesheetChooserOutcome
    = TimesheetChooserBlocked TimesheetCreationBlocker
    | TimesheetChooserDirectBlank NewTimesheetRenderModel
    | TimesheetChooserRequired TimesheetChooserRenderModel

-- Preserve the existing lookup/venue/visibility/window precedence. This snapshot
-- does not introduce a new row lock or change the mutation's calendar lock.
fetchEditableTimesheetEntry :: (?request :: Request, ?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext) => Id TimesheetEntry -> IO TimesheetEntry
fetchEditableTimesheetEntry entryId = do
    entry <- fetch entryId
    ensureRecordInCurrentVenue entry.venueId
    ensureTimesheetVisibility entry
    ensureEditWindowOrManager (timesheetEntryOperationalDate entry)
    pure entry

prepareEditTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe UUID -> TimesheetEntry -> IO TimesheetFormInputs
prepareEditTimesheetForm selectedStaffFilterId entry = do
    formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor entry) selectedStaffFilterId
    pure (timesheetFormInputsFor formContext entry)

prepareTimesheetChooser :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe UUID -> Day -> IO TimesheetChooserOutcome
prepareTimesheetChooser selectedStaffFilterId operationalDate = do
    formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
    case (formContext.formStaffMembers, formContext.formShiftTypes) of
        ([], _) -> TimesheetChooserBlocked <$> unavailableTimesheetStaffBlocker formContext
        (_, []) -> pure (TimesheetChooserBlocked NoTimesheetShiftTypes)
        (eligibleStaff, _) -> do
            rosterShifts <- fetchAuthorizedTimesheetRosterPrefillsForWindow operationalDate (addDays 1 operationalDate) Nothing
            rosterGroups <- fetchActiveTimesheetRosterGroups
            let orderedStaff = sortOn (\staff -> (Text.toCaseFold staff.lastName, Text.toCaseFold staff.firstName, staff.id)) eligibleStaff
            staffClassifications <- forM orderedStaff \staff -> do
                classifications <- validTimesheetRosterGroupClassificationsForStaff (unpackId currentVenueId) (unpackId staff.id)
                pure (staff, classifications)
            let groupOrder = Map.fromList [(unpackId group.id, index) | (index, group) <- zip [0 :: Int ..] rosterGroups]
            let classificationOrder = \case
                    TimesheetInRosterGroup groupId -> (Map.findWithDefault maxBound groupId groupOrder, (0 :: Int), groupId)
                    TimesheetNoRosterGroup -> (maxBound, 1, UUID.nil)
            let blankClassifications = sortOn classificationOrder (Set.toList (Set.fromList (concatMap snd staffClassifications)))
            let defaultStaffFor classification =
                    let matchingStaff = [staff | (staff, classifications) <- staffClassifications, classification `elem` classifications]
                     in find (\staff -> Just (unpackId staff.id) == selectedStaffFilterId) matchingStaff
                            <|> (formContext.formCurrentViewerStaffId >>= \staffId -> find ((== staffId) . unpackId . (.id)) matchingStaff)
                            <|> listToMaybe matchingStaff
            let blankChoices = mapMaybe (\classification -> TimesheetBlankChoice <$> defaultStaffFor classification <*> pure classification) blankClassifications
            let staffNames = Map.fromList [(unpackId staff.id, (Text.toCaseFold staff.lastName, Text.toCaseFold staff.firstName)) | staff <- eligibleStaff]
            let currentViewerId = formContext.formCurrentViewerStaffId
            let groupIndex rosterPrefill = Map.findWithDefault maxBound rosterPrefill.prefillRosterGroupId groupOrder
            let ownShiftOrder rosterPrefill =
                    ( timesheetRosterPrefillStartTime rosterPrefill
                    , timesheetRosterPrefillEndTime rosterPrefill
                    , rosterPrefill.prefillRosterSlotId
                    )
            let otherShiftOrder rosterPrefill =
                    ( groupIndex rosterPrefill
                    , timesheetRosterPrefillStartTime rosterPrefill
                    , Map.findWithDefault ("", "") rosterPrefill.prefillStaffId staffNames
                    , rosterPrefill.prefillRosterSlotId
                    )
            let (ownRosterShifts, otherRosterShifts) = partition ((== currentViewerId) . Just . (.prefillStaffId)) rosterShifts
            let chooserRosterShifts = sortOn ownShiftOrder ownRosterShifts <> sortOn otherShiftOrder otherRosterShifts
            let chooserBlankChoices = blankChoices
            let chooserStaffMembers = eligibleStaff
            let chooserShiftTypes = formContext.formShiftTypes
            let chooserRosterGroups = rosterGroups
            let chooserCalendarRevision = formContext.formVenueConfig.rosterCalendarRevision
            let chooserSelectedStaffFilter = selectedStaffFilterId
            let chooserCurrentViewerStaff = currentViewerId
            let chooserOperationalDate = operationalDate
            case (chooserRosterShifts, chooserBlankChoices) of
                ([], [soleChoice]) ->
                    prepareNewTimesheetForm (Just (unpackId soleChoice.blankChoiceStaff.id)) (Just operationalDate) (Just soleChoice.blankChoiceClassification)
                        >>= \case
                            Left blocker -> pure (TimesheetChooserBlocked blocker)
                            Right model -> pure (TimesheetChooserDirectBlank model)
                _ -> pure (TimesheetChooserRequired TimesheetChooserRenderModel { .. })

prepareChosenBlankTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UUID -> Day -> TimesheetRosterGroupClassification -> IO (Maybe (Either TimesheetCreationBlocker NewTimesheetRenderModel))
prepareChosenBlankTimesheetForm selectedStaffId operationalDate classification =
    prepareTimesheetChooser (Just selectedStaffId) operationalDate >>= \case
        TimesheetChooserRequired model ->
            case find (\choice -> unpackId choice.blankChoiceStaff.id == selectedStaffId && choice.blankChoiceClassification == classification) model.chooserBlankChoices of
                Nothing -> pure Nothing
                Just _ -> Just <$> prepareNewTimesheetForm (Just selectedStaffId) (Just operationalDate) (Just classification)
        TimesheetChooserBlocked _ -> pure Nothing
        TimesheetChooserDirectBlank _ -> pure Nothing

prepareNewTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe UUID -> Maybe Day -> Maybe TimesheetRosterGroupClassification -> IO (Either TimesheetCreationBlocker NewTimesheetRenderModel)
prepareNewTimesheetForm selectedStaffFilterId maybeWorkedOn maybeClassification = do
    baseFormContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
    formContext <- constrainFormContextToClassification baseFormContext maybeClassification
    let venueConfig = formContext.formVenueConfig
    case (formContext.formStaffMembers, formContext.formShiftTypes, maybeWorkedOn) of
        ([], _, _) -> Left <$> unavailableTimesheetStaffBlocker formContext
        (_, [], _) -> pure (Left NoTimesheetShiftTypes)
        (_, _, Nothing) -> pure (Left NoTimesheetDay)
        (_, defaultShiftType : _, Just workedOn) ->
            case defaultTimesheetEntry venueConfig workedOn of
                Left _ -> pure (Left TimesheetTimingUnavailable)
                Right entry -> do
                    let defaultStaffId =
                            (formContext.formSelectedStaffFilterId >>= \staffId -> guard (any ((== staffId) . unpackId . (.id)) formContext.formStaffMembers) >> pure staffId)
                                <|> (formContext.formCurrentViewerStaffId >>= \staffId -> guard (any ((== staffId) . unpackId . (.id)) formContext.formStaffMembers) >> pure staffId)
                                <|> (unpackId . (.id) <$> listToMaybe formContext.formStaffMembers)
                    let timesheetEntry = entry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\record -> maybe record (\staffId -> set #staffId staffId record) defaultStaffId)
                            |> set #shiftTypeId (unpackId defaultShiftType.id)
                            |> (\record -> maybe record (`applyTimesheetRosterGroupClassification` record) maybeClassification)
                    let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                    pure (Right NewTimesheetRenderModel { .. })

constrainFormContextToClassification :: (?modelContext :: ModelContext) => TimesheetFormContext -> Maybe TimesheetRosterGroupClassification -> IO TimesheetFormContext
constrainFormContextToClassification context Nothing = pure context
constrainFormContextToClassification context (Just classification) = do
    matchingStaff <- filterM (\staff -> staffMatchesTimesheetRosterGroup staff.venueId (unpackId staff.id) classification) context.formStaffMembers
    pure context { formStaffMembers = matchingStaff }

-- An empty authorized option list is not necessarily a missing staff record.
-- Managers may create for colleagues even when their own profile is roster-only.
unavailableTimesheetStaffBlocker :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetFormContext -> IO TimesheetCreationBlocker
unavailableTimesheetStaffBlocker formContext
    | formContext.formViewerIsManager = pure NoEnabledTimesheetStaff
    | otherwise = fetchCurrentUserStaff >>= \case
        Nothing -> pure NoTimesheetStaff
        Just staff
            | staffAssignmentSuppressesTimesheets (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId) -> pure ViewerTimesheetsDisabled
            | otherwise -> pure TimesheetStaffConfigurationRequired

createOrdinaryTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> IO TimesheetCreateOutcome
createOrdinaryTimesheetEntry context = do
    let selectedStaffFilterId = context.timesheetFilters.filterStaffId
    submittedClassification <- submittedTimesheetRosterGroupClassification
    baseFormContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
    formContext <- constrainFormContextToClassification baseFormContext submittedClassification
    let venueConfig = formContext.formVenueConfig
    let submittedWorkedOn = fromMaybe context.timesheetScope.timesheetWindowStart (paramOrNothing @Day "workedOn")
    case (formContext.formStaffMembers, defaultTimesheetEntry venueConfig submittedWorkedOn) of
        ([], _) -> TimesheetCreateBlocked <$> unavailableTimesheetStaffBlocker formContext
        (_, Left _) -> pure (TimesheetCreateBlocked TimesheetTimingUnavailable)
        (_, Right entry) -> do
            let submittedEntry = entry
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry venueConfig formContext.formCurrentViewerStaffId
            classification <- case submittedClassification of
                Just classification -> pure classification
                Nothing -> validTimesheetRosterGroupClassificationsForStaff submittedEntry.venueId submittedEntry.staffId >>= \case
                    [classification] -> pure classification
                    _ -> accessDeniedUnless False >> pure TimesheetNoRosterGroup
            let timesheetEntryRecord = applyTimesheetRosterGroupClassification classification submittedEntry
            timesheetEntryRecord |> ifValid \case
                Left timesheetEntry -> do
                    let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                    pure (TimesheetCreateInvalid NewTimesheetRenderModel { .. })
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    classificationAllowed <- staffMatchesTimesheetRosterGroup timesheetEntry.venueId timesheetEntry.staffId classification
                    accessDeniedUnless classificationAllowed
                    TimesheetCreateCompleted <$> createTimesheetEntryMutation context.timesheetScope timesheetEntry

editOrdinaryTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> TimesheetEntry -> IO TimesheetEditOutcome
editOrdinaryTimesheetEntry context existingEntry = do
    formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor existingEntry) context.timesheetFilters.filterStaffId
    prepareTimesheetEdit formContext.formVenueConfig formContext.formCurrentViewerStaffId existingEntry >>= \case
        Left timesheetEntry -> pure (TimesheetEditInvalid (timesheetFormInputsFor formContext timesheetEntry))
        Right intent -> TimesheetEditCompleted <$> updateTimesheetEntryMutation context.timesheetScope intent

data TimesheetRosterPrefillFormOutcome
    = RosterPrefillTimesheetMissing
    | RosterPrefillTimesheetCanonicalRedirect Text
    | RosterPrefillTimesheetTimingUnavailable Day
    | RosterPrefillTimesheetForm RosterPrefillTimesheetRenderModel

data TimesheetRosterPrefillOutcome
    = RosterPrefillUnavailable
    | RosterPrefillTimingUnavailable
    | RosterPrefillInvalid RosterPrefillTimesheetRenderModel
    | RosterPrefillAccessDenied
    | RosterPrefillCalendarConflict TimesheetCalendarConflict
    | RosterPrefillChanged
    | RosterPrefillCompleted TimesheetMaterializationKind (LiveMutationResult TimesheetEntry)

data TimesheetReviewIntent = ApproveTimesheet | UnapproveTimesheet

data TimesheetReviewOutcome
    = TimesheetReviewTimingInvalid
    | TimesheetReviewFailed AppError
    | TimesheetReviewCalendarConflict TimesheetCalendarConflict
    | TimesheetReviewCompleted TimesheetReviewIntent (LiveMutationResult TimesheetEntry)

prepareRosterPrefillTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterSlot -> Maybe UUID -> Bool -> IO TimesheetRosterPrefillFormOutcome
prepareRosterPrefillTimesheetForm rosterSlotId selectedStaffFilterId needsCanonicalRedirect = do
    fetchTimesheetRosterPrefillForRosterSlot rosterSlotId >>= \case
        Nothing -> pure RosterPrefillTimesheetMissing
        Just rosterPrefill -> do
            let workedOn = timesheetRosterPrefillOperationalDate rosterPrefill
            if needsCanonicalRedirect
                then pure (RosterPrefillTimesheetCanonicalRedirect (newTimesheetEntryFromRosterPrefillUrl rosterSlotId workedOn selectedStaffFilterId))
                else do
                    baseFormContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
                    formContext <- constrainFormContextToClassification baseFormContext (Just (TimesheetInRosterGroup rosterPrefill.prefillRosterGroupId))
                    case validatePersistedTimezone formContext.formVenueConfig.timezone of
                        Left _ -> pure (RosterPrefillTimesheetTimingUnavailable workedOn)
                        Right () -> do
                            let timesheetEntry = newTimesheetEntryFromRosterPrefill (unpackId currentVenueId) rosterPrefill
                            let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                            pure (RosterPrefillTimesheetForm RosterPrefillTimesheetRenderModel { .. })

createRosterPrefillTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> Id RosterSlot -> IO TimesheetRosterPrefillOutcome
createRosterPrefillTimesheetEntry context rosterSlotId = do
    fetchTimesheetRosterPrefillForRosterSlot rosterSlotId >>= \case
        Nothing -> pure RosterPrefillUnavailable
        Just rosterPrefill -> do
            baseFormContext <- fetchTimesheetFormContext noReferencedTimesheetOptions context.timesheetFilters.filterStaffId
            formContext <- constrainFormContextToClassification baseFormContext (Just (TimesheetInRosterGroup rosterPrefill.prefillRosterGroupId))
            let venueConfig = formContext.formVenueConfig
            case validatePersistedTimezone venueConfig.timezone of
                Left _ -> pure RosterPrefillTimingUnavailable
                Right () -> do
                    let rosterPrefillEntry = newTimesheetEntryFromRosterPrefill (unpackId currentVenueId) rosterPrefill
                    let timesheetEntry =
                            if hasParam "startTime" || hasParam "hadBreak"
                                then buildTimesheetEntry venueConfig formContext.formCurrentViewerStaffId rosterPrefillEntry
                                else rosterPrefillEntry
                    timesheetEntry |> ifValid \case
                        Left invalidEntry -> do
                            let timesheetFormInputs = timesheetFormInputsFor formContext invalidEntry
                            pure (RosterPrefillInvalid RosterPrefillTimesheetRenderModel { .. })
                        Right validEntry ->
                            if validEntry.operationalDate /= rosterPrefill.prefillOperationalDate
                                then pure RosterPrefillAccessDenied
                                else do
                                    staffAllowed <- timesheetStaffAssignmentAllowed validEntry.staffId
                                    groupAllowed <-
                                        if validEntry.staffId == rosterPrefill.prefillStaffId
                                            then pure True
                                            else staffMatchesTimesheetRosterGroup validEntry.venueId validEntry.staffId (TimesheetInRosterGroup rosterPrefill.prefillRosterGroupId)
                                    shiftAllowed <- if staffAllowed && groupAllowed then timesheetShiftTypeAllowed validEntry.shiftTypeId else pure False
                                    if not shiftAllowed
                                        then pure RosterPrefillAccessDenied
                                        else materializeTimesheetRosterPrefillMutation context.timesheetScope rosterPrefill validEntry >>= \case
                                            Left conflict -> pure (RosterPrefillCalendarConflict conflict)
                                            Right Nothing -> pure RosterPrefillChanged
                                            Right (Just (kind, result)) -> pure (RosterPrefillCompleted kind result)

-- Controller invokes manager/writability/venue/deleted-row policy before reading
-- the shared request context. Timing and approval decisions stay here.
reviewTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> TimesheetReviewIntent -> TimesheetEntry -> IO TimesheetReviewOutcome
reviewTimesheetEntry context intent entry = case intent of
    ApproveTimesheet -> case decodeTimesheetTiming entry of
        Left _ -> pure TimesheetReviewTimingInvalid
        Right _ -> approveTimesheetEntryMutation context.timesheetScope entry >>= \case
            Left conflict -> pure (TimesheetReviewCalendarConflict conflict)
            Right (Left failure) -> pure (TimesheetReviewFailed failure)
            Right (Right result) -> pure (TimesheetReviewCompleted intent result)
    UnapproveTimesheet -> unapproveTimesheetEntryMutation context.timesheetScope entry >>= \case
        Left conflict -> pure (TimesheetReviewCalendarConflict conflict)
        Right result -> pure (TimesheetReviewCompleted intent result)

defaultTimesheetEntry :: VenueConfig -> Day -> Either BoundaryModelError TimesheetEntry
defaultTimesheetEntry venueConfig operationalDate = do
    let (startTime, endTime) = defaultShiftTimesForVenueConfig venueConfig
    boundaries <- resolveShiftBoundaries venueConfig.timezone ShiftBoundaryInput
        { shiftBoundaryDate = calendarDayForOperationalClock operationalDate startTime
        , shiftBoundaryStartTime = startTime
        , shiftBoundaryStartOccurrence = Nothing
        , shiftBoundaryEndTime = endTime
        , shiftBoundaryEndOccurrence = Nothing
        , shiftBoundaryBreak = Nothing
        }
    pure (newRecord @TimesheetEntry |> set #operationalDate operationalDate |> applyTimesheetEntryBoundaries boundaries)
