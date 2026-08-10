{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Helper.Controller
import Application.Helper.FrontendContract.AppShell (ConfirmDeleteRosterSlotOverlay,
                                                     ConfirmRemoveRosterRowOverlay,
                                                     CreateRosterShiftOverlay,
                                                     DeleteRosterSlotOverlay,
                                                     UpdateRosterShiftOverlay)
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeySetupPromptMode,
                                                            passkeySetupPromptModeFromValue)
import qualified Application.Helper.FrontendContract.Surface.Interaction as SurfaceInteraction
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError (..),
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceIntentForm)
import Application.Helper.FrontendContract.Surface.Roster (RosterStaffScopeValue (..))
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterNotificationStatusResource)
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
import Application.Helper.WeekBoundaries (startOfWeekFor, venueWeekOffsetForDay,
                                          venueWeekStartDate)
import qualified Application.RosterNotification as Notification
import Application.RosterPublication (fetchRosterWeekIsPublished)
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
import Data.Maybe (catMaybes, fromJust, fromMaybe, isJust, mapMaybe)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time (getCurrentTime, utctDay)
import qualified Data.Time.Calendar as Calendar
import Data.Time.LocalTime (TimeOfDay)
import qualified Data.UUID as UUID
import Network.HTTP.Types.Status (status400)
import qualified Network.Wai as Wai
import qualified Text.Blaze.Html as Blaze
import qualified Text.Read as TextRead
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.Controller.Sessions (passkeySetupPromptSessionKey)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.DateRange (RosterDayRowRemovalPreview (..),
                                  RosterWindow (..), RosterWindowLane (..),
                                  fetchRosterWindow,
                                  previewRemoveRosterDayRowByLanes,
                                  projectedRosterDayId,
                                  resolveRosterLaneReference,
                                  rosterPlanningWeekForDay)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.DropWorkflow
import Web.RosterWeeks.Filters
import Web.RosterWeeks.FrontendSurface (rosterDuplicateShiftIntentForm,
                                        rosterMoveShiftIntentForm,
                                        rosterTimelineMoveShiftIntentForm)
import Web.RosterWeeks.Mutations
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Paths (rosterCopyWeekUrl, rosterTimelineWindowUrl,
                              rosterWindowUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondWithRosterContent,
                                  respondWithRosterContentError,
                                  respondWithRosterContentUpdate,
                                  respondWithRosterDialogOverlay,
                                  respondWithRosterFragments,
                                  respondWithRosterFragmentsUpdate,
                                  respondWithRosterOwnHighlightPreferenceUpdate,
                                  respondWithRosterResourceInvalidation,
                                  respondWithRosterToast)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.ShiftWorkflow
import Web.RosterWeeks.StaffOptions (buildRosterStaffOptionStates,
                                     fetchRosterShiftDialogStaff,
                                     fetchStaffPayConfigurationRequiredIds)
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.NotificationDialog (renderRosterNotificationConfirmation)
import Web.View.RosterWeeks.OccurrenceDialog
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.ShiftDialog
import Web.View.RosterWeeks.Show (renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderrosterStaffPanelLiveFragment)
import Web.View.RosterWeeks.Timeline (renderRosterDayTimelineContent)

rosterSurfaceRequestErrorMessage :: [SurfaceRequestFieldError] -> Text
rosterSurfaceRequestErrorMessage errors =
    "Check the roster controls: " <> surfaceRequestFieldErrorsMessage errors

respondRosterNotificationBadRequest :: (?request :: Request) => Text -> IO value
respondRosterNotificationBadRequest message = do
    respondAndExit (Wai.responseLBS status400 [("Content-Type", "text/plain")] (cs message))
    error "unreachable"

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
    | not RosterAction.toggleRosterStaffScopeActionParamsPresent = Right RosterStaffPanelCurrentGroup
    | otherwise =
        case RosterAction.parseToggleRosterStaffScopeActionParams of
            Left errors -> Left (rosterSurfaceRequestErrorMessage errors)
            Right fields ->
                case surfaceFieldValue @Surface.StaffScope fields of
                    RosterStaffAllVenue     -> Right RosterStaffPanelAllVenue
                    RosterStaffCurrentGroup -> Right RosterStaffPanelCurrentGroup

respondWithRosterCopyFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterCopyFailure rosterGroupId targetWeekOffset message =
    if isHtmxRequest
        then respondWithRosterToast message "app-toast-error"
        else do
            setErrorMessage message
            redirectToRosterWindow targetWeekOffset rosterGroupId

respondWithRosterCopyOccurrenceDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Int -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> IO ()
respondWithRosterCopyOccurrenceDialog rosterGroupId sourceWeekOffset targetWeekOffset startIsRepeated endIsRepeated selections =
    if not isHtmxRequest
        then respondWithRosterCopyFailure rosterGroupId targetWeekOffset "Choose repeated-time occurrences from the roster copy dialog."
        else do
            venueConfig <- fetchVenueConfig
            let dialog = renderRosterWeekCopyOccurrenceDialog
                    (rosterCopyWeekUrl (venueWeekStartDate venueConfig sourceWeekOffset) (venueWeekStartDate venueConfig targetWeekOffset) rosterGroupId)
                    venueConfig.rosterCalendarRevision
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

rosterMutationMountedProjections :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterMutationProjection -> IO [RosterProjectionFragment]
rosterMutationMountedProjections mutationProjection =
    flip rosterMutationProjectionFragments mutationProjection <$> fetchCurrentRosterLayoutMode

instance Controller RosterWeeksController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        markStaleRosterCalendarResponseForRefresh

    action currentAction@RosterWeeksAction = runBepis currentAction BepisPageAction do
        venueConfig <- fetchVenueConfig
        today <- utctDay <$> getCurrentTime
        let currentWeekOffset = venueWeekOffsetForDay venueConfig today
        currentRosterGroup <- resolveRequestedRosterGroup
        let currentWeekPath = case paramOrNothing @Text "rosterView" of
                Just "timeline" -> rosterTimelineWindowUrl today currentRosterGroup.id
                _ -> rosterWindowUrl today currentRosterGroup.id

        if isHtmxRequest
            then case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
                (Just "timeline", Nothing) -> do
                    setHeader ("HX-Redirect", cs currentWeekPath)
                    respondHtmlProfiled mempty
                _ -> do
                    setHtmxPushUrl currentWeekPath
                    renderRosterWeekPage currentWeekOffset currentRosterGroup.id
            else redirectToPath currentWeekPath

    action currentAction@ShowRosterWindowAction { anchorDate } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        venueConfig <- fetchVenueConfig
        let windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate
        let weekOffset = venueWeekOffsetForDay venueConfig windowStart
        renderRosterWeekPage weekOffset rosterGroup.id

    action currentAction@ShowRosterWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        venueConfig <- fetchVenueConfig
        maybeLegacyWeek <- query @RosterWeek
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhere (#weekOffset, weekOffset)
            |> fetchOneOrNothing
        maybeLegacyDate <- case maybeLegacyWeek of
            Nothing -> pure Nothing
            Just legacyWeek -> query @RosterDay
                |> filterWhere (#rosterWeekId, Just (unpackId legacyWeek.id))
                |> orderByAsc #operationalDate
                |> fetchOneOrNothing
                |> fmap (fmap (.operationalDate))
        let anchorDate = fromMaybe (venueWeekStartDate venueConfig weekOffset) maybeLegacyDate
        redirectToPath (rosterWindowUrl anchorDate rosterGroup.id)

    action currentAction@ShowRosterDayTimelineAction { weekOffset, rosterDayId } = runBepis currentAction BepisPageAction do
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> do
                setErrorMessage "Roster week not found."
                redirectToRosterWindow weekOffset rosterGroup.id
            Just rosterData -> do
                let canViewTimeline = maybe False (.isLive) rosterData.rosterWeek || hasRole Manager
                accessDeniedUnless canViewTimeline
                case find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays of
                    Nothing -> do
                        setErrorMessage "Roster day not found."
                        redirectToRosterWindow weekOffset rosterGroup.id
                    Just rosterDay ->
                        redirectToPath (rosterTimelineWindowUrl rosterDay.operationalDate rosterGroup.id)

    action currentAction@ShowRosterDayTimelineContentFragmentAction { anchorDate, rosterDayId } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        maybeRosterData <- fetchVisibleRosterReadModel rosterGroup.id weekOffset
        case maybeRosterData of
            Nothing -> respondHtmlProfiled mempty
            Just rosterData -> do
                let canViewTimeline = maybe False (.isLive) rosterData.rosterWeek || hasRole Manager
                accessDeniedUnless canViewTimeline
                let maybeRosterDay = find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays
                respondHtmlProfiled (maybe mempty (renderRosterDayTimelineContent Nothing rosterData) maybeRosterDay)

    action currentAction@ShowRosterWeekOverviewFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment weekOffset rosterGroup.id

    action currentAction@ShowRosterWeekContentFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        respondWithRosterContent rosterGroup.id weekOffset

    action currentAction@ShowRosterWeekGridToolbarFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        toolbarHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridToolbar
        respondHtmlProfiled (fromMaybe mempty toolbarHtml)

    action currentAction@ShowRosterWeekGridFrameFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        frameHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionGridFrame
        respondHtmlProfiled (fromMaybe mempty frameHtml)

    action currentAction@ShowRosterWeekDayColumnsFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayColumns
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekDayRailFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionDayRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekWageRailFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionWageRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekSlotsGridFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        fragmentHtml <- renderVisibleRosterReadModelFragment rosterGroup.id weekOffset RosterProjectionSlotsGrid
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekStaffPanelFragmentAction { anchorDate } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroup <- resolveRequestedRosterGroup
        panelScope <- case parseRosterStaffPanelScope of
            Left errorMessage -> setErrorMessage errorMessage >> pure RosterStaffPanelCurrentGroup
            Right scope -> pure scope
        panelModel <- fetchVisibleRosterStaffPanelRenderModel panelScope rosterGroup.id weekOffset
        respondHtmlProfiled (renderrosterStaffPanelLiveFragment panelModel)

    action currentAction@ShowRosterNotificationConfirmationAction { rosterWeekId } = runBepis currentAction BepisFragmentAction do
        ensureManagerRole
        notificationFields <- case RosterAction.parseShowRosterNotificationConfirmationActionParams of
            Left errors -> respondRosterNotificationBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> pure fields
        accessDeniedUnless (surfaceFieldValue @Surface.NotificationRosterWeekId notificationFields == unpackId rosterWeekId)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        accessDeniedUnless =<< fetchRosterWeekIsPublished rosterWeek
        rosterGroup <- query @RosterGroup
            |> filterWhere (#id, Id rosterWeek.rosterGroupId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOne
        venue <- fetch currentVenueId
        venueConfig <- fetchVenueConfig
        audience <- Notification.fetchRosterNotificationAudience venue rosterGroup
        latestRun <- Notification.fetchLatestRosterNotificationRunSummary rosterWeek
        let weekStart = venueWeekStartDate venueConfig rosterWeek.weekOffset
        respondHtmlProfiled (renderRosterNotificationConfirmation venue rosterGroup rosterWeek weekStart audience latestRun)

    action currentAction@CreateRosterNotificationRunAction { rosterWeekId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        notificationFields <- case RosterAction.parseCreateRosterNotificationRunActionParams of
            Left errors -> respondRosterNotificationBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> pure fields
        accessDeniedUnless (surfaceFieldValue @Surface.NotificationRosterWeekId notificationFields == unpackId rosterWeekId)
        rosterWeek <- fetch rosterWeekId
        ensureRecordInCurrentVenue rosterWeek.venueId
        accessDeniedUnless =<< fetchRosterWeekIsPublished rosterWeek
        let rosterGroupId = Id rosterWeek.rosterGroupId
        runResult <- Notification.createRosterNotificationRunUnlessActive currentUser rosterWeek
        case runResult of
            Notification.RosterNotificationRunAlreadyActive ->
                if isHtmxRequest
                    then respondWithRosterFragments
                        rosterGroupId
                        rosterWeek.weekOffset
                        [RosterProjectionStaffPanel]
                        [hsx|
                            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                            {renderToastOob ToastBottomCenter (errorToast "Roster email delivery is already in progress.")}
                        |]
                    else do
                        setErrorMessage "Roster email delivery is already in progress."
                        redirectToRosterWindow rosterWeek.weekOffset rosterGroupId
            Notification.RosterNotificationRunHasNoEligibleRecipients ->
                if isHtmxRequest
                    then respondWithRosterFragments
                        rosterGroupId
                        rosterWeek.weekOffset
                        [RosterProjectionStaffPanel]
                        [hsx|
                            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                            {renderToastOob ToastBottomCenter (errorToast "No eligible recipients are available.")}
                        |]
                    else do
                        setErrorMessage "No eligible recipients are available."
                        redirectToRosterWindow rosterWeek.weekOffset rosterGroupId
            Notification.RosterNotificationRunCreated run -> do
                recipients <- Notification.decodeRosterNotificationRecipients run
                skippedRecipients <- Notification.decodeRosterNotificationSkippedRecipients run
                let queuedCount = length recipients
                let skippedCount = length skippedRecipients
                let successMessage =
                        "Roster email queued for "
                            <> Notification.rosterNotificationRecipientCountLabel queuedCount
                            <> ". "
                            <> tshow skippedCount
                            <> " skipped"
                            <> "."
                if isHtmxRequest
                    then respondWithRosterResourceInvalidation
                        rosterGroupId
                        rosterWeek.weekOffset
                        (Set.singleton (rosterNotificationStatusResource (unpackId rosterGroupId) run.weekStart (Calendar.addDays 7 run.weekStart)))
                        [RosterProjectionStaffPanel]
                        [hsx|
                            <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
                            {renderToastOob ToastBottomCenter (successToast successMessage)}
                        |]
                    else do
                        setSuccessMessage successMessage
                        redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

    action currentAction@ShowRosterWeekDaySectionFragmentAction { anchorDate, rosterDayId } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        daySectionHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action currentAction@ShowRosterWeekRowFragmentAction { anchorDate, rosterDayId, rowIndex } = runBepis currentAction BepisFragmentAction do
        weekOffset <- rosterWeekOffsetForAnchor anchorDate
        rosterGroupId <- resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId
        rowHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action currentAction@UpdateRosterAssignmentFiltersAction = runBepis currentAction BepisPreferenceAction do
        weekOffset <- rosterActionWeekOffset
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterAssignmentFiltersActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToRosterWindow weekOffset rosterGroup.id
            Right fields -> do
                setRosterAssignmentFiltersSession RosterAssignmentFilters
                    { hideStaffAtIdealShifts = surfaceFieldValue @Surface.HideStaffAtIdealShifts fields
                    , hideStaffUnavailable = surfaceFieldValue @Surface.HideStaffUnavailable fields
                    , hideStaffOnApprovedLeave = surfaceFieldValue @Surface.HideStaffOnApprovedLeave fields
                    , hideStaffAlreadyAssignedToday = surfaceFieldValue @Surface.HideStaffAlreadyAssignedToday fields
                    }
                respondHtmlProfiled mempty

    action currentAction@CreateRosterWeekAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterMutationWeekOffset
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        result <- ensureRosterWeekExistsMutation rosterGroup.id weekOffset
        case result of
            Left message -> respondToRosterSlotDefinitionError rosterGroup.id weekOffset message
            Right mutationResult -> do
                let (rosterWeek, wasCreated) = mutationResult.liveMutationValue
                let successMessage =
                        if wasCreated
                            then "Roster week created successfully"
                            else "Roster week already exists."
                targetPath <- rosterWindowUrlForOffset rosterWeek.weekOffset rosterGroup.id
                if isHtmxRequest
                    then do
                        setHtmxPushUrl targetPath
                        respondWithRosterContentUpdate rosterGroup.id rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
                    else do
                        setSuccessMessage successMessage
                        redirectToPath targetPath

    action currentAction@CopyRosterWeekAction = runBepis currentAction BepisMutationAction do
        (sourceWeekOffset, targetWeekOffset) <- rosterCopyActionWeekOffsets
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
                        redirectToRosterWindow targetWeekOffset rosterGroup.id
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
                                redirectToRosterWindow targetWeekOffset rosterGroup.id
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
                                        targetPath <- rosterWindowUrlForOffset targetWeekOffset rosterGroup.id
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
        requestedWeekOffset <- rosterActionWeekOffset
        (rosterWeek, rosterGroupId) <-
            if unpackId rosterWeekId == UUID.nil
                then do
                    rosterGroup <- resolveRequestedRosterGroup
                    pure
                        ( newRecord @RosterWeek
                            |> set #venueId (unpackId currentVenueId)
                            |> set #rosterGroupId (unpackId rosterGroup.id)
                            |> set #weekOffset requestedWeekOffset
                            |> set #isLive False
                        , rosterGroup.id
                        )
                else do
                    persistedWeek <- fetch rosterWeekId
                    ensureRecordInCurrentVenue persistedWeek.venueId
                    accessDeniedUnless (persistedWeek.weekOffset == requestedWeekOffset)
                    pure (persistedWeek, coerce persistedWeek.rosterGroupId)
        windowStart <- rosterWindowStartForOffset rosterWeek.weekOffset
        let targetPath = rosterWindowUrl windowStart rosterGroupId
        case RosterAction.parseToggleRosterWeekLiveStatusActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterContentError rosterGroupId rosterWeek.weekOffset errorMessage
                    else do
                        setErrorMessage errorMessage
                        redirectToPath targetPath
            Right fields -> do
                let nextLiveStatus = surfaceFieldValue @Surface.IsLive fields
                mutationResult <- toggleRosterWeekLiveStatusMutation rosterGroupId rosterWeek nextLiveStatus
                case mutationResult of
                    Left errorMessage ->
                        if isHtmxRequest
                            then respondWithRosterContentError rosterGroupId rosterWeek.weekOffset errorMessage
                            else do
                                setErrorMessage errorMessage
                                redirectToPath targetPath
                    Right mutationResult -> do
                        let successMessage =
                                if nextLiveStatus
                                    then "Roster window Published. Timesheet suggestions are available immediately."
                                    else "Roster window returned to Draft. Timesheet suggestions are hidden."
                        if isHtmxRequest
                            then do
                                setHtmxPushUrl targetPath
                                respondWithRosterContentUpdate rosterGroupId rosterWeek.weekOffset mutationResult.liveMutationTouchedResources successMessage
                            else do
                                setSuccessMessage successMessage
                                redirectToPath targetPath

    action currentAction@CreateRosterWeekSlotDefinitionAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        venueConfig <- fetchVenueConfig
        window <- fetchRosterWindow currentVenueId rosterGroup.id (venueWeekStartDate venueConfig weekOffset)
        let existingNames = map (.rosterWindowLaneName) window.rosterWindowLanes
            submittedName = Text.strip (paramOrDefault @Text "" "name")
            requestedSlotName = if Text.null submittedName
                then Right (firstAvailableDefaultName existingNames)
                else normalizeRosterSlotDefinitionName submittedName
        case requestedSlotName of
            Left errorMessage -> respondToRosterSlotDefinitionError rosterGroup.id weekOffset errorMessage
            Right laneName -> do
                result <- appendRosterWindowLaneMutation rosterGroup.id weekOffset laneName
                case result of
                    Left errorMessage -> respondToRosterSlotDefinitionError rosterGroup.id weekOffset errorMessage
                    Right mutationResult -> respondToRosterSlotDefinitionSuccess rosterGroup.id weekOffset mutationResult "Roster column added."

    action currentAction@DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterLane <- query @RosterLane
            |> filterWhere (#id, rosterWeekSlotDefinitionId)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOne
        rosterDay <- query @RosterDay
            |> filterWhere (#id, Id rosterLane.rosterDayId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOne
        accessDeniedUnless (rosterDay.publicationState == Draft)
        venueConfig <- fetchVenueConfig
        let weekOffset = venueWeekOffsetForDay venueConfig rosterDay.operationalDate
            rosterGroupId = Id rosterDay.rosterGroupId
        result <- removeRosterWindowLaneMutation rosterGroupId weekOffset rosterLane.id
        case result of
            Left errorMessage -> respondToRosterSlotDefinitionError rosterGroupId weekOffset errorMessage
            Right mutationResult -> respondToRosterSlotDefinitionSuccess rosterGroupId weekOffset mutationResult "Roster column removed."

    action currentAction@SortRosterWeekAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        repackRosterWindowMutation rosterGroup.id weekOffset >>= \case
            Left errorMessage -> respondToRosterSlotDefinitionError rosterGroup.id weekOffset errorMessage
            Right mutationResult ->
                if isHtmxRequest
                    then
                        respondWithRosterResourceInvalidation
                            rosterGroup.id
                            weekOffset
                            mutationResult.liveMutationTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            clearDialogOverlayOob
                    else do
                        setSuccessMessage "Roster sorted."
                        redirectToRosterWindow weekOffset rosterGroup.id

    action currentAction@ToggleRosterDayClosedAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetchRosterDayForMutation rosterDayId
        rosterWeek <- rosterPlanningWeekForDay rosterDay
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        let nextClosedState = not rosterDay.isClosed

        toggleRosterDayClosedMutation rosterGroupId rosterWeek rosterDay nextClosedState closedRosterDayRows >>= \case
            Left errorMessage -> respondToRosterSlotDefinitionError rosterGroupId rosterWeek.weekOffset errorMessage
            Right mutationResult -> do
                let successMessage =
                        if nextClosedState
                            then "Roster day marked closed."
                            else "Roster day reopened."
                targetPath <- rosterWindowUrlForOffset rosterWeek.weekOffset rosterGroupId
                if isHtmxRequest
                    then do
                        mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
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

        rosterDay <- fetchRosterDayForMutation rosterDayId
        rosterWeek <- rosterPlanningWeekForDay rosterDay
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        activeLanes <- query @RosterLane
            |> filterWhere (#rosterDayId, unpackId rosterDay.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch

        if null activeLanes
            then do
                let errorMessage = "Add at least one active slot to the selected roster group before adding roster rows."
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToRosterWindow rosterWeek.weekOffset rosterGroupId
            else
                addRosterDayRowMutation rosterGroupId rosterWeek rosterDay >>= \case
                    Left errorMessage -> respondToRosterSlotDefinitionError rosterGroupId rosterWeek.weekOffset errorMessage
                    Right mutationResult ->
                        if isHtmxRequest
                            then do
                                mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
                                respondWithRosterResourceInvalidation
                                    rosterGroupId
                                    rosterWeek.weekOffset
                                    mutationResult.liveMutationTouchedResources
                                    mountedProjections
                                    clearDialogOverlayOob
                            else do
                                setSuccessMessage "Roster row added."
                                redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

    action currentAction@RemoveRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetchRosterDayForMutation rosterDayId
        rosterWeek <- rosterPlanningWeekForDay rosterDay
        ensureRecordInCurrentVenue rosterWeek.venueId
        ensureRosterWeekIsDraftForEdit rosterWeek

        when rosterDay.isClosed do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

        let rowCount = rosterDay.rowCount
        let confirmDeletePopulatedRow = paramOrDefault @Text "false" "confirmDeletePopulatedRow" == "true"

        when (rowCount <= minimumOpenRosterRows) do
            let rosterGroupId = coerce rosterWeek.rosterGroupId
            let errorMessage = "Roster days must keep at least two rows."
            if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

        let rosterGroupId = coerce rosterWeek.rosterGroupId
        preview <- previewRemoveRosterDayRowByLanes rosterDay
        if preview.laneRowRemovalOverflowCount > 0 && not confirmDeletePopulatedRow
            then respondWithRemoveRosterRowConfirmation rosterDay preview
            else
                removeRosterDayRowByLanesMutation rosterGroupId rosterWeek rosterDay >>= \case
                    Left errorMessage -> respondToRosterSlotDefinitionError rosterGroupId rosterWeek.weekOffset errorMessage
                    Right mutationResult ->
                        if isHtmxRequest
                            then do
                                mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
                                respondWithRosterResourceInvalidation
                                    rosterGroupId
                                    rosterWeek.weekOffset
                                    mutationResult.liveMutationTouchedResources
                                    mountedProjections
                                    clearDialogOverlayOob
                            else do
                                setSuccessMessage "Roster row removed."
                                redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

    action currentAction@UpdateRosterLayoutPreferenceAction = runBepis currentAction BepisPreferenceAction do
        weekOffset <- rosterActionWeekOffset
        rosterGroup <- resolveRequestedRosterGroup
        let requestedLayoutMode =
                case RosterIntent.parseSetRosterLayoutModeIntentParams of
                    Left errors -> Left (rosterSurfaceRequestErrorMessage errors)
                    Right fields ->
                        Right (surfaceFieldValue @Surface.RosterLayoutMode fields)
        case requestedLayoutMode of
            Left requestError -> do
                let errorMessage = requestError
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToRosterWindow weekOffset rosterGroup.id
            Right layoutMode -> do
                _ <- upsertCurrentUserRosterLayoutMode layoutMode
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster layout preference saved.")
                    else do
                        setSuccessMessage "Roster layout preference saved."
                        redirectToRosterWindow weekOffset rosterGroup.id

    action currentAction@MoveRosterShiftToSlotAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
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
                            Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot (param @Calendar.Day "anchorDate") (param @Int "rosterCalendarRevision")
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
                                        anchorDate <- rosterWindowStartForOffset weekOffset
                                        let intentForm = rosterMoveShiftIntentForm anchorDate rosterGroup.id (surfaceFieldValue @Surface.RosterCalendarRevision fields) sourceToken targetToken Nothing Nothing
                                        let occurrenceFields = (surfaceFieldNameFrom @Surface.CopyStartOccurrence fields, surfaceFieldNameFrom @Surface.CopyEndOccurrence fields)
                                        case boundaryResolution of
                                            RosterDayDropBoundaryFailure repeatedEndpoints failure ->
                                                respondWithRosterSlotCopyBoundaryFailure rosterGroup.id weekOffset "move" intentForm occurrenceFields repeatedEndpoints selections failure
                                            RosterDayDropBoundaryReady targetRosterWeek copiedBoundariesSlot -> do
                                                let updatedSlot = copiedBoundariesSlot
                                                        |> set #rosterDayId (unpackId targetRosterDay.id)
                                                        |> set #rosterLaneId (unpackId targetSlotDefinition.id)
                                                        |> set #rosterWeekSlotDefinitionId (targetSlotDefinition.legacyRosterWeekSlotDefinitionId <|> sourceSlot.rosterWeekSlotDefinitionId)
                                                        |> set #slotSortOrder targetSlotDefinition.sortOrder
                                                        |> set #rowIndex targetRowIndex
                                                mutationResult <- moveRosterSlotMutation rosterGroup.id targetRosterWeek sourceRosterDay targetRosterDay sourceSlot updatedSlot
                                                case mutationResult of
                                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                                    Right mutationResult -> do
                                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                                        let impactedRows = nub [(sourceSlot.rosterDayId, sourceSlot.rowIndex), (unpackId targetRosterDay.id, targetRowIndex)]
                                                        respondToRosterSlotMove rosterGroup.id targetRosterWeek mutationResult impactedRows shouldWarnSourceTimesheetUnchanged

    action currentAction@MoveRosterTimelineShiftAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
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
                        anchorDate <- rosterWindowStartForOffset weekOffset
                        let calendarRevision = surfaceFieldValue @Surface.RosterCalendarRevision fields
                        let intentForm = rosterTimelineMoveShiftIntentForm anchorDate rosterGroup.id timelineTargetRosterDay.operationalDate calendarRevision sourceToken targetToken Nothing
                        let startOccurrenceField = surfaceFieldNameFrom @Surface.TimelineStartOccurrence fields
                        let occurrenceFields = (startOccurrenceField, startOccurrenceField)
                        case boundaryResolution of
                            RosterTimelineDropInvalid message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                            RosterTimelineDropBoundaryFailure repeatedEndpoints selections failure ->
                                respondWithRosterSlotCopyBoundaryFailure rosterGroup.id weekOffset "move" intentForm occurrenceFields repeatedEndpoints selections failure
                            RosterTimelineDropBoundaryReady rosterWeek boundaries -> do
                                let updatedSlot = timelineSourceSlot
                                        |> set #rosterDayId (unpackId timelineTargetRosterDay.id)
                                        |> set #rosterLaneId (unpackId timelineTargetSlotDefinition.id)
                                        |> set #rosterWeekSlotDefinitionId (timelineTargetSlotDefinition.legacyRosterWeekSlotDefinitionId <|> timelineSourceSlot.rosterWeekSlotDefinitionId)
                                        |> set #slotSortOrder timelineTargetSlotDefinition.sortOrder
                                        |> set #rowIndex timelineTargetRowIndex
                                        |> applyRosterSlotBoundaries boundaries
                                mutationResult <- moveRosterSlotMutation rosterGroup.id rosterWeek timelineSourceRosterDay timelineTargetRosterDay timelineSourceSlot updatedSlot
                                case mutationResult of
                                    Left message -> respondWithMoveRosterShiftFailure rosterGroup.id weekOffset message
                                    Right mutationResult -> do
                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                        respondToRosterTimelineSlotMove rosterGroup.id rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged

    action currentAction@DuplicateRosterShiftToDayAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
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
                            Right rosterSlot -> respondWithDeleteRosterSlotDropConfirmation rosterSlot (param @Calendar.Day "anchorDate") (param @Int "rosterCalendarRevision")
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
                                        anchorDate <- rosterWindowStartForOffset weekOffset
                                        let intentForm = rosterDuplicateShiftIntentForm anchorDate rosterGroup.id (surfaceFieldValue @Surface.RosterCalendarRevision fields) sourceToken targetToken Nothing Nothing
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
                                                                |> set #rosterLaneId (unpackId targetSlotDefinition.id)
                                                                |> set #rosterWeekSlotDefinitionId (targetSlotDefinition.legacyRosterWeekSlotDefinitionId <|> sourceSlot.rosterWeekSlotDefinitionId)
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

    action currentAction@DropRosterStaffAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
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
                        mutationResult <- updateRosterSlotMutation rosterGroup.id staffDropRosterWeek staffDropRosterDay staffDropSlot updatedSlot False
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

    action currentAction@UpdateRosterWarningPreferenceAction = runBepis currentAction BepisMutationAction do
        weekOffset <- rosterActionWeekOffset
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterWarningsActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow weekOffset rosterGroup.id
            Right fields -> do
                _ <- upsertCurrentUserShowRosterWarnings (surfaceFieldValue @Surface.ShowRosterWarnings fields)
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster warning preference saved.")
                    else do
                        setSuccessMessage "Roster warning preference saved."
                        redirectToRosterWindow weekOffset rosterGroup.id

    action currentAction@UpdateRosterWageEstimatePreferenceAction = runBepis currentAction BepisPreferenceAction do
        weekOffset <- rosterActionWeekOffset
        accessDeniedUnless (hasRole VenueAdmin)
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterWageEstimatesActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow weekOffset rosterGroup.id
            Right fields -> do
                _ <- upsertCurrentUserShowWageEstimates (surfaceFieldValue @Surface.ShowWageEstimates fields)
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate rosterGroup.id weekOffset rosterGridStructuralAndStaffPanelFragments (successToast "Roster wage estimate preference saved.")
                    else do
                        setSuccessMessage "Roster wage estimate preference saved."
                        redirectToRosterWindow weekOffset rosterGroup.id

    action currentAction@UpdateRosterOwnLiveShiftHighlightPreferenceAction = runBepis currentAction BepisPreferenceAction do
        weekOffset <- rosterActionWeekOffset
        rosterGroup <- resolveRequestedRosterGroup
        case RosterAction.parseToggleRosterOwnLiveShiftHighlightActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow weekOffset rosterGroup.id
            Right fields -> do
                _ <- upsertCurrentUserHighlightOwnLiveShifts (surfaceFieldValue @Surface.HighlightOwnLiveShifts fields)
                if isHtmxRequest
                    then respondWithRosterOwnHighlightPreferenceUpdate rosterGroup.id weekOffset (successToast "Own Published-shift highlight preference saved.")
                    else do
                        setSuccessMessage "Own Published-shift highlight preference saved."
                        redirectToRosterWindow weekOffset rosterGroup.id

    action currentAction@NewRosterSlotDialogAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        rosterDay <- fetchRosterDayForMutation rosterDayId
        rosterWeek <- rosterPlanningWeekForDay rosterDay
        authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterDayId rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition
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
        rosterDay <- fetchRosterDayForMutation rosterDayId
        rosterWeek <- rosterPlanningWeekForDay rosterDay
        requireRosterShiftCalendarAppShellContext (parseAppShellActionParams @CreateRosterShiftOverlay)
        authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterDayId rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        existingSlot <- query @RosterSlot
            |> filterWhere (#rosterDayId, unpackId rosterDay.id)
            |> filterWhere (#rosterLaneId, unpackId slotDefinition.id)
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
                            |> set #rosterLaneId (unpackId slotDefinition.id)
                            |> set #rosterWeekSlotDefinitionId slotDefinition.legacyRosterWeekSlotDefinitionId
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
        requireRosterShiftCalendarAppShellContext (parseAppShellActionParams @UpdateRosterShiftOverlay)
        authorizeRosterSlotEditContext rosterSlot rosterDay rosterWeek
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        if rosterWeek.isLive
            then do
                validation <- validateLiveOpenShiftFill rosterGroupId rosterSlot rosterShiftDialogSubmissionFromRequest
                case validation of
                    Left values -> renderRosterShiftDialogForEdit rosterSlot rosterDay rosterWeek values
                    Right assignment -> do
                        let updatedSlot = applyRosterShiftAssignment assignment rosterSlot
                        mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot True
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
                        mutationResult <- updateRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot updatedSlot False
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
        requireRosterSlotMutationContext rosterWeek
        authorizeRosterSlotDeleteContext rosterDay rosterWeek
        let rosterGroupId = coerce rosterWeek.rosterGroupId
        deleteRosterSlotMutation rosterGroupId rosterWeek rosterDay rosterSlot >>= \case
            Left message -> respondWithMoveRosterShiftFailure rosterGroupId rosterWeek.weekOffset message
            Right mutationResult -> respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult [(rosterSlot.rosterDayId, rosterSlot.rowIndex)] False

requireRosterShiftCalendarAppShellContext :: (?context :: ControllerContext, ?request :: Request) => Either [SurfaceRequestFieldError] fields -> IO ()
requireRosterShiftCalendarAppShellContext requestFields =
    case requestFields of
        Right _ -> pure ()
        Left errors -> do
            let contextErrors = filter ((`elem` ["anchorDate", "rosterCalendarRevision"]) . (.surfaceRequestFieldErrorName)) errors
            unless (null contextErrors) do
                setErrorMessage (surfaceRequestFieldErrorsMessage contextErrors)
                accessDeniedUnless False

requireRosterSlotMutationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWeek -> IO ()
requireRosterSlotMutationContext rosterWeek = do
    venueConfig <- fetchVenueConfig
    let anchorDate = param @Calendar.Day "anchorDate"
    let calendarRevision = param @Int "rosterCalendarRevision"
    accessDeniedUnless (venueWeekOffsetForDay venueConfig anchorDate == rosterWeek.weekOffset)
    requireCurrentRosterCalendarRevision venueConfig calendarRevision

requireCurrentRosterCalendarRevision :: (?context :: ControllerContext, ?request :: Request) => VenueConfig -> Int -> IO ()
requireCurrentRosterCalendarRevision venueConfig expectedRevision =
    when (expectedRevision /= venueConfig.rosterCalendarRevision) do
        setHeader ("HX-Refresh", "true")
        setErrorMessage "The roster calendar changed. Review the refreshed window and try again."

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

authorizeRosterSlotCreateContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> Int -> IO ()
authorizeRosterSlotCreateContext rosterDay rosterWeek rowIndex = do
    ensureRecordInCurrentVenue rosterWeek.venueId
    ensureRosterWeekIsDraftForEdit rosterWeek
    accessDeniedUnless (not rosterDay.isClosed)
    accessDeniedUnless (rowIndex >= 0)

authorizeRosterSlotDefinitionForCreate :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RosterLane -> IO ()
authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition = do
    accessDeniedUnless (slotDefinition.rosterDayId == unpackId rosterDay.id)
    accessDeniedUnless (isNothing slotDefinition.deletedAt)

authorizeRosterSlotForEdit :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> IO ()
authorizeRosterSlotForEdit rosterSlot =
    accessDeniedUnless (isNothing rosterSlot.deletedAt)

authorizeRosterSlotEditContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterSlot -> RosterDay -> RosterWeek -> IO ()
authorizeRosterSlotEditContext rosterSlot rosterDay rosterWeek = do
    ensureRecordInCurrentVenue rosterWeek.venueId
    accessDeniedUnless (not rosterDay.isClosed)
    unless (rosterWeek.isLive && rosterShiftIsOpen rosterSlot) do
        ensureRosterWeekIsDraftForEdit rosterWeek

authorizeRosterSlotDeleteContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> IO ()
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
            redirectToRosterWindow weekOffset rosterGroupId

respondWithSilentRosterNoOp :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithSilentRosterNoOp rosterGroupId weekOffset =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled mempty
        else redirectToRosterWindow weekOffset rosterGroupId

renderRosterShiftDialogForCreate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterLane -> Int -> RosterShiftDialogValues -> IO ()
renderRosterShiftDialogForCreate rosterDay rosterWeek slotDefinition rowIndex values =
    respondHtmlProfiled =<< rosterShiftDialogForCreateHtml rosterDay rosterWeek slotDefinition rowIndex values

respondWithRosterShiftCreateDialogOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> RosterWeek -> RosterLane -> Int -> RosterShiftDialogValues -> IO ()
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
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation [(unpackId rosterDay.id, rowIndex)])
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
            redirectToRosterWindow rosterWeek.weekOffset rosterGroupId

respondToRosterSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotMove rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation impactedRowKeys)
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterTimelineSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> Bool -> IO ()
respondToRosterTimelineSlotMove rosterGroupId rosterWeek mutationResult shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections RosterTimelineMutation
    respondWithRosterResourceInvalidation
        rosterGroupId
        rosterWeek.weekOffset
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (clearDialogOverlayOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterSlotUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> RosterWeek -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ()
respondToRosterSlotUpdate rosterGroupId rosterWeek mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation impactedRowKeys)
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

fetchRosterDayForMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterDay -> IO RosterDay
fetchRosterDayForMutation rosterDayId = do
    existing <- query @RosterDay
        |> filterWhere (#id, rosterDayId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
    case existing of
        Just rosterDay
            | rosterDay.publicationState == Draft -> do
                venueConfig <- fetchVenueConfig
                let rosterGroupId = Id rosterDay.rosterGroupId
                    weekOffset = venueWeekOffsetForDay venueConfig rosterDay.operationalDate
                _ <- materializeRosterWindowMutation rosterGroupId weekOffset
                fetch rosterDayId
            | otherwise -> pure rosterDay
        Nothing -> do
            let rosterGroupId = Id (param @UUID "rosterGroupId")
            let operationalDate = param @Calendar.Day "operationalDate"
            rosterGroup <- query @RosterGroup
                |> filterWhere (#id, rosterGroupId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#isActive, True)
                |> fetchOne
            accessDeniedUnless (rosterDayId == projectedRosterDayId rosterGroup.id operationalDate)
            venueConfig <- fetchVenueConfig
            let weekOffset = venueWeekOffsetForDay venueConfig operationalDate
            _ <- materializeRosterWindowMutation rosterGroup.id weekOffset
            rosterDay <- fetch rosterDayId
            accessDeniedUnless (rosterDay.operationalDate == operationalDate)
            pure rosterDay

resolveRosterGroupIdForFragmentRosterDay :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Id RosterDay -> IO (Id RosterGroup)
resolveRosterGroupIdForFragmentRosterDay weekOffset rosterDayId = do
    rosterDay <- fetch rosterDayId
    ensureRecordInCurrentVenue rosterDay.venueId
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, rosterDay.venueId) |> fetchOne
    accessDeniedUnless (venueWeekOffsetForDay venueConfig rosterDay.operationalDate == weekOffset)
    pure (coerce rosterDay.rosterGroupId)

respondWithDeleteRosterSlotDropConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> Calendar.Day -> Int -> IO ()
respondWithDeleteRosterSlotDropConfirmation rosterSlot anchorDate calendarRevision =
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {confirmationDialog}
        </div>
    |]
  where
    confirmationDialog =
        renderDialogOverlay DialogOverlayConfig
            { dialogOverlayTitle = "Delete roster shift?"
            , dialogOverlayBody = [hsx|<p class="mb-0">Delete this shift?</p>|]
            , dialogOverlayStartButtons = []
            , dialogOverlayButtons =
                [ OverlayButton
                    { overlayButtonLabel = "Cancel"
                    , overlayButtonClass = "btn btn-outline-secondary"
                    , overlayButtonAction = OverlayCloseAction
                    }
                , OverlayButton
                    { overlayButtonLabel = "Delete shift"
                    , overlayButtonClass = "btn btn-danger"
                    , overlayButtonAction = GeneratedDialogFormAction
                        (appShellActionByMarker @ConfirmDeleteRosterSlotOverlay)
                        (rosterDeleteSlotActionRoute (pathTo (DeleteRosterSlotAction rosterSlot.id)) anchorDate calendarRevision)
                        []
                        Nothing
                    }
                ]
            , dialogOverlayDialogClass = ""
            }

rosterDeleteSlotActionRoute :: Text -> Calendar.Day -> Int -> AppShellActionRoute
rosterDeleteSlotActionRoute actionUrl anchorDate calendarRevision =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields =
            [ AppShellFieldValue ("anchorDate", tshow anchorDate)
            , AppShellFieldValue ("rosterCalendarRevision", tshow calendarRevision)
            ]
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

respondWithRemoveRosterRowConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterDay -> RosterDayRowRemovalPreview -> IO ()
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
        overflowCount = preview.laneRowRemovalOverflowCount
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

rosterWindowStartForOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> IO Calendar.Day
rosterWindowStartForOffset weekOffset = do
    venueConfig <- fetchVenueConfig
    pure (venueWeekStartDate venueConfig weekOffset)

markStaleRosterCalendarResponseForRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
markStaleRosterCalendarResponseForRefresh =
    when isHtmxRequest $
        forM_ (paramOrNothing @Int "rosterCalendarRevision") \expectedRevision -> do
            venueConfig <- fetchVenueConfig
            when (expectedRevision /= venueConfig.rosterCalendarRevision) $
                setHeader ("HX-Refresh", "true")

rosterWindowUrlForOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Int -> Id RosterGroup -> IO Text
rosterWindowUrlForOffset weekOffset rosterGroupId =
    rosterWindowUrl <$> rosterWindowStartForOffset weekOffset <*> pure rosterGroupId

redirectToRosterWindow :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Id RosterGroup -> IO ()
redirectToRosterWindow weekOffset rosterGroupId =
    rosterWindowUrlForOffset weekOffset rosterGroupId >>= redirectToPath

rosterActionWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Int
rosterActionWeekOffset = do
    venueConfig <- fetchVenueConfig
    let anchorDate = param @Calendar.Day "anchorDate"
    pure (venueWeekOffsetForDay venueConfig (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate))

rosterMutationWeekOffset :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO Int
rosterMutationWeekOffset = do
    venueConfig <- fetchVenueConfig
    let calendarRevision = param @Int "rosterCalendarRevision"
    requireCurrentRosterCalendarRevision venueConfig calendarRevision
    rosterActionWeekOffset

rosterCopyActionWeekOffsets :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Int, Int)
rosterCopyActionWeekOffsets = do
    venueConfig <- fetchVenueConfig
    let sourceAnchorDate = param @Calendar.Day "sourceAnchorDate"
    let targetAnchorDate = param @Calendar.Day "targetAnchorDate"
    let calendarRevision = param @Int "rosterCalendarRevision"
    let resolve = venueWeekOffsetForDay venueConfig . startOfWeekFor venueConfig.rosterWeekStartsOn
    requireCurrentRosterCalendarRevision venueConfig calendarRevision
    pure (resolve sourceAnchorDate, resolve targetAnchorDate)

rosterWeekOffsetForAnchor :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Calendar.Day -> IO Int
rosterWeekOffsetForAnchor anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (venueWeekOffsetForDay venueConfig (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate))

currentRosterGridViewMode :: (?request :: Request) => Calendar.Day -> RosterGridViewMode
currentRosterGridViewMode windowStart =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Calendar.Day "dayDate", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayDate, _) -> RosterDayTimelineGridView (clampDayOffset (fromInteger (Calendar.diffDays dayDate windowStart)))
        (Just "timeline", Nothing, Just dayOffset) -> RosterDayTimelineGridView (clampDayOffset dayOffset)
        _ -> RosterWeekGridView
  where
    clampDayOffset = max 0 . min 6


buildRosterTimelineTodayUrl :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO Text
buildRosterTimelineTodayUrl rosterGroupId = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (rosterTimelineWindowUrl today rosterGroupId)

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Id RosterGroup -> IO ()
renderRosterWeekPage weekOffset requestedRosterGroupId =
    profileActionSpan "roster.page.render" do
        venueConfig <- profileActionSpan "roster.page.fetch_venue_config" fetchVenueConfig
        let weekStartDate = venueWeekStartDate venueConfig weekOffset
        let weekEndDate = Calendar.addDays 6 weekStartDate
        setTitle "Roster"
        rosterGroups <- profileActionSpan "roster.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
        currentRosterGroup <- profileActionSpan "roster.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just requestedRosterGroupId))
        rosterDataOrNothing <- profileActionSpan "roster.page.fetch_read_model" (fetchVisibleRosterReadModel currentRosterGroup.id weekOffset)
        passkeySetupPrompt <- profileActionSpan "roster.page.passkey_prompt" passkeySetupPromptFromSession
        passkeyStrongAuthenticationRequired <- profileActionSpan "roster.page.passkey_policy" currentUserRequiresMandatoryPasskey
        timelineTodayUrl <- profileActionSpan "roster.page.timeline_today_url" (buildRosterTimelineTodayUrl currentRosterGroup.id)

        case rosterDataOrNothing of
            Just RosterRenderData { rosterWeek, rosterDays, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } ->
                let visibleRosterWeek =
                        case rosterWeek of
                            Just legacyRosterWeek
                                | legacyRosterWeek.isLive || hasRole Manager -> Just legacyRosterWeek
                            _ -> Nothing
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
                                , rosterCalendarRevision
                                , assignmentFilters
                                , staffMembers
                                , panelStaff
                                , templateLibrary
                                , templateLibraryUserId
                                , showNotificationPanelData = rosterNotificationPanelData
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
                                , highlightOwnLiveShifts
                                , currentViewerStaffKey
                                , publicHolidays = rosterPublicHolidays
                                , passkeySetupPrompt
                                , passkeyStrongAuthenticationRequired
                                , rosterGridViewMode = currentRosterGridViewMode weekStartDate
                                , rosterTimelineTodayUrl = Just timelineTodayUrl
                                }
            Nothing ->
                error "Roster date range could not be projected for the selected roster group"

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
            venueConfig <- query @VenueConfig |> filterWhere (#venueId, rosterWeek.venueId) |> fetchOne
            let weekStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterGroupId, rosterWeek.rosterGroupId)
                |> filterWhereGreaterThanOrEqualTo (#operationalDate, weekStartDate)
                |> filterWhereLessThanOrEqualTo (#operationalDate, Calendar.addDays 6 weekStartDate)
                |> fetch
            if null rosterDays
                then pure []
                else query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                    |> filterWhereIn (#staffId, map Just (nub staffIds))
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

respondToRosterSlotDefinitionError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondToRosterSlotDefinitionError rosterGroupId weekOffset errorMessage =
    if isHtmxRequest
        then respondWithRosterToast errorMessage "app-toast-error"
        else do
            setErrorMessage errorMessage
            redirectToRosterWindow weekOffset rosterGroupId

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> LiveMutationResult value -> Text -> IO ()
respondToRosterSlotDefinitionSuccess rosterGroupId weekOffset mutationResult successMessage =
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                rosterGroupId
                weekOffset
                mutationResult.liveMutationTouchedResources
                rosterGridInnerAndStaffPanelFragments
                mempty
        else do
            setSuccessMessage successMessage
            redirectToRosterWindow weekOffset rosterGroupId
