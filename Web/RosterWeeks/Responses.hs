{-# LANGUAGE ExplicitNamespaces #-}

module Web.RosterWeeks.Responses
    ( respondToRosterSlotMutation
    , respondToRosterSlotMove
    , respondToRosterTimelineSlotMove
    , respondToRosterSlotUpdate
    , respondToRosterShiftEdit
    , respondWithRosterContent
    , respondWithRosterContentError
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterDialogOverlay
    , respondWithRosterFragments
    , respondWithRosterFragmentsUpdate
    , respondWithRosterOwnHighlightPreferenceUpdate
    , respondWithRosterResourceInvalidation
    , respondWithRosterToast
    , respondWithRosterTemplateApplicationUpdate
    , respondWithRosterTemplateCaptureUpdate
    , respondWithRosterTemplateDeleteUpdate
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchViewableRosterGroup,
                                        fetchViewableRosterGroups)
import Application.Helper.SurfaceResource (LiveMutationResult (..), SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import qualified Data.UUID as UUID
import qualified IHP.HSX.Markup as Markup
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..))
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterMountedFragmentForProjection,
                                        rosterMountedFragmentPlanFromRenderData,
                                        rosterSurfaceFragmentKeys,
                                        rosterSurfaceScope)
import Web.RosterWeeks.Mutations (type RosterSlotMutationResult)
import Web.RosterWeeks.Paths (rosterWindowUrl)
import Web.RosterWeeks.Projection (RosterMutationProjection (..),
                                    rosterMutationMountedProjections,
                                    rosterGridInnerAndStaffPanelFragments)
import Web.RosterWeeks.ShiftWorkflow (RosterShiftEditCompletion (..))
import Web.RosterWeeks.RenderData (currentRosterTimelineDate,
                                   fetchVisibleRosterReadModel,
                                   renderRosterProjectionFragmentWithMode,
                                   renderVisibleRosterReadModelFragment,
                                   rosterGridRenderModelFromProjection)
import Web.RosterWeeks.Types (RosterGridRenderModel (..),
                              RosterProjectionFragment (..),
                              RosterRenderData (..))
import Web.View.RosterWeeks.Grid (renderrosterContentLiveFragment,
                                  renderrosterContentLiveFragmentOob)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServicePanelFragmentOob)

respondToRosterSlotMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterDay -> Int -> LiveMutationResult RosterSlotMutationResult -> Text -> IO ResponseReceived
respondToRosterSlotMutation scope rosterDay rowIndex mutationResult successMessage = do
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation [(unpackId rosterDay.id, rowIndex)])
    if isHtmxRequest
        then
            respondWithRosterResourceInvalidation
                scope
                mutationResult.liveMutationTouchedResources
                mountedProjections
                (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast successMessage))
        else do
            setSuccessMessage successMessage
            redirectToPath (rosterWindowUrl scope.rosterWindowStart scope.rosterWindowRosterGroupId)

respondToRosterSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ResponseReceived
respondToRosterSlotMove scope mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation impactedRowKeys)
    respondWithRosterResourceInvalidation
        scope
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterTimelineSlotMove :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> LiveMutationResult RosterSlotMutationResult -> Bool -> IO ResponseReceived
respondToRosterTimelineSlotMove scope mutationResult shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections RosterTimelineMutation
    respondWithRosterResourceInvalidation
        scope
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (renderDialogOverlayClearOob <> renderToastOob ToastBottomCenter (successToast "Roster shift moved.") <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

respondToRosterShiftEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> RosterShiftEditCompletion -> IO ResponseReceived
respondToRosterShiftEdit scope completion =
    respondToRosterSlotUpdate scope completion.rosterShiftEditMutation completion.rosterShiftEditImpactedRows completion.rosterShiftEditWarnSourceTimesheetUnchanged

respondToRosterSlotUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> LiveMutationResult RosterSlotMutationResult -> [(UUID.UUID, Int)] -> Bool -> IO ResponseReceived
respondToRosterSlotUpdate scope mutationResult impactedRowKeys shouldWarnSourceTimesheetUnchanged = do
    mountedProjections <- rosterMutationMountedProjections (RosterRowsMutation impactedRowKeys)
    respondWithRosterResourceInvalidation
        scope
        mutationResult.liveMutationTouchedResources
        mountedProjections
        (renderDialogOverlayClearOob <> sourceTimesheetWarningToast shouldWarnSourceTimesheetUnchanged)

sourceTimesheetWarningToast :: (?context :: ControllerContext, ?request :: Request) => Bool -> Markup.Html
sourceTimesheetWarningToast shouldWarn =
    if shouldWarn
        then renderToastOob ToastBottomCenter (errorToast "A timesheet entry was already created from this roster shift. The timesheet snapshot was not changed. Edit the timesheet entry directly.")
        else mempty

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> IO ResponseReceived
respondWithRosterContent scope = do
    maybeHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionContent
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("roster_read_model_miss: rosterGroupId=" <> tshow scope.rosterWindowRosterGroupId <> " windowStart=" <> tshow scope.rosterWindowStart)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithRosterFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> [RosterProjectionFragment] -> ToastOverlayConfig -> IO ResponseReceived
respondWithRosterFragmentsUpdate scope fragments toast =
    respondWithRosterFragments scope fragments (renderToastOob ToastBottomCenter toast)

respondWithRosterOwnHighlightPreferenceUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> ToastOverlayConfig -> IO ResponseReceived
respondWithRosterOwnHighlightPreferenceUpdate scope toast = do
    rosterData <- fetchVisibleRosterReadModel scope
    let selfServicePanel = rosterData >>= (.staffSelfServicePanel)
    respondWithRosterFragments
        scope
        rosterGridInnerAndStaffPanelFragments
        (renderRosterStaffSelfServicePanelFragmentOob selfServicePanel <> renderToastOob ToastBottomCenter toast)

respondWithRosterFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> [RosterProjectionFragment] -> Markup.Html -> IO ResponseReceived
respondWithRosterFragments scope fragments extraHtml =
    respondWithRosterActorInvalidation scope fragments extraHtml

respondWithRosterActorInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> [RosterProjectionFragment] -> Markup.Html -> IO ResponseReceived
respondWithRosterActorInvalidation windowScope fragments extraHtml = do
    let scope = rosterFrontendScopeValue windowScope
    setHeader ("HX-Reswap", "none")
    setActorLocalFragmentsRefresh (rosterSurfaceScope scope) (rosterSurfaceFragmentKeys (map (rosterMountedFragmentForProjection scope) (nub fragments)))
    respondHtmlProfiled extraHtml

respondWithRosterResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> [RosterProjectionFragment] -> Markup.Html -> IO ResponseReceived
respondWithRosterResourceInvalidation windowScope touchedResources fragments extraHtml = do
    let scope = rosterFrontendScopeValue windowScope
    let mountedFragments = map (rosterMountedFragmentForProjection scope) (nub fragments)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources mountedFragments
    respondHtmlProfiled extraHtml

respondWithRosterDialogOverlay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Markup.Html -> IO ResponseReceived
respondWithRosterDialogOverlay scope dialog =
    respondWithRosterResourceInvalidation scope Set.empty [] [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">{dialog}</div>
    |]

respondWithRosterCompleteResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> Markup.Html -> IO ResponseReceived
respondWithRosterCompleteResourceInvalidation windowScope touchedResources extraHtml = do
    prepareRosterCompleteResourceInvalidation windowScope touchedResources
    respondHtmlProfiled extraHtml

prepareRosterCompleteResourceInvalidation :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ()
prepareRosterCompleteResourceInvalidation windowScope touchedResources = do
    maybeRosterData <- fetchVisibleRosterReadModel windowScope
    case maybeRosterData of
        Nothing -> do
            let scope = rosterFrontendScopeValue windowScope
            setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources [rosterMountedFragmentForProjection scope RosterProjectionContent]
        Just rosterData -> do
            let scope = rosterFrontendScopeValue rosterData.rosterWindowScope
                plan = rosterMountedFragmentPlanFromRenderData (isJust rosterData.templateLibrary) rosterData.rosterDays rosterData.renderIndexes
            setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources (rosterCandidateMountedFragments scope plan)
    setHeader ("HX-Reswap", "none")

respondWithRosterTemplateApplicationUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ResponseReceived
respondWithRosterTemplateApplicationUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template applied.")}
    |]

respondWithRosterTemplateCaptureUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ResponseReceived
respondWithRosterTemplateCaptureUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template saved.")}
    |]

respondWithRosterTemplateDeleteUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ResponseReceived
respondWithRosterTemplateDeleteUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template deleted.")}
    |]

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> IO ResponseReceived
respondWithRosterContentOob scope = do
    let rosterGroupId = scope.rosterWindowRosterGroupId
    rosterGroups <- fetchViewableRosterGroups
    currentRosterGroupOrNothing <- fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") currentRosterGroupOrNothing
    rosterData <- fetchVisibleRosterReadModel scope
    case rosterData of
        Nothing -> do
            TextIO.putStrLn ("roster_read_model_miss_oob: rosterGroupId=" <> tshow rosterGroupId <> " windowStart=" <> tshow scope.rosterWindowStart)
            respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just rosterData ->
            respondHtmlProfiled $
                renderrosterContentLiveFragmentOob
                    (rosterGridRenderModelFromProjection rosterData)
                        { gridRosterGroups = rosterGroups
                        , gridCurrentRosterGroup = currentRosterGroup
                        }

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Set.Set SurfaceResourceValue -> Text -> IO ResponseReceived
respondWithRosterContentUpdate scope touchedResources successMessage =
    respondWithRosterCompleteResourceInvalidation
        scope
        touchedResources
        (renderToastOob ToastBottomCenter (successToast successMessage))

respondWithRosterContentError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Text -> IO ResponseReceived
respondWithRosterContentError scope errorMessage = do
    respondWithRosterContentToast scope True (errorToast errorMessage)

respondWithRosterContentToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => RosterWindowScope -> Bool -> ToastOverlayConfig -> IO ResponseReceived
respondWithRosterContentToast scope publishAttempted toast = do
    let rosterGroupId = scope.rosterWindowRosterGroupId
    rosterGroups <- fetchViewableRosterGroups
    currentRosterGroupOrNothing <- fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") currentRosterGroupOrNothing
    rosterData <- fetchVisibleRosterReadModel scope
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just rosterData ->
                    renderrosterContentLiveFragment
                        (rosterGridRenderModelFromProjection rosterData)
                            { gridRosterGroups = rosterGroups
                            , gridCurrentRosterGroup = currentRosterGroup
                            , gridPublishAttempted = publishAttempted
                            }
            , renderToastOob ToastBottomCenter toast
            ]

rosterFrontendScopeValue :: (?request :: Request) => RosterWindowScope -> RosterWeekScopeValue
rosterFrontendScopeValue scope =
    RosterWeekScopeValue
        { rosterWeekVenueId = unpackId scope.rosterWindowVenueId
        , rosterWeekGroupId = scope.rosterWindowRosterGroupId
        , rosterWeekWindowStart = scope.rosterWindowStart
        , rosterWeekWindowEnd = scope.rosterWindowEnd
        , rosterWeekCalendarRevision = scope.rosterWindowCalendarRevision
        , rosterWeekTimelineDate = currentRosterTimelineDate scope.rosterWindowStart
        }

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> Text -> IO ResponseReceived
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
