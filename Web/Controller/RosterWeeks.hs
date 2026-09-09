{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.Controller.RosterWeeks where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Controller
import Application.Helper.FrontendContract.AppShell (AnchorDateField,
                                                     ConfirmDeleteRosterSlotOverlay,
                                                     ConfirmRemoveRosterRowOverlay,
                                                     CreateRosterShiftOverlay,
                                                     OpenRosterSlotDeleteConfirmationDialog,
                                                     RosterCalendarRevisionField,
                                                     UpdateRosterShiftOverlay)
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
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
import Application.Helper.SurfaceResource (LiveMutationResult (liveMutationTouchedResources, liveMutationValue))
import Application.Helper.UserPreferences
import Application.Helper.View (OverlayButton (OverlayButton, overlayButtonAction, overlayButtonClass, overlayButtonLabel),
                                OverlayButtonAction (GeneratedDialogFormAction, OverlaySubmitFormAction),
                                ToastOverlayPosition (ToastBottomCenter),
                                defaultDialogOverlayConfig,
                                dialogOverlayCloseButton, dialogOverlayMountId,
                                errorToast, renderDialogOverlay,
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import qualified Application.RosterNotification as Notification
import Application.RosterPublication (rosterDaysArePublished)
import Application.RosterShiftAssignment (RosterShiftAssignment (StaffAssignment),
                                          applyRosterShiftAssignment,
                                          copyRosterShiftAssignment,
                                          rosterShiftIsOpen)
import Application.VenueTime (VenueTimeError (InvalidCivilTimeOfDay, NonPositiveResolvedInterval, NonexistentCivilTime, RepeatedCivilTimeRequiresOccurrence, RepeatedTimeOccurrenceNotApplicable))
import Application.VenueTime.Model
import Data.Coerce (coerce)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Time.Calendar as Calendar
import Network.HTTP.Types.Status (status400, status409)
import qualified Network.Wai as Wai
import qualified IHP.HSX.Markup as Markup
import Web.Controller.Prelude
import Web.Controller.RosterWeeks.Validation
import Web.Controller.Sessions (passkeySetupPromptSessionKey)
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.DateRange (RosterDayRowRemovalPreview (laneRowRemovalOverflowCount),
                                  RosterWindow (rosterWindowLanes, rosterWindowProjectedDays),
                                  RosterWindowDay (persistedRosterDay),
                                  RosterWindowLane (rosterWindowLaneName),
                                  RosterWindowScope (..), fetchRosterWindow,
                                  previewRemoveRosterDayRowByLanes,
                                  projectedRosterDayId,
                                  rosterWindowScopeForAnchor)
import Web.RosterWeeks.DirectReadModel (fetchRosterNotificationWindowDays)
import Web.RosterWeeks.Dom
import Web.RosterWeeks.DropWorkflow
import Web.RosterWeeks.Filters
import Web.RosterWeeks.FrontendSurface (rosterDuplicateShiftIntentForm,
                                        rosterMoveShiftIntentForm,
                                        rosterTimelineMoveShiftIntentForm)
import Web.RosterWeeks.Mutations
import Web.RosterWeeks.Overview
import Web.RosterWeeks.Paths (rosterCopyWeekUrl, rosterDeleteSlotUrl,
                              rosterTimelineWindowUrl, rosterWindowUrl)
import Web.RosterWeeks.Projection
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Responses (respondToRosterSlotMutation,
                                  respondToRosterSlotMove,
                                  respondToRosterTimelineSlotMove,
                                  respondToRosterSlotUpdate,
                                  respondToRosterShiftEdit,
                                  respondWithRosterContent,
                                  respondWithRosterContentError,
                                  respondWithRosterContentUpdate,
                                  respondWithRosterDialogOverlay,
                                  respondWithRosterFragments,
                                  respondWithRosterFragmentsUpdate,
                                  respondWithRosterOwnHighlightPreferenceUpdate,
                                  respondWithRosterResourceInvalidation,
                                  respondWithRosterToast)
import Web.RosterWeeks.Service
import Web.RosterWeeks.ShiftWorkflow
import Web.RosterWeeks.StaffOptions (fetchStaffPayConfigurationRequiredIds)
import Web.RosterWeeks.Types
import Web.RosterWeeks.VenueSettings (setVenueRosterLayoutMode)
import Web.View.RosterWeeks.NotificationDialog (renderRosterNotificationConfirmation)
import Web.View.RosterWeeks.OccurrenceDialog
import Web.View.RosterWeeks.Overview (renderWeekOverviewPanelFragment)
import Web.View.RosterWeeks.ShiftDialog
import Web.View.RosterWeeks.Show (renderNoRosterGroupShell,
                                  renderRosterWeekShell)
import Web.View.RosterWeeks.StaffPanel (renderrosterStaffPanelLiveFragment)
import Web.View.RosterWeeks.Timeline (renderRosterDayTimelineContent)

rosterSurfaceRequestErrorMessage :: [SurfaceRequestFieldError] -> Text
rosterSurfaceRequestErrorMessage errors =
    "Check the roster controls: " <> surfaceRequestFieldErrorsMessage errors

respondRosterBadRequest :: (?request :: Request, ?respond :: Respond) => Text -> IO value
respondRosterBadRequest message =
    respondAndStop (Wai.responseLBS status400 [("Content-Type", "text/plain")] (cs message))

respondRosterNotificationBadRequest :: (?request :: Request, ?respond :: Respond) => Text -> IO value
respondRosterNotificationBadRequest = respondRosterBadRequest

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

respondWithRosterCopyFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ResponseReceived
respondWithRosterCopyFailure targetScope message =
    if isHtmxRequest
        then respondWithRosterToast message "app-toast-error"
        else do
            setErrorMessage message
            redirectToRosterWindow targetScope

respondWithRosterCopyOccurrenceDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterWindowScope -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> IO ResponseReceived
respondWithRosterCopyOccurrenceDialog sourceScope targetScope startIsRepeated endIsRepeated selections =
    if not isHtmxRequest
        then do
            let copyError = RosterCopyOccurrenceSelectionRequired
            recordRosterCopyError copyError
            respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
        else do
            let dialog = renderRosterWeekCopyOccurrenceDialog
                    (rosterCopyWeekUrl sourceScope.rosterWindowStart targetScope.rosterWindowStart targetScope.rosterWindowRosterGroupId)
                    targetScope.rosterWindowCalendarRevision
                    startIsRepeated
                    endIsRepeated
                    selections
            respondWithRosterDialogOverlay targetScope dialog

respondWithRosterShiftOccurrenceDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> FrontendSurfaceIntentForm -> (Text, Text) -> Bool -> Bool -> ShiftCopyOccurrenceSelections -> IO ResponseReceived
respondWithRosterShiftOccurrenceDialog scope operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections =
    if not isHtmxRequest
        then respondWithMoveRosterShiftFailure scope "Choose repeated-time occurrences from the roster copy dialog."
        else do
            let dialog = renderRosterShiftOccurrenceDialog operationLabel intentForm (startOccurrenceField, endOccurrenceField) startIsRepeated endIsRepeated selections
            respondWithRosterDialogOverlay scope dialog

respondWithRosterSlotCopyBoundaryFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> FrontendSurfaceIntentForm -> (Text, Text) -> (Bool, Bool) -> ShiftCopyOccurrenceSelections -> BoundaryModelError -> IO ResponseReceived
respondWithRosterSlotCopyBoundaryFailure scope operationLabel intentForm occurrenceFields (startIsRepeated, endIsRepeated) selections failure =
    case failure of
        BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)
            | startIsRepeated || endIsRepeated ->
                respondWithRosterShiftOccurrenceDialog scope operationLabel intentForm occurrenceFields startIsRepeated endIsRepeated selections
        _ -> respondWithMoveRosterShiftFailure scope (rosterCopyBoundaryErrorMessage failure)

rosterCopyBoundaryErrorMessage :: BoundaryModelError -> Text
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (NonexistentCivilTime _)) = "A copied roster time does not exist because clocks move forward. Change the source shift before copying."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedCivilTimeRequiresOccurrence _)) = "Choose whether repeated copied times use their first or second occurrence."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (RepeatedTimeOccurrenceNotApplicable _ _)) = "A copied occurrence choice applies only to a repeated local time."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (InvalidCivilTimeOfDay _)) = "The source roster contains an invalid local time."
rosterCopyBoundaryErrorMessage (BoundaryCivilTimeError (NonPositiveResolvedInterval _ _)) = "The copied roster shift would not have a positive duration."
rosterCopyBoundaryErrorMessage (BoundaryUnsupportedTimezone _) = "This venue timezone is not supported for roster copying."
rosterCopyBoundaryErrorMessage BoundaryBreakNotContained = "The copied break would fall outside its shift."
rosterCopyBoundaryErrorMessage BoundaryBreakShapeInvalid = "The copied break boundaries are incomplete."
rosterCopyBoundaryErrorMessage BoundaryShiftShapeInvalid = "The copied shift boundaries are incomplete."

instance Controller RosterWeeksController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        case ?theAction of
            RosterWeeksAction -> unless (currentUserIsImpersonating && currentImpersonationReturnFallbackVisible) ensureProfileCompleted
            ShowRosterWindowAction {} -> unless (currentUserIsImpersonating && currentImpersonationReturnFallbackVisible) ensureProfileCompleted
            _ -> ensureProfileCompleted
        markStaleRosterCalendarResponseForRefresh

    action currentAction@RosterWeeksAction = runBepis currentAction BepisPageAction do
        venueConfig <- fetchVenueConfig
        today <- utctDay <$> getCurrentTime
        resolveRosterPageGroup >>= \case
            Nothing -> do
                clearImpersonationReturnFallback
                renderNoRosterGroupPage
            Just (currentRosterGroup, requestedGroupWasViewable) -> do
                let currentWeekPath = case paramOrNothing @Text "rosterView" of
                        Just "timeline" -> rosterTimelineWindowUrl today currentRosterGroup.id
                        _ -> rosterWindowUrl today currentRosterGroup.id
                if not requestedGroupWasViewable || not isHtmxRequest
                    then redirectToPath currentWeekPath
                    else case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
                        (Just "timeline", Nothing) -> do
                            setHeader ("HX-Redirect", cs currentWeekPath)
                            respondHtmlProfiled mempty
                        _ -> do
                            clearImpersonationReturnFallback
                            setHtmxPushUrl currentWeekPath
                            renderRosterWeekPage (rosterWindowScopeForAnchor venueConfig currentRosterGroup.id today)

    action currentAction@ShowRosterWindowAction { anchorDate = anchorDateParam } = runBepis currentAction BepisPageAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        venueConfig <- fetchVenueConfig
        resolveRosterPageGroup >>= \case
            Nothing -> do
                clearImpersonationReturnFallback
                renderNoRosterGroupPage
            Just (rosterGroup, True) -> do
                clearImpersonationReturnFallback
                renderRosterWeekPage (rosterWindowScopeForAnchor venueConfig rosterGroup.id anchorDate)
            Just (rosterGroup, False) ->
                redirectToPath (rosterWindowUrl anchorDate rosterGroup.id)

    action currentAction@ShowRosterDayTimelineContentFragmentAction { anchorDate = anchorDateParam, rosterDayId } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        maybeRosterData <- fetchVisibleRosterReadModel scope
        case maybeRosterData of
            Nothing -> respondHtmlProfiled mempty
            Just rosterData -> do
                let canViewTimeline = maybe False (.windowIsPublished) rosterData.rosterWeek || hasRole Manager
                accessDeniedUnless canViewTimeline
                let maybeRosterDay = find (\rosterDay -> rosterDay.id == rosterDayId) rosterData.rosterDays
                let rosterGridModel = rosterGridRenderModelFromProjection rosterData
                respondHtmlProfiled (maybe mempty (renderRosterDayTimelineContent Nothing rosterGridModel) maybeRosterDay)

    action currentAction@ShowRosterWeekOverviewFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        respondHtmlProfiled =<< renderRosterWeekOverviewFragment scope.rosterWindowStart rosterGroup.id

    action currentAction@ShowRosterWeekContentFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        respondWithRosterContent scope

    action currentAction@ShowRosterWeekGridToolbarFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        toolbarHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionGridToolbar
        respondHtmlProfiled (fromMaybe mempty toolbarHtml)

    action currentAction@ShowRosterWeekGridFrameFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        frameHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionGridFrame
        respondHtmlProfiled (fromMaybe mempty frameHtml)

    action currentAction@ShowRosterWeekDayColumnsFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        fragmentHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionDayColumns
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekDayRailFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        fragmentHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionDayRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekWageRailFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        fragmentHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionWageRail
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekSlotsGridFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        fragmentHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionSlotsGrid
        respondHtmlProfiled (fromMaybe mempty fragmentHtml)

    action currentAction@ShowRosterWeekStaffPanelFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterWindowScopeForRequestedAnchor rosterGroup.id anchorDate
        panelScope <- case parseRosterStaffPanelScope of
            Left errorMessage -> setErrorMessage errorMessage >> pure RosterStaffPanelCurrentGroup
            Right scope -> pure scope
        panelModel <- fetchVisibleRosterStaffPanelRenderModel panelScope scope
        respondHtmlProfiled (renderrosterStaffPanelLiveFragment panelModel)

    action currentAction@ShowRosterNotificationConfirmationAction = runBepis currentAction BepisFragmentAction do
        ensureManagerRole
        notificationFields <- case RosterAction.parseShowRosterNotificationConfirmationActionParams of
            Left errors -> respondRosterNotificationBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> pure fields
        let rosterGroupId = Id (surfaceFieldValue @Surface.RosterGroupId notificationFields)
        let windowStart = surfaceFieldValue @Surface.WindowStartDate notificationFields
        let windowEnd = surfaceFieldValue @Surface.WindowEndDate notificationFields
        let expectedCalendarRevision = surfaceFieldValue @Surface.RosterCalendarRevision notificationFields
        maybeRosterGroup <- query @RosterGroup
            |> filterWhere (#id, rosterGroupId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
        accessDeniedUnless (isJust maybeRosterGroup)
        let rosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized notification roster group missing") maybeRosterGroup
        venueConfig <- fetchVenueConfig
        accessDeniedUnless (expectedCalendarRevision == venueConfig.rosterCalendarRevision)
        accessDeniedUnless (windowStart == startOfWeekFor venueConfig.rosterWeekStartsOn windowStart && windowEnd == Calendar.addDays 7 windowStart)
        rosterDays <- fetchRosterNotificationWindowDays currentVenueId rosterGroup.id windowStart windowEnd
        accessDeniedUnless (rosterDaysArePublished rosterDays && length rosterDays == 7)
        venue <- fetch currentVenueId
        audience <- Notification.fetchRosterNotificationAudience venue rosterGroup
        latestRun <- Notification.fetchLatestRosterNotificationRunSummaryForWindow currentVenueId rosterGroup.id windowStart windowEnd
        respondHtmlProfiled (renderRosterNotificationConfirmation venue rosterGroup windowStart windowEnd expectedCalendarRevision audience latestRun)

    action currentAction@CreateRosterNotificationRunAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        notificationFields <- case RosterAction.parseCreateRosterNotificationRunActionParams of
            Left errors -> respondRosterNotificationBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> pure fields
        let rosterGroupId = Id (surfaceFieldValue @Surface.RosterGroupId notificationFields)
        let windowStart = surfaceFieldValue @Surface.WindowStartDate notificationFields
        let windowEnd = surfaceFieldValue @Surface.WindowEndDate notificationFields
        let expectedCalendarRevision = surfaceFieldValue @Surface.RosterCalendarRevision notificationFields
        maybeRosterGroup <- query @RosterGroup
            |> filterWhere (#id, rosterGroupId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
        accessDeniedUnless (isJust maybeRosterGroup)
        let rosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized notification roster group missing") maybeRosterGroup
        venueConfig <- fetchVenueConfig
        accessDeniedUnless (expectedCalendarRevision == venueConfig.rosterCalendarRevision)
        accessDeniedUnless (windowStart == startOfWeekFor venueConfig.rosterWeekStartsOn windowStart && windowEnd == Calendar.addDays 7 windowStart)
        venue <- fetch currentVenueId
        let scope = RosterWindowScope
                { rosterWindowVenueId = currentVenueId
                , rosterWindowRosterGroupId = rosterGroupId
                , rosterWindowStart = windowStart
                , rosterWindowEnd = windowEnd
                , rosterWindowCalendarRevision = expectedCalendarRevision
                }
        runResult <- Notification.createRosterNotificationRunForWindowUnlessActiveAtRevision currentUser venue rosterGroup windowStart windowEnd expectedCalendarRevision
        case runResult of
            Notification.RosterNotificationRunCalendarConflict ->
                markStaleRosterCalendarResponseForRefresh >> respondRosterNotificationBadRequest "The roster calendar changed. Review the refreshed window and try again."
            Notification.RosterNotificationRunAlreadyActive ->
                if isHtmxRequest
                    then respondWithRosterFragments scope [RosterProjectionStaffPanel] [hsx|
                        {renderDialogOverlayClearOob}
                        {renderToastOob ToastBottomCenter (errorToast "Roster email delivery is already in progress.")}
                    |]
                    else setErrorMessage "Roster email delivery is already in progress." >> redirectToRosterWindow scope
            Notification.RosterNotificationRunHasNoEligibleRecipients ->
                if isHtmxRequest
                    then respondWithRosterFragments scope [RosterProjectionStaffPanel] [hsx|
                        {renderDialogOverlayClearOob}
                        {renderToastOob ToastBottomCenter (errorToast "No eligible recipients are available.")}
                    |]
                    else setErrorMessage "No eligible recipients are available." >> redirectToRosterWindow scope
            Notification.RosterNotificationRunCreated run -> do
                recipients <- Notification.decodeRosterNotificationRecipients run
                skippedRecipients <- Notification.decodeRosterNotificationSkippedRecipients run
                let successMessage = "Roster email queued for " <> Notification.rosterNotificationRecipientCountLabel (length recipients) <> ". " <> tshow (length skippedRecipients) <> " skipped."
                if isHtmxRequest
                    then respondWithRosterResourceInvalidation
                        scope
                        (Set.singleton (rosterNotificationStatusResource (unpackId rosterGroupId) run.weekStart run.windowEnd))
                        [RosterProjectionStaffPanel]
                        [hsx|
                            {renderDialogOverlayClearOob}
                            {renderToastOob ToastBottomCenter (successToast successMessage)}
                        |]
                    else setSuccessMessage successMessage >> redirectToRosterWindow scope

    action currentAction@ShowRosterWeekDaySectionFragmentAction { anchorDate = anchorDateParam, rosterDayId } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        scope <- rosterWindowScopeForFragmentRosterDay anchorDate rosterDayId
        daySectionHtml <- renderVisibleRosterReadModelFragment scope (RosterProjectionDaySection (unpackId rosterDayId))
        respondHtmlProfiled (fromMaybe mempty daySectionHtml)

    action currentAction@ShowRosterWeekRowFragmentAction { anchorDate = anchorDateParam, rosterDayId, rowIndex } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        scope <- rosterWindowScopeForFragmentRosterDay anchorDate rosterDayId
        rowHtml <- renderVisibleRosterReadModelFragment scope (RosterProjectionRow (unpackId rosterDayId) rowIndex)
        respondHtmlProfiled (fromMaybe mempty rowHtml)

    action currentAction@UpdateRosterAssignmentFiltersAction = runBepis currentAction BepisPreferenceAction do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterActionScope rosterGroup.id
        case RosterAction.parseToggleRosterAssignmentFiltersActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else do
                        setErrorMessage errorMessage
                        redirectToRosterWindow scope
            Right fields -> do
                setRosterAssignmentFiltersSession RosterAssignmentFilters
                    { hideStaffAtIdealShifts = surfaceFieldValue @Surface.HideStaffAtIdealShifts fields
                    , hideStaffUnavailable = surfaceFieldValue @Surface.HideStaffUnavailable fields
                    , hideStaffOnApprovedLeave = surfaceFieldValue @Surface.HideStaffOnApprovedLeave fields
                    , hideStaffAlreadyAssignedToday = surfaceFieldValue @Surface.HideStaffAlreadyAssignedToday fields
                    }
                respondHtmlProfiled mempty

    action currentAction@CreateRosterWeekAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        result <- ensureRosterWeekExistsMutation scope
        case result of
            Left message -> respondToRosterSlotDefinitionError scope message
            Right mutationResult -> do
                let (_, wasCreated) = mutationResult.liveMutationValue
                let successMessage =
                        if wasCreated
                            then "Roster week created successfully"
                            else "Roster week already exists."
                let targetPath = rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId
                if isHtmxRequest
                    then do
                        setHtmxPushUrl targetPath
                        respondWithRosterContentUpdate scope mutationResult.liveMutationTouchedResources successMessage
                    else do
                        setSuccessMessage successMessage
                        redirectToPath targetPath

    action currentAction@CopyRosterWeekAction = runBepis currentAction BepisMutationAction do
        (sourceWindowStart, targetWindowStart) <- rosterCopyActionDates
        venueConfig <- fetchVenueConfig
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        let sourceScope = rosterWindowScopeForAnchor venueConfig rosterGroup.id sourceWindowStart
            targetScope = rosterWindowScopeForAnchor venueConfig rosterGroup.id targetWindowStart

        if sourceWindowStart == targetWindowStart
            then do
                let copyError = RosterCopySameWindow
                recordRosterCopyError copyError
                respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
            else do
                sourceDays <- query @RosterDay
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> filterWhereGreaterThanOrEqualTo (#operationalDate, sourceWindowStart)
                    |> filterWhereLessThan (#operationalDate, Calendar.addDays 7 sourceWindowStart)
                    |> fetch
                case sourceDays of
                    [] -> do
                        let copyError = RosterCopySourceWindowUnavailable
                        recordRosterCopyError copyError
                        respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
                    _ ->
                        case copyOccurrenceSelectionsFromRosterAction of
                            Left _ -> do
                                let copyError = RosterCopyPersistenceRejected
                                recordRosterCopyError copyError
                                respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
                            Right selections ->
                                rosterWindowCopyAmbiguousEndpoints venueConfig currentVenueId rosterGroup.id sourceWindowStart targetWindowStart >>= \case
                                    Left failure -> do
                                        let copyError = RosterCopyBoundaryError failure
                                        recordRosterCopyError copyError
                                        respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
                                    Right (startIsRepeated, endIsRepeated)
                                        | (startIsRepeated && isNothing selections.copyShiftStartOccurrence)
                                            || (endIsRepeated && isNothing selections.copyShiftEndOccurrence) ->
                                            respondWithRosterCopyOccurrenceDialog sourceScope targetScope startIsRepeated endIsRepeated selections
                                        | otherwise -> do
                                            copyResult <- copyRosterWindowFromSourceMutation selections rosterGroup.id sourceWindowStart targetWindowStart
                                            case copyResult of
                                                Left copyError ->
                                                    respondWithRosterCopyFailure targetScope (rosterCopySafeMessage copyError)
                                                Right mutationResult -> do
                                                    let successMessage = "Roster week copied from the previous week."
                                                    let targetPath = rosterWindowUrl targetScope.rosterWindowStart targetScope.rosterWindowRosterGroupId
                                                    if isHtmxRequest
                                                        then do
                                                            setHtmxPushUrl targetPath
                                                            respondWithRosterContentUpdate targetScope mutationResult.liveMutationTouchedResources successMessage
                                                        else do
                                                            setSuccessMessage successMessage
                                                            redirectToPath targetPath

    action currentAction@ToggleRosterWeekLiveStatusAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
        let windowDays = mapMaybe (.persistedRosterDay) window.rosterWindowProjectedDays
        let windowState = RosterWindowState
                { windowRosterGroupId = unpackId rosterGroup.id
                , windowIsPublished = rosterDaysArePublished windowDays
                , windowHasPublishedDays = any ((== Published) . (.publicationState)) windowDays
                }
        let targetPath = rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId
        case RosterAction.parseToggleRosterWeekLiveStatusActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterContentError scope errorMessage
                    else do
                        setErrorMessage errorMessage
                        redirectToPath targetPath
            Right fields -> do
                let nextLiveStatus = surfaceFieldValue @Surface.IsLive fields
                mutationResult <- toggleRosterWeekLiveStatusMutation scope windowState nextLiveStatus
                case mutationResult of
                    Left errorMessage ->
                        if isHtmxRequest
                            then respondWithRosterContentError scope errorMessage
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
                                respondWithRosterContentUpdate scope mutationResult.liveMutationTouchedResources successMessage
                            else do
                                setSuccessMessage successMessage
                                redirectToPath targetPath

    action currentAction@CreateRosterWeekSlotDefinitionAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        window <- fetchRosterWindow scope.rosterWindowVenueId scope.rosterWindowRosterGroupId scope.rosterWindowStart
        let existingNames = map (.rosterWindowLaneName) window.rosterWindowLanes
            submittedName = Text.strip (paramOrDefault @Text "" "name")
            requestedSlotName = if Text.null submittedName
                then Right (firstAvailableDefaultName existingNames)
                else normalizeRosterSlotDefinitionName submittedName
        case requestedSlotName of
            Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
            Right laneName -> do
                result <- appendRosterWindowLaneMutation scope laneName
                case result of
                    Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
                    Right mutationResult -> respondToRosterSlotDefinitionSuccess scope mutationResult "Roster column added."

    action currentAction@RemoveRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId } = runBepis currentAction BepisMutationAction do
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
        let rosterGroupId = Id rosterDay.rosterGroupId
        scope <- rosterMutationScope rosterGroupId
        accessDeniedUnless (rosterDay.operationalDate >= scope.rosterWindowStart && rosterDay.operationalDate < scope.rosterWindowEnd)
        result <- removeRosterWindowLaneMutation scope rosterLane.id
        case result of
            Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
            Right mutationResult -> respondToRosterSlotDefinitionSuccess scope mutationResult "Roster column removed."

    action currentAction@SortRosterWeekAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        repackRosterWindowMutation scope >>= \case
            Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
            Right mutationResult ->
                if isHtmxRequest
                    then
                        respondWithRosterResourceInvalidation
                            scope
                            mutationResult.liveMutationTouchedResources
                            rosterGridInnerAndStaffPanelFragments
                            renderDialogOverlayClearOob
                    else do
                        setSuccessMessage "Roster sorted."
                        redirectToRosterWindow scope

    action currentAction@ToggleRosterDayClosedAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetchRosterDayForMutation rosterDayId
        scope <- rosterMutationScopeForDay rosterDay
        ensureRosterDayIsDraftForEdit scope rosterDay
        let nextClosedState = not rosterDay.isClosed

        toggleRosterDayClosedMutation scope rosterDay nextClosedState closedRosterDayRows >>= \case
            Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
            Right mutationResult -> do
                let successMessage =
                        if nextClosedState
                            then "Roster day marked closed."
                            else "Roster day reopened."
                let targetPath = rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId
                if isHtmxRequest
                    then do
                        mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
                        setHtmxPushUrl targetPath
                        respondWithRosterResourceInvalidation
                            scope
                            mutationResult.liveMutationTouchedResources
                            mountedProjections
                            renderDialogOverlayClearOob
                    else do
                        setSuccessMessage successMessage
                        redirectToPath targetPath

    action currentAction@AddRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetchRosterDayForMutation rosterDayId
        scope <- rosterMutationScopeForDay rosterDay
        ensureRosterDayIsDraftForEdit scope rosterDay

        when rosterDay.isClosed do
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            earlyReturn $ if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow scope

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
                        redirectToRosterWindow scope
            else
                addRosterDayRowMutation scope rosterDay >>= \case
                    Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
                    Right mutationResult ->
                        if isHtmxRequest
                            then do
                                mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
                                respondWithRosterResourceInvalidation
                                    scope
                                    mutationResult.liveMutationTouchedResources
                                    mountedProjections
                                    renderDialogOverlayClearOob
                            else do
                                setSuccessMessage "Roster row added."
                                redirectToRosterWindow scope

    action currentAction@RemoveRosterRowAction { rosterDayId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable

        rosterDay <- fetchRosterDayForMutation rosterDayId
        scope <- rosterMutationScopeForDay rosterDay
        ensureRosterDayIsDraftForEdit scope rosterDay

        when rosterDay.isClosed do
            let errorMessage = "Closed days stay locked at two blank rows until reopened."
            earlyReturn $ if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow scope

        let rowCount = rosterDay.rowCount
        let confirmDeletePopulatedRow = paramOrDefault @Text "false" "confirmDeletePopulatedRow" == "true"

        when (rowCount <= minimumOpenRosterRows) do
            let errorMessage = "Roster days must keep at least two rows."
            earlyReturn $ if isHtmxRequest
                then respondWithRosterToast errorMessage "app-toast-error"
                else do
                    setErrorMessage errorMessage
                    redirectToRosterWindow scope

        preview <- previewRemoveRosterDayRowByLanes rosterDay
        if preview.laneRowRemovalOverflowCount > 0 && not confirmDeletePopulatedRow
            then respondWithRemoveRosterRowConfirmation rosterDay preview
            else
                removeRosterDayRowByLanesMutation scope rosterDay >>= \case
                    Left errorMessage -> respondToRosterSlotDefinitionError scope errorMessage
                    Right mutationResult ->
                        if isHtmxRequest
                            then do
                                mountedProjections <- rosterMutationMountedProjections (RosterDayMutation (unpackId rosterDay.id))
                                respondWithRosterResourceInvalidation
                                    scope
                                    mutationResult.liveMutationTouchedResources
                                    mountedProjections
                                    renderDialogOverlayClearOob
                            else do
                                setSuccessMessage "Roster row removed."
                                redirectToRosterWindow scope

    action currentAction@UpdateRosterLayoutPreferenceAction = runBepis currentAction BepisPreferenceAction do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
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
                        redirectToRosterWindow scope
            Right layoutMode -> do
                venueConfig <- fetchVenueConfig
                mutationResult <- setVenueRosterLayoutMode venueConfig layoutMode
                if isHtmxRequest
                    then respondWithRosterResourceInvalidation
                        scope
                        mutationResult.liveMutationTouchedResources
                        rosterGridStructuralAndStaffPanelFragments
                        (renderToastOob ToastBottomCenter (successToast "Venue roster layout saved."))
                    else do
                        setSuccessMessage "Venue roster layout saved."
                        redirectToRosterWindow scope

    action currentAction@MoveRosterShiftToSlotAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        case RosterIntent.parseMoveRosterShiftToSlotIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure scope (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                if parseRosterShiftDropDestinationToken targetToken == Just DeleteRosterShiftDestination
                    then do
                        result <- validateRosterShiftDeleteDropIntent scope sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure scope message
                            Right rosterSlot -> respondWithDeleteRosterSlotConfirmation rosterSlot (param @Calendar.Day "anchorDate") (param @Int "rosterCalendarRevision")
                    else do
                        result <- validateMoveRosterShiftIntent scope sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure scope message
                            Right MoveRosterShiftIntent { moveIsNoOp = True } -> respondWithSilentRosterNoOp scope
                            Right resultValue@MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                                let startOccurrenceValue = surfaceFieldValue @Surface.CopyStartOccurrence fields
                                let endOccurrenceValue = surfaceFieldValue @Surface.CopyEndOccurrence fields
                                case copyOccurrenceSelectionsFromValues startOccurrenceValue endOccurrenceValue of
                                    Left message -> respondWithMoveRosterShiftFailure scope message
                                    Right selections -> do
                                        boundaryResolution <- resolveRosterDayDropBoundaries resultValue selections
                                        let intentForm = rosterMoveShiftIntentForm scope.rosterWindowStart rosterGroup.id (surfaceFieldValue @Surface.RosterCalendarRevision fields) sourceToken targetToken Nothing Nothing
                                        let occurrenceFields = (surfaceFieldNameFrom @Surface.CopyStartOccurrence fields, surfaceFieldNameFrom @Surface.CopyEndOccurrence fields)
                                        case boundaryResolution of
                                            RosterDayDropBoundaryFailure repeatedEndpoints failure ->
                                                respondWithRosterSlotCopyBoundaryFailure scope "move" intentForm occurrenceFields repeatedEndpoints selections failure
                                            RosterDayDropBoundaryReady copiedBoundariesSlot -> do
                                                let updatedSlot = copiedBoundariesSlot
                                                        |> set #rosterDayId (unpackId targetRosterDay.id)
                                                        |> set #rosterLaneId (unpackId targetSlotDefinition.id)
                                                        |> set #slotSortOrder targetSlotDefinition.sortOrder
                                                        |> set #rowIndex targetRowIndex
                                                mutationResult <- moveRosterSlotMutation scope sourceRosterDay targetRosterDay sourceSlot updatedSlot
                                                case mutationResult of
                                                    Left message -> respondWithMoveRosterShiftFailure scope message
                                                    Right mutationResult -> do
                                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                                        let impactedRows = nub [(sourceSlot.rosterDayId, sourceSlot.rowIndex), (unpackId targetRosterDay.id, targetRowIndex)]
                                                        respondToRosterSlotMove scope mutationResult impactedRows shouldWarnSourceTimesheetUnchanged

    action currentAction@MoveRosterTimelineShiftAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        case RosterIntent.parseMoveRosterTimelineShiftIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure scope (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                result <- validateMoveRosterTimelineShiftIntent scope sourceToken targetToken
                case result of
                    Left message -> respondWithMoveRosterShiftFailure scope message
                    Right MoveRosterTimelineShiftIntent { timelineMoveIsNoOp = True } -> respondWithSilentRosterNoOp scope
                    Right resultValue@MoveRosterTimelineShiftIntent { timelineSourceSlot, timelineSourceRosterDay, timelineTargetRosterDay, timelineTargetSlotDefinition, timelineTargetRowIndex } -> do
                        let startOccurrenceValue = fromMaybe "" (surfaceFieldValue @Surface.TimelineStartOccurrence fields)
                        boundaryResolution <- resolveRosterTimelineDropBoundaries resultValue startOccurrenceValue
                        let calendarRevision = surfaceFieldValue @Surface.RosterCalendarRevision fields
                        let intentForm = rosterTimelineMoveShiftIntentForm scope.rosterWindowStart rosterGroup.id timelineTargetRosterDay.operationalDate calendarRevision sourceToken targetToken Nothing
                        let startOccurrenceField = surfaceFieldNameFrom @Surface.TimelineStartOccurrence fields
                        let occurrenceFields = (startOccurrenceField, startOccurrenceField)
                        case boundaryResolution of
                            RosterTimelineDropInvalid message -> respondWithMoveRosterShiftFailure scope message
                            RosterTimelineDropBoundaryFailure repeatedEndpoints selections failure ->
                                respondWithRosterSlotCopyBoundaryFailure scope "move" intentForm occurrenceFields repeatedEndpoints selections failure
                            RosterTimelineDropBoundaryReady boundaries -> do
                                let updatedSlot = timelineSourceSlot
                                        |> set #rosterDayId (unpackId timelineTargetRosterDay.id)
                                        |> set #rosterLaneId (unpackId timelineTargetSlotDefinition.id)
                                        |> set #slotSortOrder timelineTargetSlotDefinition.sortOrder
                                        |> set #rowIndex timelineTargetRowIndex
                                        |> applyRosterSlotBoundaries boundaries
                                mutationResult <- moveRosterSlotMutation scope timelineSourceRosterDay timelineTargetRosterDay timelineSourceSlot updatedSlot
                                case mutationResult of
                                    Left message -> respondWithMoveRosterShiftFailure scope message
                                    Right mutationResult -> do
                                        let shouldWarnSourceTimesheetUnchanged = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                        respondToRosterTimelineSlotMove scope mutationResult shouldWarnSourceTimesheetUnchanged

    action currentAction@DuplicateRosterShiftToDayAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        case RosterIntent.parseDuplicateRosterShiftToDayIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure scope (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                if parseRosterShiftDropDestinationToken targetToken == Just DeleteRosterShiftDestination
                    then do
                        result <- validateRosterShiftDeleteDropIntent scope sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure scope message
                            Right rosterSlot -> respondWithDeleteRosterSlotConfirmation rosterSlot (param @Calendar.Day "anchorDate") (param @Int "rosterCalendarRevision")
                    else do
                        result <- validateDuplicateRosterShiftIntent scope sourceToken targetToken
                        case result of
                            Left message -> respondWithMoveRosterShiftFailure scope message
                            Right resultValue@MoveRosterShiftIntent { sourceSlot, sourceRosterDay, targetRosterDay, targetSlotDefinition, targetRowIndex } -> do
                                let startOccurrenceValue = surfaceFieldValue @Surface.CopyStartOccurrence fields
                                let endOccurrenceValue = surfaceFieldValue @Surface.CopyEndOccurrence fields
                                case copyOccurrenceSelectionsFromValues startOccurrenceValue endOccurrenceValue of
                                    Left message -> respondWithMoveRosterShiftFailure scope message
                                    Right selections -> do
                                        boundaryResolution <- resolveRosterDayDropBoundaries resultValue selections
                                        let intentForm = rosterDuplicateShiftIntentForm scope.rosterWindowStart rosterGroup.id (surfaceFieldValue @Surface.RosterCalendarRevision fields) sourceToken targetToken Nothing Nothing
                                        let occurrenceFields = (surfaceFieldNameFrom @Surface.CopyStartOccurrence fields, surfaceFieldNameFrom @Surface.CopyEndOccurrence fields)
                                        case boundaryResolution of
                                            RosterDayDropBoundaryFailure repeatedEndpoints failure ->
                                                respondWithRosterSlotCopyBoundaryFailure scope "duplicate" intentForm occurrenceFields repeatedEndpoints selections failure
                                            RosterDayDropBoundaryReady copiedBoundariesSlot ->
                                                case copyRosterShiftAssignment sourceSlot (newRecord @RosterSlot) of
                                                    Left message -> respondWithMoveRosterShiftFailure scope message
                                                    Right assignmentSlot -> do
                                                        let copiedSlot = assignmentSlot
                                                                |> set #rosterDayId (unpackId targetRosterDay.id)
                                                                |> set #rosterLaneId (unpackId targetSlotDefinition.id)
                                                                |> set #slotSortOrder targetSlotDefinition.sortOrder
                                                                |> set #rowIndex targetRowIndex
                                                                |> set #startsAt copiedBoundariesSlot.startsAt
                                                                |> set #endsAt copiedBoundariesSlot.endsAt
                                                                |> set #timezone copiedBoundariesSlot.timezone
                                                                |> set #shiftTypeId sourceSlot.shiftTypeId
                                                        mutationResult <- saveRosterSlotMutation scope targetRosterDay Nothing copiedSlot
                                                        case mutationResult of
                                                            Left message -> respondWithMoveRosterShiftFailure scope message
                                                            Right mutationResult ->
                                                                respondToRosterSlotMutation scope targetRosterDay targetRowIndex mutationResult "Roster shift duplicated."

    action currentAction@DropRosterStaffAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterMutationScope rosterGroup.id
        case RosterIntent.parseDropRosterStaffIntentParams of
            Left errors -> respondWithMoveRosterShiftFailure scope (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                let sourceToken = surfaceFieldValue @SurfaceInteraction.SourceItemKey fields
                let targetToken = surfaceFieldValue @SurfaceInteraction.TargetDropzoneKey fields
                result <- validateRosterStaffDropIntent scope sourceToken targetToken
                case result of
                    Left message -> respondWithMoveRosterShiftFailure scope message
                    Right RosterStaffExistingShiftDropIntent { staffDropStaff, staffDropSlot, staffDropRosterDay } -> do
                        let updatedSlot = staffDropSlot |> applyRosterShiftAssignment (StaffAssignment staffDropStaff.id)
                        mutationResult <- updateRosterSlotMutation scope staffDropRosterDay staffDropSlot updatedSlot False
                        case mutationResult of
                            Left message -> respondWithMoveRosterShiftFailure scope message
                            Right mutationResult -> do
                                let warningToast = mutationResult.liveMutationValue.rosterSlotMutationShouldWarnSourceTimesheetUnchanged
                                respondToRosterSlotMutation scope staffDropRosterDay updatedSlot.rowIndex mutationResult $
                                    if warningToast then "Staff assigned. A timesheet entry was already created from this roster shift. The timesheet snapshot was not changed." else "Staff assigned."
                    Right RosterStaffCreateShiftDropIntent { staffDropStaff, staffDropRosterDay, staffDropSlotDefinition, staffDropRowIndex } -> do
                        payInvalidStaffIds <- fetchStaffPayConfigurationRequiredIds [staffDropStaff]
                        if coerce staffDropStaff.id `Set.member` payInvalidStaffIds
                            then respondWithMoveRosterShiftFailure scope "Resolve pay configuration for the selected staff member before adding a roster shift."
                            else respondWithRosterShiftCreateDialogOob scope staffDropRosterDay staffDropSlotDefinition staffDropRowIndex emptyRosterShiftDialogValues { rosterShiftSelectedAssignment = Just (StaffAssignment staffDropStaff.id) }

    action currentAction@UpdateRosterWarningPreferenceAction = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterActionScope rosterGroup.id
        case RosterAction.parseToggleRosterWarningsActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow scope
            Right fields -> do
                _ <- upsertCurrentUserShowRosterWarnings (surfaceFieldValue @Surface.ShowRosterWarnings fields)
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate scope rosterGridStructuralAndStaffPanelFragments (successToast "Roster warning preference saved.")
                    else do
                        setSuccessMessage "Roster warning preference saved."
                        redirectToRosterWindow scope

    action currentAction@UpdateRosterWageEstimatePreferenceAction = runBepis currentAction BepisPreferenceAction do
        accessDeniedUnless (hasRole VenueAdmin)
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterActionScope rosterGroup.id
        case RosterAction.parseToggleRosterWageEstimatesActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow scope
            Right fields -> do
                _ <- upsertCurrentUserShowWageEstimates (surfaceFieldValue @Surface.ShowWageEstimates fields)
                if isHtmxRequest
                    then respondWithRosterFragmentsUpdate scope rosterGridStructuralAndStaffPanelFragments (successToast "Roster wage estimate preference saved.")
                    else do
                        setSuccessMessage "Roster wage estimate preference saved."
                        redirectToRosterWindow scope

    action currentAction@UpdateRosterOwnLiveShiftHighlightPreferenceAction = runBepis currentAction BepisPreferenceAction do
        rosterGroup <- resolveRequestedRosterGroup
        scope <- rosterActionScope rosterGroup.id
        case RosterAction.parseToggleRosterOwnLiveShiftHighlightActionParams of
            Left errors -> do
                let errorMessage = rosterSurfaceRequestErrorMessage errors
                if isHtmxRequest
                    then respondWithRosterToast errorMessage "app-toast-error"
                    else setErrorMessage errorMessage >> redirectToRosterWindow scope
            Right fields -> do
                _ <- upsertCurrentUserHighlightOwnLiveShifts (surfaceFieldValue @Surface.HighlightOwnLiveShifts fields)
                if isHtmxRequest
                    then respondWithRosterOwnHighlightPreferenceUpdate scope (successToast "Own Published-shift highlight preference saved.")
                    else do
                        setSuccessMessage "Own Published-shift highlight preference saved."
                        redirectToRosterWindow scope

    action currentAction@NewRosterSlotDialogAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        rosterDay <- fetchRosterDayForDialog rosterDayId
        scope <- rosterActionScopeForDay rosterDay
        authorizeRosterSlotCreateContext scope rosterDay rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterDayId rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition
        shiftTypes <- fetchCurrentVenueRosterShiftTypesForDialog
        if null shiftTypes
            then respondWithRosterToast "Create at least one shift type in Admin > Shift Types before adding roster shifts." "app-toast-error"
            else do
                venueConfig <- fetchVenueConfig
                renderRosterShiftDialogForCreate scope rosterDay slotDefinition rowIndex (defaultRosterShiftDialogValuesForVenue venueConfig)

    action currentAction@EditRosterSlotDialogAction { rosterSlotId } = runBepis currentAction BepisDialogAction do
        ensureManagerRole
        ensureVenueWritable
        rosterSlot <- fetchRosterSlotForEdit rosterSlotId
        authorizeRosterSlotForEdit rosterSlot
        rosterDay <- fetchRosterSlotEditContext rosterSlot
        scope <- rosterActionScopeForDay rosterDay
        authorizeRosterSlotEditContext scope rosterSlot rosterDay
        renderRosterShiftDialogForEdit scope rosterSlot rosterDay (rosterShiftDialogValuesFromSlot rosterSlot)

    action currentAction@CreateRosterSlotAction { rosterDayId, rosterWeekSlotDefinitionId, rowIndex } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterDay <- fetchRosterDayForMutation rosterDayId
        scope <- rosterMutationScopeForDay rosterDay
        requireRosterShiftCalendarAppShellContext (parseAppShellActionParams @CreateRosterShiftOverlay)
        authorizeRosterSlotCreateContext scope rosterDay rowIndex
        slotDefinition <- fetchRosterSlotDefinitionForCreate rosterDayId rosterWeekSlotDefinitionId
        authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition
        createRosterShift scope rosterDay slotDefinition rowIndex rosterShiftDialogSubmissionFromRequest >>= \case
            Left values -> renderRosterShiftDialogForCreate scope rosterDay slotDefinition rowIndex values
            Right mutationResult -> respondToRosterSlotMutation scope rosterDay rowIndex mutationResult "Roster shift saved."

    action currentAction@UpdateRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        rosterSlot <- fetchRosterSlotForEdit rosterSlotId
        authorizeRosterSlotForEdit rosterSlot
        rosterDay <- fetchRosterSlotEditContext rosterSlot
        scope <- rosterMutationScopeForDay rosterDay
        requireRosterShiftCalendarAppShellContext (parseAppShellActionParams @UpdateRosterShiftOverlay)
        authorizeRosterSlotEditContext scope rosterSlot rosterDay
        editRosterShift scope rosterDay rosterSlot rosterShiftDialogSubmissionFromRequest >>= \case
            Left values -> renderRosterShiftDialogForEdit scope rosterSlot rosterDay values
            Right completion -> respondToRosterShiftEdit scope completion

    action currentAction@ShowRosterSlotDeleteConfirmationAction { rosterSlotId } = runBepis currentAction BepisFormAction do
        ensureManagerRole
        ensureVenueWritable
        case parseAppShellActionParams @OpenRosterSlotDeleteConfirmationDialog of
            Left errors -> respondRosterBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                rosterSlot <- fetchRosterSlotForEdit rosterSlotId
                authorizeRosterSlotForEdit rosterSlot
                rosterDay <- fetchRosterSlotEditContext rosterSlot
                scope <- rosterMutationScopeForDayAt
                    (surfaceFieldValue @AnchorDateField fields)
                    (surfaceFieldValue @RosterCalendarRevisionField fields)
                    rosterDay
                authorizeRosterSlotDeleteContext scope rosterDay
                respondHtmlProfiled
                    ( renderDeleteRosterSlotConfirmation
                        rosterSlot
                        (surfaceFieldValue @AnchorDateField fields)
                        (surfaceFieldValue @RosterCalendarRevisionField fields)
                    )

    action currentAction@DeleteRosterSlotAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        case parseAppShellActionParams @ConfirmDeleteRosterSlotOverlay of
            Left errors -> respondRosterBadRequest (rosterSurfaceRequestErrorMessage errors)
            Right fields -> do
                rosterSlot <- fetchRosterSlotForEdit rosterSlotId
                authorizeRosterSlotForEdit rosterSlot
                rosterDay <- fetchRosterSlotEditContext rosterSlot
                scope <- rosterMutationScopeForDayAt
                    (surfaceFieldValue @AnchorDateField fields)
                    (surfaceFieldValue @RosterCalendarRevisionField fields)
                    rosterDay
                authorizeRosterSlotDeleteContext scope rosterDay
                deleteRosterSlotMutation scope rosterDay rosterSlot >>= \case
                    Left message -> respondWithMoveRosterShiftFailure scope message
                    Right mutationResult -> respondToRosterSlotUpdate scope mutationResult [(rosterSlot.rosterDayId, rosterSlot.rowIndex)] False

requireRosterShiftCalendarAppShellContext :: (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) => Either [SurfaceRequestFieldError] fields -> IO ()
requireRosterShiftCalendarAppShellContext requestFields =
    case requestFields of
        Right _ -> pure ()
        Left errors -> do
            let contextErrors = filter ((`elem` ["anchorDate", "rosterCalendarRevision"]) . (.surfaceRequestFieldErrorName)) errors
            unless (null contextErrors) do
                setErrorMessage (surfaceRequestFieldErrorsMessage contextErrors)
                accessDeniedUnless False

requireCurrentRosterCalendarRevision :: (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) => VenueConfig -> Int -> IO ()
requireCurrentRosterCalendarRevision venueConfig expectedRevision =
    when (expectedRevision /= venueConfig.rosterCalendarRevision) $
        respondAndStop
            ( Wai.responseLBS
                status409
                [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                "The roster calendar changed. Review the refreshed window and try again."
            )

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

authorizeRosterSlotCreateContext :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> Int -> IO ()
authorizeRosterSlotCreateContext scope rosterDay rowIndex = do
    ensureRosterDayIsDraftForEdit scope rosterDay
    accessDeniedUnless (not rosterDay.isClosed)
    accessDeniedUnless (rowIndex >= 0)

authorizeRosterSlotDefinitionForCreate :: (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) => RosterDay -> RosterLane -> IO ()
authorizeRosterSlotDefinitionForCreate rosterDay slotDefinition = do
    accessDeniedUnless (slotDefinition.rosterDayId == unpackId rosterDay.id)
    accessDeniedUnless (isNothing slotDefinition.deletedAt)

authorizeRosterSlotForEdit :: (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) => RosterSlot -> IO ()
authorizeRosterSlotForEdit rosterSlot =
    accessDeniedUnless (isNothing rosterSlot.deletedAt)

authorizeRosterSlotEditContext :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterSlot -> RosterDay -> IO ()
authorizeRosterSlotEditContext scope rosterSlot rosterDay = do
    accessDeniedUnless (not rosterDay.isClosed)
    unless (rosterDay.publicationState == Published && rosterShiftIsOpen rosterSlot) do
        ensureRosterDayIsDraftForEdit scope rosterDay

authorizeRosterSlotDeleteContext :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO ()
authorizeRosterSlotDeleteContext scope rosterDay = do
    ensureRosterDayIsDraftForEdit scope rosterDay
    accessDeniedUnless (not rosterDay.isClosed)

ensureRosterDayIsDraftForEdit :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterDay -> IO ()
ensureRosterDayIsDraftForEdit scope rosterDay =
    when (rosterDay.publicationState /= Draft) do
        let errorMessage = "Published roster windows are read-only. Return it to Draft to make changes."
        earlyReturn $ if isHtmxRequest
            then respondWithRosterToast errorMessage "app-toast-error"
            else do
                setErrorMessage errorMessage
                redirectToRosterWindow scope

respondWithMoveRosterShiftFailure :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ResponseReceived
respondWithMoveRosterShiftFailure scope message =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (errorToast message))
        else do
            setErrorMessage message
            redirectToRosterWindow scope

respondWithSilentRosterNoOp :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> IO ResponseReceived
respondWithSilentRosterNoOp scope =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            respondHtmlProfiled mempty
        else redirectToRosterWindow scope

renderRosterShiftDialogForCreate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterDay -> RosterLane -> Int -> RosterShiftDialogValues -> IO ResponseReceived
renderRosterShiftDialogForCreate scope rosterDay slotDefinition rowIndex values =
    respondHtmlProfiled =<< rosterShiftDialogForCreateHtml scope rosterDay slotDefinition rowIndex values

respondWithRosterShiftCreateDialogOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterDay -> RosterLane -> Int -> RosterShiftDialogValues -> IO ResponseReceived
respondWithRosterShiftCreateDialogOob scope rosterDay slotDefinition rowIndex values = do
    dialog <- rosterShiftDialogForCreateHtml scope rosterDay slotDefinition rowIndex values
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {dialog}
        </div>
    |]

renderRosterShiftDialogForEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterSlot -> RosterDay -> RosterShiftDialogValues -> IO ResponseReceived
renderRosterShiftDialogForEdit scope rosterSlot rosterDay values =
    respondHtmlProfiled =<< rosterShiftDialogForEditHtml scope rosterSlot rosterDay values

resolveRosterPageGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Maybe (RosterGroup, Bool))
resolveRosterPageGroup = do
    let requestedRosterGroupId = paramOrNothing "rosterGroupId"
    rosterGroups <- fetchViewableRosterGroups
    pure $ case requestedRosterGroupId of
        Nothing -> (\rosterGroup -> (rosterGroup, True)) <$> listToMaybe rosterGroups
        Just rosterGroupId ->
            case find ((== rosterGroupId) . (.id)) rosterGroups of
                Just rosterGroup -> Just (rosterGroup, True)
                Nothing          -> (\rosterGroup -> (rosterGroup, False)) <$> listToMaybe rosterGroups

resolveRequestedRosterGroup :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO RosterGroup
resolveRequestedRosterGroup = do
    let requestedRosterGroupId = paramOrNothing "rosterGroupId"
    rosterGroups <- fetchViewableRosterGroups
    let maybeRosterGroup = maybe (listToMaybe rosterGroups) (\rosterGroupId -> find ((== rosterGroupId) . (.id)) rosterGroups) requestedRosterGroupId
    accessDeniedUnless (isJust maybeRosterGroup)
    pure (fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") maybeRosterGroup)

renderNoRosterGroupPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
renderNoRosterGroupPage = do
    setTitle "Roster"
    noRosterGroupPasskeySetupPrompt <- passkeySetupPromptFromSession
    noRosterGroupPasskeyStrongAuthenticationRequired <- currentUserRequiresMandatoryPasskey
    let view = NoRosterGroupView { .. }
    if isHtmxRequest
        then respondHtmlProfiled (renderNoRosterGroupShell view)
        else renderProfiled view

fetchRosterDayForMutation :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterDay -> IO RosterDay
fetchRosterDayForMutation rosterDayId = do
    venueConfig <- fetchVenueConfig
    requireCurrentRosterCalendarRevision venueConfig (param @Int "rosterCalendarRevision")
    fetchRosterDayForRequest rosterDayId

fetchRosterDayForDialog :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterDay -> IO RosterDay
fetchRosterDayForDialog = fetchRosterDayForRequest

fetchRosterDayForRequest :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterDay -> IO RosterDay
fetchRosterDayForRequest rosterDayId = do
    existing <- query @RosterDay
        |> filterWhere (#id, rosterDayId)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
    case existing of
        Just rosterDay
            | rosterDay.publicationState == Draft -> do
                scope <- rosterActionScopeForDay rosterDay
                _ <- materializeRosterWindowMutation scope
                fetch rosterDayId
            | otherwise -> rosterActionScopeForDay rosterDay >> pure rosterDay
        Nothing -> do
            let rosterGroupId = Id (param @UUID "rosterGroupId")
            let operationalDate = param @Calendar.Day "operationalDate"
            rosterGroup <- query @RosterGroup
                |> filterWhere (#id, rosterGroupId)
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#isActive, True)
                |> fetchOne
            scope <- rosterActionScope rosterGroup.id
            accessDeniedUnless (operationalDate >= scope.rosterWindowStart && operationalDate < scope.rosterWindowEnd)
            accessDeniedUnless (rosterDayId == projectedRosterDayId rosterGroup.id operationalDate)
            _ <- materializeRosterWindowMutation scope
            rosterDay <- fetch rosterDayId
            accessDeniedUnless (rosterDay.operationalDate == operationalDate)
            pure rosterDay

rosterActionScopeForDay :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> IO RosterWindowScope
rosterActionScopeForDay rosterDay = do
    ensureRecordInCurrentVenue rosterDay.venueId
    scope <- rosterActionScope (Id rosterDay.rosterGroupId)
    accessDeniedUnless (rosterDay.operationalDate >= scope.rosterWindowStart && rosterDay.operationalDate < scope.rosterWindowEnd)
    pure scope

rosterMutationScopeForDay :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterDay -> IO RosterWindowScope
rosterMutationScopeForDay rosterDay =
    rosterMutationScopeForDayAt
        (param @Calendar.Day "anchorDate")
        (param @Int "rosterCalendarRevision")
        rosterDay

rosterMutationScopeForDayAt :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Calendar.Day -> Int -> RosterDay -> IO RosterWindowScope
rosterMutationScopeForDayAt anchorDate calendarRevision rosterDay = do
    ensureRecordInCurrentVenue rosterDay.venueId
    venueConfig <- fetchVenueConfig
    requireCurrentRosterCalendarRevision venueConfig calendarRevision
    let scope = rosterWindowScopeForAnchor venueConfig (Id rosterDay.rosterGroupId) anchorDate
    accessDeniedUnless (rosterDay.operationalDate >= scope.rosterWindowStart && rosterDay.operationalDate < scope.rosterWindowEnd)
    pure scope

rosterWindowScopeForFragmentRosterDay :: (?request :: Request, ?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext) => Calendar.Day -> Id RosterDay -> IO RosterWindowScope
rosterWindowScopeForFragmentRosterDay anchorDate rosterDayId = do
    rosterDay <- fetch rosterDayId
    ensureRecordInCurrentVenue rosterDay.venueId
    let rosterGroupId = Id rosterDay.rosterGroupId
    scope <- rosterWindowScopeForRequestedAnchor rosterGroupId anchorDate
    accessDeniedUnless (rosterDay.operationalDate >= scope.rosterWindowStart)
    accessDeniedUnless (rosterDay.operationalDate < scope.rosterWindowEnd)
    pure scope

respondWithDeleteRosterSlotConfirmation :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterSlot -> Calendar.Day -> Int -> IO ResponseReceived
respondWithDeleteRosterSlotConfirmation rosterSlot anchorDate calendarRevision =
    respondHtmlProfiled [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">
            {renderDeleteRosterSlotConfirmation rosterSlot anchorDate calendarRevision}
        </div>
    |]
renderDeleteRosterSlotConfirmation :: (?context :: ControllerContext, ?request :: Request) => RosterSlot -> Calendar.Day -> Int -> Markup.Html
renderDeleteRosterSlotConfirmation rosterSlot anchorDate calendarRevision =
    renderDialogOverlay (defaultDialogOverlayConfig
        "Delete roster shift?"
        [hsx|<p class="mb-0">Delete this shift?</p>|]
        [ dialogOverlayCloseButton "Cancel"
        , OverlayButton
            { overlayButtonLabel = "Delete shift"
            , overlayButtonClass = "btn btn-danger"
            , overlayButtonAction = GeneratedDialogFormAction
                (appShellActionByMarker @ConfirmDeleteRosterSlotOverlay)
                (rosterDeleteSlotActionRoute rosterSlot.id anchorDate calendarRevision)
                []
                Nothing
            }
        ])

rosterDeleteSlotActionRoute :: Id RosterSlot -> Calendar.Day -> Int -> AppShellActionRoute
rosterDeleteSlotActionRoute rosterSlotId anchorDate calendarRevision =
    ((defaultAppShellActionRoute (rosterDeleteSlotUrl rosterSlotId anchorDate calendarRevision))
        { appShellActionRouteFields =
            [ AppShellFieldValue ("anchorDate", tshow anchorDate)
            , AppShellFieldValue ("rosterCalendarRevision", tshow calendarRevision)
            ]
        })

respondWithRemoveRosterRowConfirmation :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterDay -> RosterDayRowRemovalPreview -> IO ResponseReceived
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
                ((defaultAppShellActionRoute (pathTo (RemoveRosterRowAction rosterDay.id)))
                    { appShellActionRouteFields = [ AppShellFieldValue ("anchorDate", param @Text "anchorDate")
                        , AppShellFieldValue ("rosterCalendarRevision", param @Text "rosterCalendarRevision")
                        ]
                    , appShellActionRouteExtraAttrs = [ ("id", confirmFormId)

                        ]
                    })
                [hsx|<input type="hidden" name="confirmDeletePopulatedRow" value="true" />|]
        confirmationDialog =
            renderDialogOverlay (defaultDialogOverlayConfig
            "Delete roster row?"
            [hsx|
                    <p class="mb-2">
                        {overflowCopy} cannot be packed into another column and will be deleted.
                    </p>
                    <p class="mb-0 app-muted">
                        Shifts that fit will be moved into the bottom of the remaining columns from left to right.
                    </p>
                |]
            [ dialogOverlayCloseButton "Cancel"
                    , OverlayButton
                        { overlayButtonLabel = "Delete row"
                        , overlayButtonClass = "btn btn-danger"
                        , overlayButtonAction = OverlaySubmitFormAction confirmFormId
                        }
                    ])


markStaleRosterCalendarResponseForRefresh :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
markStaleRosterCalendarResponseForRefresh =
    when isHtmxRequest $
        forM_ (paramOrNothing @Int "rosterCalendarRevision") \expectedRevision -> do
            venueConfig <- fetchVenueConfig
            when (expectedRevision /= venueConfig.rosterCalendarRevision) $
                respondAndStop
                    ( Wai.responseLBS
                        status409
                        [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                        "The roster calendar changed. Review the refreshed window and try again."
                    )

redirectToRosterWindow :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> IO ResponseReceived
redirectToRosterWindow scope =
    redirectToPath (rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId)

rosterActionScope :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> IO RosterWindowScope
rosterActionScope rosterGroupId =
    rosterWindowScopeForRequestedAnchor rosterGroupId (param @Calendar.Day "anchorDate")

rosterMutationScope :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> IO RosterWindowScope
rosterMutationScope rosterGroupId = do
    venueConfig <- fetchVenueConfig
    requireCurrentRosterCalendarRevision venueConfig (param @Int "rosterCalendarRevision")
    pure (rosterWindowScopeForAnchor venueConfig rosterGroupId (param @Calendar.Day "anchorDate"))

rosterCopyActionDates :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (Day, Day)
rosterCopyActionDates = do
    venueConfig <- fetchVenueConfig
    let sourceAnchorDate = param @Calendar.Day "sourceAnchorDate"
    let targetAnchorDate = param @Calendar.Day "targetAnchorDate"
    let calendarRevision = param @Int "rosterCalendarRevision"
    let resolve = startOfWeekFor venueConfig.rosterWeekStartsOn
    requireCurrentRosterCalendarRevision venueConfig calendarRevision
    pure (resolve sourceAnchorDate, resolve targetAnchorDate)

rosterWindowScopeForRequestedAnchor :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> Calendar.Day -> IO RosterWindowScope
rosterWindowScopeForRequestedAnchor rosterGroupId anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (rosterWindowScopeForAnchor venueConfig rosterGroupId anchorDate)

buildRosterTimelineTodayUrl :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO Text
buildRosterTimelineTodayUrl rosterGroupId = do
    venueConfig <- fetchVenueConfig
    today <- utctDay <$> getCurrentTime
    pure (rosterTimelineWindowUrl today rosterGroupId)

renderRosterWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> IO ResponseReceived
renderRosterWeekPage requestedScope =
    profileActionSpan "roster.page.render" do
        setTitle "Roster"
        rosterGroups <- profileActionSpan "roster.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
        currentRosterGroup <- profileActionSpan "roster.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just requestedScope.rosterWindowRosterGroupId))
        accessDeniedUnless (currentRosterGroup.id == requestedScope.rosterWindowRosterGroupId)
        rosterDataOrNothing <- profileActionSpan "roster.page.fetch_read_model" (fetchVisibleRosterReadModel requestedScope)
        passkeySetupPrompt <- profileActionSpan "roster.page.passkey_prompt" passkeySetupPromptFromSession
        passkeyStrongAuthenticationRequired <- profileActionSpan "roster.page.passkey_policy" currentUserRequiresMandatoryPasskey
        timelineTodayUrl <- profileActionSpan "roster.page.timeline_today_url" (buildRosterTimelineTodayUrl currentRosterGroup.id)

        case rosterDataOrNothing of
            Just rosterData ->
                let rosterPageGridModel =
                        (rosterGridRenderModelFromProjection rosterData)
                            { gridRosterGroups = rosterGroups
                            , gridCurrentRosterGroup = currentRosterGroup
                            , gridTimelineTodayUrl = Just timelineTodayUrl
                            }
                 in profileActionSpan "roster.page.respond" $
                        respondWithRosterWeekView ShowView { rosterPageGridModel, passkeySetupPrompt, passkeyStrongAuthenticationRequired }
            Nothing ->
                externalRuntimeInvariantFailure PersistedRuntimeInvariant "Roster date range could not be projected for the selected roster group"

respondWithRosterWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => ShowView -> IO ResponseReceived
respondWithRosterWeekView showView =
    profileActionSpan "roster.page.render_response" do
        if isHtmxRequest
            then respondHtmlProfiled (renderRosterWeekShell showView)
            else renderProfiled showView

passkeySetupPromptFromSession :: (?request :: Request) => IO (Maybe PasskeySetupPromptMode)
passkeySetupPromptFromSession =
    fmap (>>= passkeySetupPromptModeFromValue) (getSessionAndClear @Text passkeySetupPromptSessionKey)

renderRosterWeekOverviewFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Calendar.Day -> Id RosterGroup -> IO Markup.Html
renderRosterWeekOverviewFragment weekStartDate rosterGroupId = do
    venueConfig <- fetchVenueConfig
    todayDate <- utctDay <$> getCurrentTime
    let focusDate = initialOverviewFocusDate weekStartDate todayDate
    weekOverviewDays <- profileActionSpan "roster.build_month_overview" (buildRosterMonthOverviewDays venueConfig rosterGroupId focusDate)
    pure (renderWeekOverviewPanelFragment rosterGroupId weekStartDate todayDate weekOverviewDays (buildRosterViewCapabilities Nothing))

respondToRosterSlotDefinitionError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ResponseReceived
respondToRosterSlotDefinitionError scope errorMessage =
    if isHtmxRequest
        then respondWithRosterToast errorMessage "app-toast-error"
        else do
            setErrorMessage errorMessage
            redirectToRosterWindow scope

respondToRosterSlotDefinitionSuccess :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> LiveMutationResult value -> Text -> IO ResponseReceived
respondToRosterSlotDefinitionSuccess scope mutationResult successMessage =
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                scope
                mutationResult.liveMutationTouchedResources
                rosterGridInnerAndStaffPanelFragments
                mempty
        else do
            setSuccessMessage successMessage
            redirectToRosterWindow scope
