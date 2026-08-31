{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero
    ( XeroView (..)
    , renderXeroSection
    , renderXeroSectionFragment
    , renderXeroReferenceSyncFragment
    ) where

{-# LANGUAGE TypeApplications #-}

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendContract.AppShell (OpenXeroPayItemImportOverlay,
                                                     OpenXeroStaffMappingsOverlay,
                                                     OpenXeroTimesheetPreparationOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Overlay.Runtime (navigationLoadingAttrs)
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values (SurfaceFields,
                                                           noSurfaceFields,
                                                           surfaceFragmentTargetId)
import Application.Helper.XeroAdminTypes
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.Presentation (xeroReferenceSyncPhaseText)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminXeroPageSurfaceImpl,
                                  adminXeroSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Admin.Xero.Connection
import Web.View.Prelude

data XeroView = XeroView
    { xeroSectionData :: XeroAdminSectionData
    }

instance View XeroView where
    html XeroView { .. } =
        let xeroPanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = "overflow-hidden"
                    , appPanelBodyClass = ""
                    , appPanelBody = renderXeroPageContentSurface (renderXeroSectionFragment xeroSectionData)
                    }
         in renderAppPage AppPageConfig
            { appPageTitle = "Xero"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageHelpTopic = Just (PageHelpTopicId "xero")
            , appPageWidthClass = ""
            , appPageBody = xeroPanel
            }

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing    -> error "Admin Xero live surface requires a current venue"

renderXeroPageContentSurface :: (?context :: ControllerContext) => Html -> Html
renderXeroPageContentSurface body =
    renderFrontendSurfaceMount (adminXeroPageSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={surfaceFragmentTargetId @Surface.AdminXeroPageSurface @Surface.AdminXeroPageContentFragment noSurfaceFields}>
            {body}
        </div>
    |]

renderXeroSection :: XeroAdminSectionData -> Html
renderXeroSection =
    renderXeroConnectionBody

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment xeroSectionData =
    renderFrontendSurfaceMount (adminXeroSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id={surfaceFragmentTargetId @Surface.AdminXeroSurface @Surface.AdminXeroShellFragment noSurfaceFields}
             hx-swap-oob={noOobSwap}>
            {renderXeroSection xeroSectionData}
        </div>
    |]

renderXeroConnectionBody :: XeroAdminSectionData -> Html
renderXeroConnectionBody XeroAdminSectionData { xeroConnection = Nothing, xeroConnectionActionsAllowed } = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            {renderXeroDisconnectedConnectionDetails xeroConnectionActionsAllowed}
        </section>
        {renderXeroReferenceSyncFragment Nothing}
    </div>
|]
renderXeroConnectionBody XeroAdminSectionData { xeroConnection = Just connection, .. } = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            <div class="d-flex flex-column gap-3">
                {renderXeroConnectionDetails connection}
                {renderXeroActionControls connection xeroConnectionActionsAllowed xeroReferenceRefreshAllowed}
            </div>
        </section>
        {renderXeroReferenceSyncFragment xeroReferenceSyncDiagnostics}
    </div>
|]

renderXeroReferenceSyncFragment :: Maybe XeroReferenceSyncDiagnostics -> Html
renderXeroReferenceSyncFragment maybeDiagnostics = [hsx|
    <div id={surfaceFragmentTargetId @Surface.AdminXeroSurface @Surface.AdminXeroReferenceSyncFragment noSurfaceFields}>
        {maybe mempty renderXeroReferenceSyncDiagnostics maybeDiagnostics}
    </div>
|]

xeroAppShellActionRoute :: Text -> AppShellActionRoute
xeroAppShellActionRoute actionUrl =
    AppShellActionRoute
        { appShellActionRouteUrl = actionUrl
        , appShellActionRouteFields = []
        , appShellActionRouteCustomHtmx = []
        , appShellActionRouteStandardUrl = Nothing
        , appShellActionRouteExtraAttrs = []
        }

xeroReferenceSyncActionRoute :: FrontendSurfaceActionRoute
xeroReferenceSyncActionRoute =
    FrontendSurfaceActionRoute
        { actionRouteUrl = pathTo SyncXeroPayrollReferenceDataAction
        , actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "load-reference-sync-custom-htmx"
                , customHtmxAttrValues = []
                }
            ]
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

renderXeroActionControls :: XeroConnection -> Bool -> Bool -> Html
renderXeroActionControls connection connectionActionsAllowed referenceRefreshAllowed = [hsx|
    <div class="d-flex flex-column gap-2">
        <div class="d-flex flex-wrap gap-2">
            {renderOpenXeroTimesheetPreparationForm canRunXeroActions}
            {renderOpenXeroStaffMappingsForm canRunXeroActions}
            {renderOpenXeroPayItemImportForm canRunXeroActions}
            {if referenceRefreshAllowed then renderXeroReferenceSyncForm canRunXeroActions else mempty}
            <form method="POST" action={DisconnectXeroConnectionAction}>
                <button class="btn btn-outline-danger" type="submit" disabled={not connectionActionsAllowed}>Disconnect</button>
            </form>
        </div>
    </div>
|]
    where
        canRunXeroActions = connectionActionsAllowed && connection.connectionStatus == "active"

renderXeroReferenceSyncDiagnostics :: XeroReferenceSyncDiagnostics -> Html
renderXeroReferenceSyncDiagnostics diagnostics = [hsx|
    <section class="border rounded p-3 d-flex flex-column gap-2" data-xero-reference-sync-diagnostics="true">
        <div class="fw-semibold">Reference sync diagnostics</div>
        <dl class="row mb-0 small">
            <dt class="col-sm-4">Last successful reference sync</dt>
            <dd class="col-sm-8">{maybe "Never" tshow diagnostics.referenceSyncLastSucceededAt}</dd>
            <dt class="col-sm-4">Current state</dt>
            <dd class="col-sm-8">{referenceSyncDiagnosticsActivityText diagnostics.referenceSyncActivity}</dd>
        </dl>
        {renderReferenceSyncDiagnosticsProgress diagnostics.referenceSyncProgress}
        {renderReferenceSyncDiagnosticsError diagnostics.referenceSyncSanitizedError}
    </section>
|]

renderReferenceSyncDiagnosticsProgress :: XeroReferenceSyncProgressFacts -> Html
renderReferenceSyncDiagnosticsProgress progress = [hsx|
    {renderReferenceSyncDiagnosticsPhase progress.progressPhase}
    {renderReferenceSyncDiagnosticsPage progress.progressCompletedPayItemsPage}
|]

renderReferenceSyncDiagnosticsPhase :: Maybe Text -> Html
renderReferenceSyncDiagnosticsPhase Nothing = mempty
renderReferenceSyncDiagnosticsPhase (Just phase) = [hsx|<div class="small app-muted">{xeroReferenceSyncPhaseText phase}</div>|]

renderReferenceSyncDiagnosticsPage :: Maybe Int -> Html
renderReferenceSyncDiagnosticsPage Nothing = mempty
renderReferenceSyncDiagnosticsPage (Just page) = [hsx|<div class="small app-muted">Completed earnings-rate page {page}</div>|]

renderReferenceSyncDiagnosticsError :: Maybe Text -> Html
renderReferenceSyncDiagnosticsError Nothing = mempty
renderReferenceSyncDiagnosticsError (Just message) = [hsx|<div class="small text-danger">{message}</div>|]

referenceSyncDiagnosticsActivityText :: XeroReferenceSyncActivity -> Text
referenceSyncDiagnosticsActivityText = \case
    XeroReferenceSyncIdle -> "Idle"
    XeroReferenceSyncQueued -> "Queued"
    XeroReferenceSyncRunning -> "Running"
    XeroReferenceSyncRetryWaiting retryAt -> "Retry scheduled for " <> tshow retryAt
    XeroReferenceSyncFailed _ -> "Stopped"

renderXeroReferenceSyncForm :: Bool -> Html
renderXeroReferenceSyncForm actionsAllowed =
    renderFrontendSurfaceActionForm
        (AdminAction.syncXeroPayrollReferenceDataAction AdminAction.syncXeroPayrollReferenceDataActionFields)
        xeroReferenceSyncActionRoute
        [hsx|<button type="submit" class="btn btn-outline-primary" disabled={not actionsAllowed}>Sync Xero data</button>|]

renderOpenXeroStaffMappingsForm :: Bool -> Html
renderOpenXeroStaffMappingsForm connectionActionsAllowed =
    renderAppShellActionForm
        (appShellActionByMarker @OpenXeroStaffMappingsOverlay)
        (xeroAppShellActionRoute (pathTo OpenXeroStaffMappingsAction))
            { appShellActionRouteExtraAttrs = navigationLoadingAttrs "Loading…" "Refreshing Xero staff."
            }
        [hsx|<button type="submit" class="btn btn-outline-primary" disabled={not connectionActionsAllowed}>Staff mappings</button>|]

renderOpenXeroTimesheetPreparationForm :: Bool -> Html
renderOpenXeroTimesheetPreparationForm connectionActionsAllowed =
    renderAppShellActionForm
        (appShellActionByMarker @OpenXeroTimesheetPreparationOverlay)
        (xeroAppShellActionRoute (pathTo OpenXeroTimesheetPreparationAction))
            { appShellActionRouteExtraAttrs =
                [("data-xero-timesheet-preparation-form", "true")]
                    <> navigationLoadingAttrs "Loading…" "Please wait."
            }
        [hsx|
            <button type="submit"
                    class="btn btn-primary"
                    disabled={not connectionActionsAllowed}>
                Upload timesheets
            </button>
        |]

renderOpenXeroPayItemImportForm :: Bool -> Html
renderOpenXeroPayItemImportForm connectionActionsAllowed =
    renderAppShellActionForm
        (appShellActionByMarker @OpenXeroPayItemImportOverlay)
        (xeroAppShellActionRoute (pathTo OpenXeroPayItemImportAction))
        [hsx|<button type="submit" class="btn btn-outline-primary" disabled={not connectionActionsAllowed}>Import pay items</button>|]
