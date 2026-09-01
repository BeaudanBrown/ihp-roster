module Web.RosterWeeks.Responses
    ( respondWithRosterContent
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
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..))
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterMountedFragmentForProjection,
                                        rosterMountedFragmentPlanFromRenderData,
                                        rosterSurfaceFragmentKeys,
                                        rosterSurfaceScope)
import Web.RosterWeeks.Projection (rosterGridInnerAndStaffPanelFragments)
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

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO ()
respondWithRosterContent scope = do
    maybeHtml <- renderVisibleRosterReadModelFragment scope RosterProjectionContent
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("roster_read_model_miss: rosterGroupId=" <> tshow scope.rosterWindowRosterGroupId <> " windowStart=" <> tshow scope.rosterWindowStart)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithRosterFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> [RosterProjectionFragment] -> ToastOverlayConfig -> IO ()
respondWithRosterFragmentsUpdate scope fragments toast =
    respondWithRosterFragments scope fragments (renderToastOob ToastBottomCenter toast)

respondWithRosterOwnHighlightPreferenceUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> ToastOverlayConfig -> IO ()
respondWithRosterOwnHighlightPreferenceUpdate scope toast = do
    rosterData <- fetchVisibleRosterReadModel scope
    let selfServicePanel = rosterData >>= (.staffSelfServicePanel)
    respondWithRosterFragments
        scope
        rosterGridInnerAndStaffPanelFragments
        (renderRosterStaffSelfServicePanelFragmentOob selfServicePanel <> renderToastOob ToastBottomCenter toast)

respondWithRosterFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterFragments scope fragments extraHtml =
    respondWithRosterActorInvalidation scope fragments extraHtml

respondWithRosterActorInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterActorInvalidation windowScope fragments extraHtml = do
    let scope = rosterFrontendScopeValue windowScope
    setHeader ("HX-Reswap", "none")
    setActorLocalFragmentsRefresh (rosterSurfaceScope scope) (rosterSurfaceFragmentKeys (map (rosterMountedFragmentForProjection scope) (nub fragments)))
    respondHtmlProfiled extraHtml

respondWithRosterResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterResourceInvalidation windowScope touchedResources fragments extraHtml = do
    let scope = rosterFrontendScopeValue windowScope
    let mountedFragments = map (rosterMountedFragmentForProjection scope) (nub fragments)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources mountedFragments
    respondHtmlProfiled extraHtml

respondWithRosterDialogOverlay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Blaze.Html -> IO ()
respondWithRosterDialogOverlay scope dialog =
    respondWithRosterResourceInvalidation scope Set.empty [] [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">{dialog}</div>
    |]

respondWithRosterCompleteResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithRosterCompleteResourceInvalidation windowScope touchedResources extraHtml = do
    prepareRosterCompleteResourceInvalidation windowScope touchedResources
    respondHtmlProfiled extraHtml

prepareRosterCompleteResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ()
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

respondWithRosterTemplateApplicationUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ()
respondWithRosterTemplateApplicationUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template applied.")}
    |]

respondWithRosterTemplateCaptureUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ()
respondWithRosterTemplateCaptureUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template saved.")}
    |]

respondWithRosterTemplateDeleteUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> IO ()
respondWithRosterTemplateDeleteUpdate scope touchedResources =
    respondWithRosterCompleteResourceInvalidation scope touchedResources [hsx|
        {renderDialogOverlayClearOob}
        {renderToastOob ToastBottomCenter (successToast "Template deleted.")}
    |]

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO ()
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

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithRosterContentUpdate scope touchedResources successMessage =
    respondWithRosterCompleteResourceInvalidation
        scope
        touchedResources
        (renderToastOob ToastBottomCenter (successToast successMessage))

respondWithRosterContentError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Text -> IO ()
respondWithRosterContentError scope errorMessage = do
    respondWithRosterContentToast scope True (errorToast errorMessage)

respondWithRosterContentToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> Bool -> ToastOverlayConfig -> IO ()
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

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
