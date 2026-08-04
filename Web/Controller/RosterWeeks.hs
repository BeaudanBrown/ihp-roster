{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.FrontendContract.AppShell (ConfirmRemoveRosterRowOverlay,
                                                     DeleteRosterSlotOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Overlay.Runtime (dialogAutoSubmitOnceAttr)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeySetupPromptMode,
                                                            passkeySetupPromptModeFromValue)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceActionParamsPresent,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceIntentForm)
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (authoritativeRosterIntervalIsOperationallyValid,
                                     defaultShiftTimesForVenueConfig,
                                     isQuarterHourMinutes,
                                     isValidRosterShiftTimePair,
                                     minuteOfDayToTimeOfDay,
                                     rosterOperationalFinalSelectableMinute,
                                     rosterOperationalStartMinuteOfDay,
                                     rosterShiftStartDate,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Application.Helper.UserPreferences
import Application.Helper.View (DialogOverlayConfig (..), OverlayButton (..),
                                OverlayButtonAction (..),
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlay, renderToastOob,
                                successToast)
import Application.RosterShiftAssignment (RosterShiftAssignment (StaffAssignment),
                                          applyRosterShiftAssignment,
                                          copyRosterShiftAssignment,
                                          rosterShiftIsOpen)
import Application.VenueTime (RepeatedTimeOccurrence (..), VenueTimeError (..))
import Application.VenueTime.Model
import Control.Monad (guard)
import Data.Coerce (coerce)
import Data.Either (fromRight)
import Data.List (find, nub)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, mapMaybe)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time (getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import qualified Text.Read as TextRead
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.Controller.Sessions (passkeySetupPromptSessionKey)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.DropWorkflow
import Web.RosterWeeks.Filters
import Web.RosterWeeks.FrontendSurface (rosterDuplicateShiftIntentForm,
                                        rosterMoveShiftIntentForm,
                                        rosterTimelineMoveShiftIntentForm)
import Web.RosterWeeks.Mutations
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Paths (rosterCopyWeekUrl, rosterDayTimelineUrl,
                              rosterWeekUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondWithRosterContent,
                                  respondWithRosterContentError,
                                  respondWithRosterContentUpdate,
                                  respondWithRosterDialogOverlay,
                                  respondWithRosterFragmentsUpdate,
                                  respondWithRosterResourceInvalidation,
                                  respondWithRosterToast)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.ShiftWorkflow
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates,
                                     fetchRosterShiftDialogStaff,
                                     fetchStaffPayConfigurationRequiredIds)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.OccurrenceDialog
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.ShiftDialog
import Web.View.RosterWeeks.Show (renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderrosterStaffPanelLiveFragment)
import Web.View.RosterWeeks.Timeline (renderRosterDayTimelineContent)

rosterSurfaceRequestErrorMessage :: [SurfaceRequestFieldError] -> Text
rosterSurfaceRequestErrorMessage errors =
    "Check the roster controls: " <> surfaceRequestFieldErrorsMessage errors

copyOccurrenceSelectionsFromValues :: Maybe Text -> Maybe Text -> Either Text ShiftCopyOccurrenceSelections
copyOccurrenceSelectionsFromValues startValue endValue = do
    copyShiftStartOccurrence <- parseOccurrenceParam (fromMaybe "" startValue)
    copyShiftEndOccurrence <- parseOccurrenceParam (fromMaybe "" endValue)
    pure ShiftCopyOccurrenceSelections
        { copyShiftStartOccurrence
        , copyShiftEndOccurrence
        , copyShiftBreakStartOccurrence = Nothing
        , copyShiftBreakEndOccurrence = Nothing
        }

copyOccurrenceSelectionsFromRosterAction :: (?request :: Request) => Either Text ShiftCopyOccurrenceSelections
copyOccurrenceSelectionsFromRosterAction =
    case RosterAction.parseCopyRosterWeekActionParams of
        Left errors -> Left (rosterSurfaceRequestErrorMessage errors)
        Right fields ->
            copyOccurrenceSelectionsFromValues
                (surfaceFieldValue @Surface.CopyStartOccurrence fields)
                (surfaceFieldValue @Surface.CopyEndOccurrence fields)

parseRosterStaffPanelScope :: (?request :: Request) => Either Text RosterStaffPanelScope
parseRosterStaffPanelScope
    | not (surfaceActionParamsPresent @Surface.RosterSurface @Surface.ToggleRosterStaffScope) = Right RosterStaffPanelCurrentGroup
    | otherwise =
        case RosterAction.parseToggleRosterStaffScopeActionParams of
            Left errors -> Left (rosterSurfaceRequestErrorMessage errors)
            Right fields ->
                case Text.toLower (surfaceFieldValue @Surface.StaffScope fields) of
                    "all"   -> Right RosterStaffPanelAllVenue
                    "group" -> Right RosterStaffPanelCurrentGroup
                    _       -> Left "Choose a valid roster staff scope."

respondWithRosterCopyFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterCopyFailure rosterGroupId targetWeekOffset message =
    if isHtmxRequest
        then respondWithRosterToast message "app-toast-error"
        else do
            setErrorMessage message
            redirectToPath (rosterWeekUrl targetWeekOffset rosterGroupId)

respondWithRosterCopyOccurrenceDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Int -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> IO ()
respondWithRosterCopyOccurrenceDialog rosterGroupId sourceWeekOffset targetWeekOffset startIsRepeated endIsRepeated selections =
    if not isHtmxRequest
        then respondWithRosterCopyFailure rosterGroupId targetWeekOffset "Choose repeated-time occurrences from the roster copy dialog."
        else do
            let dialog = renderRosterWeekCopyOccurrenceDialog
                    (rosterCopyWeekUrl sourceWeekOffset targetWeekOffset rosterGroupId)
                    startIsRepeated
                    endIsRepeated
                    selections
            respondWithRosterDialogOverlay rosterGroupId targetWeekOffset dialog

respondWithRosterShiftOccurrenceDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> FrontendSurfaceIntentForm -> (Text, Text) -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> IO ()
respondWithRosterShiftOccurrenceDialog rosterGroupId weekOffset operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections =
    if not isHtmxRequest
        then respondWithMoveRosterShiftFailure rosterGroupId weekOffset "Choose repeated-time occurrences from the roster copy dialog."
        else do
            let dialog = renderRosterShiftOccurrenceDialog operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections
            respondWithRosterDialogOverlay rosterGroupId weekOffset dialog

respondWithRosterSlotCopyBoundaryFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> FrontendSurfaceIntentForm -> (Text, Text) -> (Bool, Bool) -> ShiftCopyOccurrenceSelections -> BoundaryModelError -> IO ()
respondWithRosterSlotCopyBoundaryFailure rosterGroupId weekOffset operationLabel intentForm occurrenceFields (startIsRepeated, endIsRepeated) selections failure =
    case failure of
        BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)
            | startIsRepeated || endIsRepeated ->
                respondWithRosterShiftOccurrenceDialog rosterGroupId weekOffset operationLabel intentForm occurrenceFields startIsRepeated endIsRepeated selections
        _ -> respondWithMoveRosterShiftFailure rosterGroupId weekOffset (rosterCopyBoundaryErrorMessage failure)

rosterCopyBoundaryErrorMessage :: BoundaryModelError -> Text
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (NonexistentCivilTime _)) = "A copied roster time does not exist because clocks move forward. Change the source shift before copying."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)) = "Choose whether repeated copied times use their first or second occurrence."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedTimeOccurrenceNotApplicable _ _)) = "A copied occurrence choice applies only to a repeated local time."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (InvalidCivilTimeOfDay _)) = "The source roster contains an invalid local time."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (NonPositiveResolvedInterval _ _)) = "The copied roster shift would not have a positive duration."
rosterCopyBoundaryErrorMessage (BoundaryUnsupportedTimezone _) = "This venue timezone is not supported for roster copying."
rosterCopyBoundaryErrorMessage BoundaryBreakNotContained = "The copied break would fall outside its shift."
rosterCopyBoundaryErrorMessage BoundaryBreakShapeInvalid = "The copied break boundaries are incomplete."

rosterDayMutationMountedProjections :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> IO [RosterProjectionFragment]
rosterDayMutationMountedProjections rosterDay = do
    layoutMode <- fetchCurrentRosterLayoutMode
    pure $
        rosterGridInnerAndStaffPanelFragments
            <> case rosterLayoutModeValue layoutMode of
                "day_columns" -> []
                _ -> [rosterDaySectionFragment (unpackId rosterDay.id)]

instance Controller RosterWeeksController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@RosterWeeksAction = runBepis currentAction BepisPageAction do
        -- Redirect to the current week's offset based on today's date
        currentWeekOffset <- fetchCurrentRosterWeekOffset
        currentRosterGroup <- resolveRequestedRosterGroup
        currentWeekPath <- case paramOrNothing @Text "rosterView" of
            Just "timeline" -> do
                venueConfig <- fetchVenueConfig
                today <- utctDay <$> getCurrentTime
                let todayDayOffset = fromInteger (Calendar.diffDays today (venueWeekStartDate venueConfig currentWeekOffset))
                pure (rosterDayTimelineUrl currentWeekOffset currentRosterGroup.id (max 0 (min 6 todayDayOffset)))
            _ -> pure (rosterWeekUrl currentWeekOffset currentRosterGroup.id)

        if isHtmxRequest
            then case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
                (Just "timeline", Nothing) -> do
                    setHeader ("HX-Redirect", cs currentWeekPath)
                    respondHtmlProfiled mempty
                _ -> do
                    setHtmxPushUrl currentWeekPath
                    renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action currentAction@ShowRosterWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        when (surfaceActionParamsPresent @Surface.RosterSurface @Surface.NavigateRosterWeek) do
            case RosterAction.parseNavigateRosterWeekActionParams of
                Left errors -> do
                    setErrorMessage (rosterSurfaceRequestErrorMessage errors)
                    redirectTo RosterWeeksAction
                Right fields -> do
                    accessDeniedUnless (surfaceFieldValue @Surface.WeekOffset fields == weekOffset)
                    accessDeniedUnless (surfaceFieldValue @Surface.RosterGroupId fields == unpackId rosterGroup.id)
        case paramOrNothing @Calendar.Day "weekDate" of
            Just weekDate -> do
                venueConfig <- fetchVenueConfig
                let selectedWeekOffset = venueWeekOffsetForDay venueConfig weekDate
                let targetPath = rosterWeekUrl selectedWeekOffset rosterGroup.id
                if isHtmxRequest
                    then do
                        setHtmxPushUrl targetPath
                        renderRosterWeekPage selectedWeekOffset rosterGroup.id
                    else redirectToPath targetPath
            Nothing ->
                renderRosterWeekPage weekOffset rosterGroup.id

    action currentAction@ShowRosterDayTimelineAction { weekOffset, rosterDayId } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> do
                setErrorMessage "Roster week not found."
                redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Just rosterData -> do
                let canViewTimeline = rosterData.rosterWeek.isLive || hasRole Manager
                accessDeniedUnless canViewTimeline
                case find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays of
                    Nothing -> do
                        setErrorMessage "Roster day not found."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
                    Just rosterDay ->
                        redirectToPath (rosterDayTimelineUrl weekOffset rosterGroup.id rosterDay.dayOffset)

    action currentAction@ShowRosterDayTimelineContentFragmentAction { weekOffset, rosterDayId } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> respondHtmlProfiled mempty
            Just rosterData -> do
                let canViewTimeline = rosterData.rosterWeek.isLive || hasRole Manager
                accessDeniedUnless canViewTimeline
                let maybeRosterDay = find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays
                respondHtmlProfiled (maybe mempty (renderRosterDayTimelineContent Nothing rosterData) maybeRosterDay)

    action currentAction@ShowRosterWeekOverviewFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment weekOffset rosterGroup.id

    action currentAction@ShowRosterWeekContentFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        respondWithRosterContent rosterGroup.id weekOffset

    action currentAction@ShowRosterWeekGridToolbarFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        toolbarHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridToolbar
        respondHtmlProfiled (fromMaybe mempty toolbarHtml)

    action currentAction@ShowRosterWeekGridFrameFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        frameHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridFrame
        respondHtmlProfiled (fromMaybe mempty frameHtml)

    action currentAction@ShowRosterWeekDayColumnsFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayColumns
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekDayRailFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekWageRailFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionWageRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekSlotsGridFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionSlotsGrid
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekStaffPanelFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        rosterGroup <- resolveRequestedRosterGroup
        panelScope <- case parseRosterStaffPanelScope of
            Left errorMessage -> setErrorMessage errorMessage >> pure RosterStaffPanelCurrentGroup
            Right scope -> pure scope
        panelModel <- fetchVisibleRosterStaffPanelRenderModel panelScope rosterGroup.id weekOffset
        respondHtmlProfiled (renderrosterStaffPanelLiveFragment panelModel)

    action currentAction@ShowRosterWeekDaySectionFragmentAction { weekOffset, rosterDayId } = runBepis currentAction BepisFragmentAction do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        daySectionHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action currentAction@ShowRosterWeekRowFragmentAction { weekOffset, rosterDayId, rowIndex } = runBepis currentAction BepisFragmentAction do
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        rowHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action currentAction@UpdateRosterAssignmentFiltersAction { weekOffset } = runBepis currentAction BepisPreferenceAction do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterAssignmentFiltersActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Right fields -> do
                setRosterAssignmentFiltersSession RosterAssignmentFilters
                    { hideStaffAtIdealShifts = surfaceFieldValue @Surface.HideStaffAtIdealShifts fields
                    , hideStaffUnavailable = surfaceFieldValue @Surface.HideStaffUnavailable fields
                    , hideStaffOnApprovedLeave = surfaceFieldValue @Surface.HideStaffOnApprovedLeave fields
                    , hideStaffAlreadyAssignedToday = surfaceFieldValue @Surface.HideStaffAlreadyAssignedToday fields
                    }
                respondHtmlProfiled mempty

    action currentAction@CreateRosterWeekAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        mutationResult <- ensureRosterWeekExistsMutation rosterGroup.id weekOffset
        let (rosterWeek, wasCreated) = mutationResult.liveMutationValue

        let successMessage =
                if wasCreated
                    then "Roster week created successfully"
                    else "Roster week already exists."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroup.id
        if isHtmxRequest
            then do
                setHtmxPushUrl targetPath
                respondWithRosterContentUpdate rosterGroup.id rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action currentAction@CopyRosterWeekAction { sourceWeekOffset, targetWeekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup

        if sourceWeekOffset == targetWeekOffset
            then do
                let errorMessage = "Cannot copy a roster week onto itself."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl targetWeekOffset rosterGroup.id)
            else do
                sourceWeekOrNothing <- query @RosterWeek
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhere (#weekOffset, sourceWeekOffset)
                    |> fetchOneOrNothing
                case sourceWeekOrNothing of
                    Nothing -> do
                        let errorMessage = "Source week not found. Cannot copy."
                        if isHtmxRequest
                            then respondWithRosterToast errorMessage "app-toast-error"
                            else do
                                setErrorMessage errorMessage
                                redirectToPath (rosterWeekUrl targetWeekOffset rosterGroup.id)
                    Just sourceWeek ->
                        case copyOccurrenceSelectionsFromRosterAction of
                            Left message -> respondWithRosterCopyFailure rosterGroup.id targetWeekOffset message
                            Right selections -> do
                                copyResult <- copyRosterWeekFromSourceMutation selections rosterGroup.id sourceWeek targetWeekOffset
                                case copyResult of
                                    Left (RosterWeekCopyPersistenceError message) ->
                                        respondWithRosterCopyFailure rosterGroup.id targetWeekOffset message
                                    Left (RosterWeekCopyBoundaryError failure) -> do
                                        venueConfig <- fetchVenueConfig
                                        (startIsRepeated, endIsRepeated) <- rosterWeekCopyAmbiguousEndpoints venueConfig sourceWeek targetWeekOffset
                                        case failure of
                                            BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)
                                                | startIsRepeated || endIsRepeated ->
                                                    respondWithRosterCopyOccurrenceDialog rosterGroup.id sourceWeekOffset targetWeekOffset startIsRepeated endIsRepeated selections
                                            _ -> respondWithRosterCopyFailure rosterGroup.id targetWeekOffset (rosterCopyBoundaryErrorMessage failure)
                                    Right mutationResult -> do
                                        let successMessage = "Roster week copied from the previous week."
                                        let targetPath = rosterWeekUrl targetWeekOffset rosterGroup.id
                                        if isHtmxRequest
                                            then do
                                                setHtmxPushUrl targetPath
                                                respondWithRosterContentUpdate rosterGroup.id targetWeekOffset mutationResult.liveMutationTouchedResources successMessage
                                            else do
                                                setSuccessMessage successMessage
                                                redirectToPath targetPath

    action currentAction@ToggleRosterWeekLiveStatusAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        case RosterAction.parseToggleRosterWeekLiveStatusActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterContentError rosterGroupId rosterWeek.weekOffset errorMessage
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            Right fields -> do
                let nextLiveStatus = surfaceFieldValue @Surface.IsLive fields
                mutationResult <- toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus
                case mutationResult of
                    Left errorMessage ->
                        if isHtmxRequest
                            then respondWithRosterContentError rosterGroupId rosterWeek.weekOffset errorMessage
                            else do
                                setErrorMessage errorMessage
                                redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
                    Right mutationResult -> do
                        let successMessage =
                                if nextLiveStatus
                                    then "Roster week is now live. Timesheet suggestions are available immediately."
                                    else "Roster week moved back to draft. Timesheet suggestions are hidden."
                        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
                        if isHtmxRequest
                            then do
                                setHtmxPushUrl targetPath
                                respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
                            else do
                                setSuccessMessage successMessage
                                redirectToPath targetPath

    action currentAction@CreateRosterWeekSlotDefinitionAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        requestedSlotName <- resolveRosterSlotDefinitionNameForCreate rosterWeek
        case requestedSlotName of
            Left errorMessage -> respondToRosterSlotDefinitionError rosterWeek errorMessage
            Right slotName -> do
                duplicate <- activeRosterWeekSlotDefinitionWithName rosterWeek slotName
                case duplicate of
                    Just _ -> respondToRosterSlotDefinitionError rosterWeek "A column with that name already exists for this week."
                    Nothing -> do
                        mutationResult <- appendRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotName
                        respondToRosterSlotDefinitionSuccess rosterWeek mutationResult "Roster column added."

    action currentAction@DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        slotDefinition <- fetch rosterWeekSlotDefinitionId
        rosterWeek <- fetch (Id slotDefinition.rosterWeekId :: Id RosterWeek)
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        activeDefinitions <- query @RosterWeekSlotDefinition
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
        if length activeDefinitions <= 1
            then respondToRosterSlotDefinitionError rosterWeek "Roster weeks need at least one column."
            else do
                let rosterGroupId = coerce rosterWeek.rosterGroupId
                mutationResult <- removeRosterWeekSlotDefinitionMutation rosterGroupId rosterWeek slotDefinition
                respondToRosterSlotDefinitionSuccess rosterWeek mutationResult "Roster column removed."

    action currentAction@SortRosterWeekAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        mutationResult <- repackRosterWeekMutation rosterWeek

        if isHtmxRequest
            then
                respondWithRosterResourceInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    mutationResult.liveMutationTouchedResources
                    rosterGridInnerAndStaffPanelFragments
                    clearDialogOverlayOob
            else do
                setSuccessMessage "Roster sorted."
                redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@ToggleRosterDayClosedAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let nextClosedState = not rosterDay.isClosed

        mutationResult <- toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState closedRosterDayRows

        let successMessage =
                if nextClosedState
                    then "Roster day marked closed."
                    else "Roster day reopened."
        let targetPath = rosterWeekUrl rosterWeek.weekOffset rosterGroupId
        if isHtmxRequest
            then do
                mountedProjections <- rosterDayMutationMountedProjections rosterDay
                setHtmxPushUrl targetPath
                respondWithRosterResourceInvalidation
                    rosterGroupId
                    rosterWeek.weekOffset
                    mutationResult.liveMutationTouchedResources
                    mountedProjections
                    clearDialogOverlayOob
            else do
                setSuccessMessage successMessage
                redirectToPath targetPath

    action currentAction@AddRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        slotTemplate <- fetchRosterWeekSlotTemplate rosterWeek

        if null slotTemplate
            then do
                let errorMessage = "Add at least one active slot to the selected roster group before adding roster rows."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
            else do
                mutationResult <- addRosterDayRowMutation rosterGroupId rosterWeek rosterDay

                if isHtmxRequest
                    then do
                        mountedProjections <- rosterDayMutationMountedProjections rosterDay
                        respondWithRosterResourceInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            mutationResult.liveMutationTouchedResources
                            mountedProjections
                            clearDialogOverlayOob
                    else do
                        setSuccessMessage "Roster row added."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@RemoveRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetch rosterDayId
        let rosterWeekId = (coerce rosterDay.rosterWeekId :: Id RosterWeek)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rowCount = rosterDay.rowCount
        let confirmDeletePopulatedRow = paramOrDefault @Text "false" "confirmDeletePopulatedRow" == "true"

        when (rowCount <= minimumOpenRosterRows) do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Roster days must keep at least two rows."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        activeDefinitions <- fetchRosterWeekOrderedSlotNames rosterWeek
        preview <- previewRemoveRosterRowPacking rosterDay activeDefinitions
        if preview.removeRosterRowOverflowCount > 0 && not confirmDeletePopulatedRow
            then respondWithRemoveRosterRowConfirmation rosterDay preview
            else do
                mutationResult <- removeRosterDayRowMutation rosterGroupId rosterWeek rosterDay activeDefinitions

                if isHtmxRequest
                    then do
                        mountedProjections <- rosterDayMutationMountedProjections rosterDay
                        respondWithRosterResourceInvalidation
                            rosterGroupId
                            rosterWeek.weekOffset
                            mutationResult.liveMutationTouchedResources
                            mountedProjections
                            clearDialogOverlayOob
                    else do
                        setSuccessMessage "Roster row removed."
                        redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

    action currentAction@UpdateRosterLayoutPreferenceAction { weekOffset } = runBepis currentAction BepisPreferenceAction do
        rosterGroup <- resolveRequestedRosterGroup
        let requestedLayoutMode =
                case RosterIntent.parseSetRosterLayoutModeIntentParams of
                    Left errors -> Left (rosterSurfaceRequestErrorMessage errors)
                    Right fields ->
                        maybe
                            (Left "Choose a valid roster layout.")
                            Right
                            (parseRosterLayoutMode (surfaceFieldValue @Surface.RosterLayoutMode fields))
        case requestedLayoutMode of
            Left requestError -> do
                let errorMessage = requestError
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Right layoutMode -> do
                _ <- upsertCurrentUserRosterLayoutMode layoutMode
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster layout preference saved.")
                    else do
                        setSuccessMessage "Roster layout preference saved."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@MoveRosterShiftToSlotAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        case RosterIntent.parseMoveRosterShiftToSlotIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                if parseRosterShiftDropDestinationToken targetToken == Just DeleteRosterShiftDestination
                    then do
                        result <- validateRosterShiftDeleteDropIntent rosterGroup.id weekOffset sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot
                    else do
                        result <- validateMoveRosterShiftIntent rosterGroup.id weekOffset sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            Right MoveRosterShiftIntent { moveIsNoOp = True } -> respondWithSilentRosterNoOp rosterGroup.id weekOffset
                            Right resultValue@MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                                let startOccurrenceValue = surfaceFieldValue @Surface.CopyStartOccurrence fields
                                let endOccurrenceValue = surfaceFieldValue @Surface.CopyEndOccurrence fields
                                case copyOccurrenceSelectionsFromValues startOccurrenceValue endOccurrenceValue of
                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                    Right selections -> do
                                        boundaryResolution <- resolveRosterDayDropBoundaries resultValue selections
                                        let intentForm = rosterMoveShiftIntentForm weekOffset rosterGroup.id sourceToken targetToken Nothing Nothing
                                        let occurrenceFields = (surfaceFieldNameFrom @Surface.CopyStartOccurrence fields, surfaceFieldNameFrom @Surface.CopyEndOccurrence fields)
                                        case boundaryResolution of
                                            RosterDayDropBoundaryFailure repeatedEndpoints failure ->
                                                respondWithRosterSlotCopyBoundaryFailure rosterGroup.id weekOffset "move" intentForm occurrenceFields repeatedEndpoints selections failure
                                            RosterDayDropBoundaryReady targetRosterWeek copiedBoundariesSlot -> do
                                                let updatedSlot = copiedBoundariesSlot
                                                        |> set #rosterDayId (unpackId targetRosterDay.id)
                                                        |> set #rosterWeekSlotDefinitionId (unpackId targetSlotDefinition.id)
                                                        |> set #slotSortOrder targetSlotDefinition.sortOrder
                                                        |> set #rowIndex targetRowIndex
                                                mutationResult <- moveRosterSlotMutation rosterGroup.id targetRosterWeek sourceRosterDay targetRosterDay sourceSlot updatedSlot
                                                case mutationResult of
                                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                                    Right mutationResult -> do
                                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                                        let impactedRows = nub [(sourceSlot.rosterDayId, sourceSlot.rowIndex), (unpackId targetRosterDay.id, targetRowIndex)]
                                                        respondToRosterSlotMove rosterGroup.id targetRosterWeek mutationResult impactedRows shouldWarnSourceTimesheetUnchanged

    action currentAction@MoveRosterTimelineShiftAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        case RosterIntent.parseMoveRosterTimelineShiftIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                result <- validateMoveRosterTimelineShiftIntent rosterGroup.id weekOffset sourceToken targetToken
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right MoveRosterTimelineShiftIntent { timelineMoveIsNoOp = True } -> respondWithSilentRosterNoOp rosterGroup.id weekOffset
                    Right resultValue@MoveRosterTimelineShiftIntent { timelineSourceSlot, timelineSourceRosterDay, timelineTargetRosterDay, timelineTargetSlotDefinition, timelineTargetRowIndex } -> do
                        let startOccurrenceValue = fromMaybe "" (surfaceFieldValue @Surface.TimelineStartOccurrence fields)
                        boundaryResolution <- resolveRosterTimelineDropBoundaries resultValue startOccurrenceValue
                        let intentForm = rosterTimelineMoveShiftIntentForm weekOffset rosterGroup.id timelineTargetRosterDay.dayOffset sourceToken targetToken Nothing
                        let startOccurrenceField = surfaceFieldNameFrom @Surface.TimelineStartOccurrence fields
                        let occurrenceFields = (startOccurrenceField, startOccurrenceField)
                        case boundaryResolution of
                            RosterTimelineDropInvalid message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            RosterTimelineDropBoundaryFailure repeatedEndpoints selections failure ->
                                respondWithRosterSlotCopyBoundaryFailure rosterGroup.id weekOffset "move" intentForm occurrenceFields repeatedEndpoints selections failure
                            RosterTimelineDropBoundaryReady rosterWeek boundaries -> do
                                let updatedSlot = timelineSourceSlot
                                        |> set #rosterDayId (unpackId timelineTargetRosterDay.id)
                                        |> set #rosterWeekSlotDefinitionId (unpackId timelineTargetSlotDefinition.id)
                                        |> set #slotSortOrder timelineTargetSlotDefinition.sortOrder
                                        |> set #rowIndex timelineTargetRowIndex
                                        |> applyRosterSlotBoundaries boundaries
                                mutationResult <- moveRosterSlotMutation rosterGroup.id rosterWeek timelineSourceRosterDay timelineTargetRosterDay timelineSourceSlot updatedSlot
                                case mutationResult of
                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                    Right mutationResult -> do
                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                        respondToRosterTimelineSlotMove rosterGroup.id rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged

    action currentAction@DuplicateRosterShiftToDayAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        case RosterIntent.parseDuplicateRosterShiftToDayIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                if parseRosterShiftDropDestinationToken targetToken == Just DeleteRosterShiftDestination
                    then do
                        result <- validateRosterShiftDeleteDropIntent rosterGroup.id weekOffset sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot
                    else do
                        result <- validateDuplicateRosterShiftIntent rosterGroup.id weekOffset sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            Right resultValue@MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                                let startOccurrenceValue = surfaceFieldValue @Surface.CopyStartOccurrence fields
                                let endOccurrenceValue = surfaceFieldValue @Surface.CopyEndOccurrence fields
                                case copyOccurrenceSelectionsFromValues startOccurrenceValue endOccurrenceValue of
                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                    Right selections -> do
                                        boundaryResolution <- resolveRosterDayDropBoundaries resultValue selections
                                        let intentForm = rosterDuplicateShiftIntentForm weekOffset rosterGroup.id sourceToken targetToken Nothing Nothing
                                        let occurrenceFields = (surfaceFieldNameFrom @Surface.CopyStartOccurrence fields, surfaceFieldNameFrom @Surface.CopyEndOccurrence fields)
                                        case boundaryResolution of
                                            RosterDayDropBoundaryFailure repeatedEndpoints failure ->
                                                respondWithRosterSlotCopyBoundaryFailure rosterGroup.id weekOffset "duplicate" intentForm occurrenceFields repeatedEndpoints selections failure
                                            RosterDayDropBoundaryReady targetRosterWeek copiedBoundariesSlot ->
                                                case copyRosterShiftAssignment sourceSlot (newRecord @RosterSlot) of
                                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                                    Right assignmentSlot -> do
                                                        let copiedSlot = assignmentSlot
                                                                |> set #rosterDayId (unpackId targetRosterDay.id)
                                                                |> set #rosterWeekSlotDefinitionId (unpackId targetSlotDefinition.id)
                                                                |> set #slotSortOrder targetSlotDefinition.sortOrder
                                                                |> set #rowIndex targetRowIndex
                                                                |> set #startsAt copiedBoundariesSlot.startsAt
                                                                |> set #endsAt copiedBoundariesSlot.endsAt
                                                                |> set #timezone copiedBoundariesSlot.timezone
                                                                |> set #shiftTypeId sourceSlot.shiftTypeId
                                                        mutationResult <- saveRosterSlotMutation rosterGroup.id targetRosterWeek targetRosterDay Nothing copiedSlot
                                                        case mutationResult of
                                                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                                            Right mutationResult ->
                                                                respondToRosterSlotMutation rosterGroup.id targetRosterWeek targetRosterDay targetRowIndex mutationResult "Roster shift duplicated."

    action currentAction@DropRosterStaffAction { weekOffset } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        case RosterIntent.parseDropRosterStaffIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                result <- validateRosterStaffDropIntent rosterGroup.id weekOffset sourceToken targetToken
                case result of
                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                    Right RosterStaffExistingShiftDropIntent { staffDropStaff, staffDropSlot, staffDropRosterDay, staffDropRosterWeek } -> do
                        let updatedSlot = staffDropSlot |> applyRosterShiftAssignment (StaffAssignment staffDropStaff.id)
                        mutationResult <- updateRosterSlotMutation rosterGroup.id staffDropRosterWeek staffDropRosterDay staffDropSlot updatedSlot
                        case mutationResult of
                            Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            Right mutationResult -> do
                                let warningToast = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                respondToRosterSlotMutation rosterGroup.id staffDropRosterWeek staffDropRosterDay updatedSlot.rowIndex mutationResult $
                                    if warningToast then "Staff assigned. A timesheet entry was already created from this roster shift. The timesheet snapshot was not changed." else "Staff assigned."
                    Right RosterStaffCreateShiftDropIntent { staffDropStaff, staffDropRosterDay, staffDropRosterWeek, staffDropSlotDefinition, staffDropRowIndex } -> do
                        payInvalidStaffIds <- fetchStaffPayConfigurationRequiredIds [staffDropStaff]
                        if coerce staffDropStaff.id `Set.member` payInvalidStaffIds
                            then respondWithMoveRosterShiftFailure rosterGroup.id weekOffset "Resolve pay configuration for the selected staff member before adding a roster shift."
                            else respondWithRosterShiftCreateDialogOob staffDropRosterDay staffDropRosterWeek staffDropSlotDefinition staffDropRowIndex emptyRosterShiftDialogValues { rosterShiftSelectedAssignment = Just (StaffAssignment staffDropStaff.id) }

    action currentAction@UpdateRosterWarningPreferenceAction { weekOffset } =
        runBepis currentAction BepisMutationAction do
            ensureManagerRole
            rosterGroup <- resolveRequestedRosterGroup
            case RosterAction.parseToggleRosterWarningsActionParams of
                Left errors -> do
                    let errorMessage = rosterSurfaceRequestErrorMessage errors
                    if isHtmxRequest
                        then respondWithRosterToast errorMessage "app-toast-error"
                        else setErrorMessage errorMessage >> redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
                Right fields -> do
                    _ <- upsertCurrentUserShowRosterWarnings (surfaceFieldValue @Surface.ShowRosterWarnings fields)
                    if isHtmxRequest
                        then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster warning preference saved.")
                        else do
                            setSuccessMessage "Roster warning preference saved."
                            redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@UpdateRosterWageEstimatePreferenceAction { weekOffset } = runBepis currentAction BepisPreferenceAction do
        accessDeniedUnless (hasRole VenueAdmin)
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterWageEstimatesActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)
            Right fields -> do
                _ <- upsertCurrentUserShowWageEstimates (surfaceFieldValue @Surface.ShowWageEstimates fields)
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster wage estimate preference saved.")
                    else do
                        setSuccessMessage "Roster wage estimate preference saved."
                        redirectToPath (rosterWeekUrl weekOffset rosterGroup.id)

    action currentAction@NewRosterSlotDialogAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterDay, rosterWeek) <- fetchRosterSlotCreateContext rosterDayId
        authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterWeek slotDefinition
        shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
        if null shiftTypes
            then respondWithRosterToast "Create at least one shift type in Admin > Shift Types before adding roster shifts." "app-toast-error"
            else do
                venueConfig <- fetchVenueConfig
                renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex (defaultRosterShiftDialogValuesForVenue venueConfig)

    action currentAction@EditRosterSlotDialogAction { rosterSlotId } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        rosterSlot <- fetchRosterSlotForEdit rosterSlotId
        authorizeRosterSlotForEdit rosterSlot
        (rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlot
        authorizeRosterSlotEditContext rosterSlot rosterDay rosterWeek
        renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek (rosterShiftDialogValuesFromSlot rosterSlot)

    action currentAction@CreateRosterSlotAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        (rosterDay, rosterWeek) <- fetchRosterSlotCreateContext rosterDayId
        authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterWeek slotDefinition
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        existingSlot <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId rosterDay.id)
            |> filterWhere (#rosterWeekSlotDefinitionId, unpackId slotDefinition.id)
            |> filterWhere (#rowIndex, rowIndex)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOneOrNothing
        validation <- validateRosterShiftDialogSubmission rosterGroupId rosterDay rosterWeek existingSlot rosterShiftDialogSubmissionFromRequest
        case validation of
            Left values -> renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex values
            Right valid -> do
                let newSlot =
                        fromMaybe
                            ( newRecord @RosterSlot
                            |> set #rosterDayId (unpackId rosterDay.id)
                            |> set #rosterWeekSlotDefinitionId (unpackId slotDefinition.id)
                            |> set #slotSortOrder slotDefinition.sortOrder
                            |> set #rowIndex rowIndex
                            )
                            existingSlot
                            |> applyValidatedRosterShift valid
                mutationResult <- saveRosterSlotMutation rosterGroupId rosterWeek rosterDay existingSlot newSlot
                case mutationResult of
                    Left message ->
                        renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex
                            (rosterShiftDialogValuesFromSlot newSlot) { rosterShiftFormError = Just message }
                    Right mutationResult ->
                        respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult "Roster shift saved."

    action currentAction@UpdateRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterSlot <- fetchRosterSlotForEdit rosterSlotId
        authorizeRosterSlotForEdit rosterSlot
        (rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlot
        authorizeRosterSlotEditContext rosterSlot rosterDay rosterWeek
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        if rosterWeek.isLive
            then do
                validation <- validateLiveOpenShiftFill rosterGroupId rosterSlot rosterShiftDialogSubmissionFromRequest
                case validation of
                    Left values -> renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek values
                    Right assignment -> do
                        let updatedSlot = applyRosterShiftAssignment assignment rosterSlot
                        mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot
                        case mutationResult of
                            Left message ->
                                renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek
                                    (rosterShiftDialogValuesFromSlot rosterSlot) { rosterShiftFormError = Just message }
                            Right mutationResult -> do
                                let previousStaffId = mutationResult.liveMutationValue.rosterSlotMutationPreviousStaffId
                                relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek (catMaybes [previousStaffId, updatedSlot.staffId])
                                let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                                respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys False
            else do
                validation <- validateRosterShiftDialogSubmission rosterGroupId rosterDay rosterWeek (Just rosterSlot) rosterShiftDialogSubmissionFromRequest
                case validation of
                    Left values -> renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek values
                    Right valid -> do
                        let updatedSlot = applyValidatedRosterShift valid rosterSlot
                        mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot
                        case mutationResult of
                            Left message ->
                                renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek
                                    (rosterShiftDialogValuesFromSlot updatedSlot) { rosterShiftFormError = Just message }
                            Right mutationResult -> do
                                let RosterSlotMutationResult { rosterSlotMutationPreviousStaffId = previousStaffId, rosterSlotMutationShouldWarnSourceTimesheetUnchanged = shouldWarnSourceTimesheetUnchanged } = mutationResult.liveMutationValue
                                relatedSlots <- fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek (catMaybes [previousStaffId, updatedSlot.staffId])
                                let impactedRowKeys = impactedRowKeysForSlotUpdate previousStaffId updatedSlot relatedSlots
                                respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged

    action currentAction@DeleteRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterSlot <- fetchRosterSlotForEdit rosterSlotId
        authorizeRosterSlotForEdit rosterSlot
        (rosterDay, rosterWeek) <- fetchRosterSlotEditContext rosterSlot
        authorizeRosterSlotDeleteContext rosterDay rosterWeek
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot >>= \case
            Left message -> respondWithMoveRosterShiftFailure rosterGroupId rosterWeek.weekOffset message
            Right mutationResult -> respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult [(rosterSlot.rosterDayId, rosterSlot.rowIndex)] False

rosterShiftDialogSubmissionFromRequest :: (?context :: ControllerContext, ?request :: Request) => RosterShiftDialogSubmission
rosterShiftDialogSubmissionFromRequest =
    RosterShiftDialogSubmission
        { submittedRosterShiftStaffId = paramOrNothing @Text "staffId"
        , submittedRosterShiftStartTime = paramOrNothing @Text "startTime"
        , submittedRosterShiftEndTime = paramOrNothing @Text "endTime"
        , submittedRosterShiftTypeId = paramOrNothing @Text "shiftTypeId"
        , submittedRosterShiftStartOccurrence = paramOrDefault "" "startOccurrence"
        , submittedRosterShiftEndOccurrence = paramOrDefault "" "endOccurrence"
        }

authorizeRosterSlotCreateContext :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RosterWeek -> Int -> IO ()
authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex = do
    ensureRecordInCurrentVenue rosterWeek.venueId
    ensureRosterWeekIsDraftForEdit rosterWeek
    accessDeniedUnless (not rosterDay.isClosed)
    accessDeniedUnless (rowIndex >= 0)

authorizeRosterSlotDefinitionForCreate :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> RosterWeekSlotDefinition -> IO ()
authorizeRosterSlotDefinitionForCreate rosterWeek slotDefinition = do
    accessDeniedUnless (slotDefinition.rosterWeekId == unpackId rosterWeek.id)
    accessDeniedUnless (isNothing slotDefinition.deletedAt)

authorizeRosterSlotForEdit :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> IO ()
authorizeRosterSlotForEdit rosterSlot =
    accessDeniedUnless (isNothing rosterSlot.deletedAt)

authorizeRosterSlotEditContext :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> RosterDay -> RosterWeek -> IO ()
authorizeRosterSlotEditContext rosterSlot rosterDay rosterWeek = do
    ensureRecordInCurrentVenue rosterWeek.venueId
    accessDeniedUnless (not rosterDay.isClosed)
    unless (rosterWeek.isLive && rosterShiftIsOpen rosterSlot) do
        ensureRosterWeekIsDraftForEdit rosterWeek

authorizeRosterSlotDeleteContext :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RosterWeek -> IO ()
authorizeRosterSlotDeleteContext rosterDay rosterWeek = do
    ensureRecordInCurrentVenue rosterWeek.venueId
    ensureRosterWeekIsDraftForEdit rosterWeek
    accessDeniedUnless (not rosterDay.isClosed)

respondWithMoveRosterShiftFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithMoveRosterShiftFailure rosterGroupId weekOffset message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToPath (rosterWeekUrl weekOffset rosterGroupId)

respondWithSilentRosterNoOp :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithSilentRosterNoOp rosterGroupId weekOffset =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled mempty
        else redirectToPath (rosterWeekUrl weekOffset rosterGroupId)

renderRosterShiftDialogForCreate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex values =
    respondHtmlProfiled =<< rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values

respondWithRosterShiftCreateDialogOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterWeekSlotDefinition -> Int -> RosterShiftDialogValues -> IO ()
respondWithRosterShiftCreateDialogOob rosterDay rosterWeek slotDefinition rowIndex values = do
    dialog <- rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {dialog}
        </div>
    |]

renderRosterShiftDialogForEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterSlot -> RosterDay -> RosterWeek -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForEdit rosterSlot _rosterDay rosterWeek values =
    respondHtmlProfiled =<< rosterShiftDialogForEditHtml rosterSlot rosterWeek values

respondToRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> RosterDay -> Int -> LiveMutationResult RosterSlotMutationResult -> Text -> IO ()
respondToRosterSlotMutation rosterGroupId rosterWeek rosterDay rowIndex mutationResult successMessage = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _ -> actorRosterRowFragments [(unpackId rosterDay.id, rowIndex)]
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                mountedProjections
                (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast successMessage))
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)

respondToRosterSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotMove rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _             -> actorRosterRowFragments impactedRowKeys
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterTimelineSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> Bool -> IO ()
respondToRosterTimelineSlotMove rosterGroupId rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged =
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        [ RosterProjectionGridToolbar
        , RosterProjectionGridFrame
        , RosterProjectionStaffPanel
        ]
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterSlotUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    layoutMode <- fetchCurrentRosterLayoutMode
    let mountedProjections =
            rosterGridInnerAndStaffPanelFragments
                <> case rosterLayoutModeValue layoutMode of
                    "day_columns" -> []
                    _             -> actorRosterRowFragments impactedRowKeys
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

sourceTimesheetWarningToast :: (?context :: ControllerContext, ?request :: Request) => Bool -> Blaze.Html
sourceTimesheetWarningToast shouldWarn =
    if shouldWarn
        then renderToastOob ToastBottomCenter (errorToast "A timesheet entry was already created from this roster shift. The timesheet snapshot was not changed. Edit the timesheet entry directly.")
        else mempty

resolveRequestedRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterGroup
resolveRequestedRosterGroup =
    fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")

resolveRosterGroupIdForFragmentRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Id RosterDay -> IO (Id RosterGroup)
resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId = do
    rosterDay <- fetch rosterDayId
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    ensureRecordInCurrentVenue rosterWeek.venueId
    accessDeniedUnless (rosterWeek.weekOffset == weekOffset)
    pure (coerce rosterWeek.rosterGroupId)

respondWithDeleteRosterSlotDropConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> IO ()
respondWithDeleteRosterSlotDropConfirmation rosterSlot =
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {renderAppShellActionForm
                (appShellActionByMarker @DeleteRosterSlotOverlay)
                (rosterDeleteSlotActionRoute (pathTo (DeleteRosterSlotAction rosterSlot.id)))
                    { appShellActionRouteExtraAttrs =
                        [ ("class", "d-none")
                        , dialogAutoSubmitOnceAttr
                        ]
                    }
                mempty}
        </div>
    |]

rosterDeleteSlotActionRoute :: Text -> AppShellActionRoute
rosterDeleteSlotActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

respondWithRemoveRosterRowConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RemoveRosterRowPackingPreview -> IO ()
respondWithRemoveRosterRowConfirmation rosterDay preview =
    if isHtmxRequest
        then respondHtmlProfiled [hsx|
            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
                {confirmationDialog}
                {confirmForm}
            </div>
        |]
        else do
            setErrorMessage (overflowCopy <> " cannot be packed into another column and would be deleted. Confirm from the roster screen before deleting this row.")
            redirectToPath (pathTo RosterWeeksAction)
    where
        confirmFormId = "confirm-remove-roster-row-form" :: Text
        overflowCount = preview.removeRosterRowOverflowCount
        overflowCopy =
            if overflowCount == 1
                then "1 shift"
                else tshow overflowCount <> " shifts"
        confirmForm =
            renderAppShellActionForm
                (appShellActionByMarker @ConfirmRemoveRosterRowOverlay)
                AppShellActionRoute
                    { appShellActionRouteUrl = pathTo (RemoveRosterRowAction rosterDay.id)
                    , appShellActionRouteFields = []
                    , appShellActionRouteCustomHtmx = []
                    , appShellActionRouteStandardUrl = Nothing
                    , appShellActionRouteExtraAttrs =
                        [ ("id", confirmFormId)

                        ]
                    }
                [hsx|<input type="hidden" name="confirmDeletePopulatedRow" value="true" />|]
        confirmationDialog =
            renderDialogOverlay DialogOverlayConfig
                { dialogOverlayTitle = "Delete roster row?"
                , dialogOverlayBody = [hsx|
                    <p class="mb-2">
                        {overflowCopy} cannot be packed into another column and will be deleted.
                    </p>
                    <p class="mb-0 app-muted">
                        Shifts that fit will be moved into the bottom of the remaining columns from left to right.
                    </p>
                |]
                , dialogOverlayStartButtons = []
                , dialogOverlayButtons =
                    [ OverlayButton
                        { overlayButtonLabel = "Cancel"
                        , overlayButtonClass = "btn btn-outline-secondary"
                        , overlayButtonAction = OverlayCloseAction
                        }
                    , OverlayButton
                        { overlayButtonLabel = "Delete row"
                        , overlayButtonClass = "btn btn-danger"
                        , overlayButtonAction = OverlaySubmitFormAction confirmFormId
                        }
                    ]
                , dialogOverlayDialogClass = ""
                }

clearDialogOverlayOob :: Blaze.Html
clearDialogOverlayOob = [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]

currentRosterGridViewMode :: (?request :: Request) => RosterGridViewMode
currentRosterGridViewMode =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayOffset) -> RosterDayTimelineGridView (max 0 (min 6 dayOffset))
        _ -> RosterWeekGridView

currentRosterTimelineDayOffset :: (?request :: Request) => Maybe Int
currentRosterTimelineDayOffset = case currentRosterGridViewMode of
    RosterDayTimelineGridView dayOffset -> Just dayOffset
    RosterWeekGridView                  -> Nothing

buildRosterTimelineTodayUrl :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO Text
buildRosterTimelineTodayUrl rosterGroupId = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    let currentWeekOffset = venueWeekOffsetForDay venueConfig today
        todayDayOffset = fromInteger (Calendar.diffDays today (venueWeekStartDate venueConfig currentWeekOffset))
    pure (rosterDayTimelineUrl currentWeekOffset rosterGroupId (max 0 (min 6 todayDayOffset)))

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId =
    profileActionSpan "roster.page.render" do
        venueConfig <- profileActionSpan "roster.page.fetch_venue_config" fetchVenueConfig
        let weekStartDate = venueWeekStartDate venueConfig weekOffset
        let weekEndDate = Calendar.addDays 6 weekStartDate
        setTitle "Roster"
        rosterGroups <- profileActionSpan "roster.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
        currentRosterGroup <- profileActionSpan "roster.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId))
        _ <- profileActionSpan "roster.page.ensure_week_exists" (ensureRosterWeekExists currentRosterGroup.id weekOffset)
        rosterDataOrNothing <- profileActionSpan "roster.page.fetch_read_model" (fetchVisibleRosterReadModel currentRosterGroup.id weekOffset)
        passkeySetupPrompt <- profileActionSpan "roster.page.passkey_prompt" passkeySetupPromptFromSession
        passkeyStrongAuthenticationRequired <- profileActionSpan "roster.page.passkey_policy" currentUserRequiresMandatoryPasskey
        timelineTodayUrl <- profileActionSpan "roster.page.timeline_today_url" (buildRosterTimelineTodayUrl currentRosterGroup.id)

        case rosterDataOrNothing of
            Just RosterRenderData { rosterWeek, rosterDays, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } ->
                let visibleRosterWeek =
                        if rosterWeek.isLive || hasRole Manager
                            then Just rosterWeek
                            else Nothing
                 in profileActionSpan "roster.page.respond" $
                        respondWithRosterWeekView
                            ShowView
                                { rosterWeek = visibleRosterWeek
                                , rosterDays
                                , weekOffset
                                , rosterGroups
                                , currentRosterGroup
                                , weekStartDate
                                , weekEndDate
                                , assignmentFilters
                                , staffMembers
                                , panelStaff
                                , staffSelfServicePanel
                                , slotNames = orderedSlotNames
                                , shiftTypes
                                , allSlots
                                , slotConflicts
                                , renderIndexes
                                , viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
                                , rosterLayoutMode
                                , rosterEndTimesEnabled
                                , rosterTimePickerStartMinute
                                , rosterTimePickerFinalSelectableMinute
                                , rosterWagePrediction
                                , showWageEstimates
                                , showRosterWarnings
                                , publicHolidays = rosterPublicHolidays
                                , passkeySetupPrompt
                                , passkeyStrongAuthenticationRequired
                                , rosterGridViewMode = currentRosterGridViewMode
                                , rosterTimelineTodayUrl = Just timelineTodayUrl
                                }
            Nothing ->
                error "Roster week should exist after ensureRosterWeekExists"

respondWithRosterWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => ShowView -> IO ()
respondWithRosterWeekView showView =
    profileActionSpan "roster.page.render_response" do
        if isHtmxRequest
            then respondHtmlProfiled (renderRosterWeekShell showView)
            else renderProfiled showView

passkeySetupPromptFromSession :: (?request :: Request) => IO (Maybe PasskeySetupPromptMode)
passkeySetupPromptFromSession =
    fmap (>>= passkeySetupPromptModeFromValue) (getSessionAndClear @Text passkeySetupPromptSessionKey)

renderRosterWeekOverviewFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Id RosterGroup -> IO Blaze.Html
renderRosterWeekOverviewFragment weekOffset rosterGroupId = do
    venueConfig <- fetchVenueConfig
    todayDate <- utctDay <$> getCurrentTime
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let focusDate = initialOverviewFocusDate weekStartDate todayDate
    weekOverviewDays <- profileActionSpan "roster.build_month_overview" (buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate)
    pure (renderWeekOverviewPanelFragment weekOffset rosterGroupId weekStartDate todayDate weekOverviewDays (buildRosterViewCapabilities Nothing))

fetchRelatedSlotsForStaffIdsInRosterWeek :: (?modelContext :: ModelContext) => RosterWeek -> [UUID.UUID] -> IO [RosterSlot]
fetchRelatedSlotsForStaffIdsInRosterWeek rosterWeek staffIds =
    if null staffIds
        then pure []
        else do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                |> fetch
            if null rosterDays
                then pure []
                else query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> filterWhereIn (#staffId, map Just (nub staffIds))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

respondToRosterSlotDefinitionError :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> Text -> IO ()
respondToRosterSlotDefinitionError rosterWeek errorMessage =
    if isHtmxRequest
        then respondWithRosterToast errorMessage "app-toast-error"
        else do
            setErrorMessage errorMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId :: Id RosterGroup))

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?request :: Request) => RosterWeek -> LiveMutationResult value -> Text -> IO ()
respondToRosterSlotDefinitionSuccess rosterWeek mutationResult successMessage =
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                rosterGroupId
                rosterWeek.weekOffset
                mutationResult.liveMutationTouchedResources
                rosterGridInnerAndStaffPanelFragments
                mempty
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWeekUrl rosterWeek.weekOffset rosterGroupId)
    where
        rosterGroupId = coerce rosterWeek.rosterGroupId
