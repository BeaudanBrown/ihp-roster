{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero
    ( XeroView (..)
    , renderXeroSection
    , renderXeroSectionFragment
    ) where

{-# LANGUAGE TypeApplications #-}

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendContract.AppShell (OpenXeroPayItemImportOverlay,
                                                     OpenXeroTimesheetPreparationOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            FrontendSurfaceCustomHtmxAttrs (..),
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.XeroAdminTypes
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..), adminXeroAction,
                                  adminXeroPageSurfaceImpl,
                                  adminXeroSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Admin.Xero.Connection
import Web.View.Prelude

data XeroView = XeroView
    { xeroSectionData          :: XeroAdminSectionData
    , xeroAutoSyncAfterConnect :: Bool
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
                    , appPanelBody = renderXeroPageContentSurface (renderXeroSectionFragmentWithAutoSync xeroAutoSyncAfterConnect xeroSectionData)
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
        <div id="admin-xero-page-content-fragment">
            {body}
        </div>
    |]

renderXeroSection :: XeroAdminSectionData -> Html
renderXeroSection XeroAdminSectionData { xeroConnection, xeroConnectionActionsAllowed } =
    renderXeroConnectionBody xeroConnection xeroConnectionActionsAllowed

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment =
    renderXeroSectionFragmentWithAutoSync False

renderXeroSectionFragmentWithAutoSync :: Bool -> XeroAdminSectionData -> Html
renderXeroSectionFragmentWithAutoSync =
    renderXeroSectionFragmentWithSwap noOobSwap

renderXeroSectionFragmentWithSwap :: OobSwapAttr -> Bool -> XeroAdminSectionData -> Html
renderXeroSectionFragmentWithSwap maybeSwapOob shouldAutoSync xeroSectionData =
    renderFrontendSurfaceMount (adminXeroSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Nothing }) [hsx|
        <div id="admin-xero-fragment"
             hx-swap-oob={maybeSwapOob}>
            {renderXeroAutoSyncTrigger shouldAutoSync xeroSectionData.xeroConnection}
            {renderXeroSection xeroSectionData}
        </div>
    |]

renderXeroAutoSyncTrigger :: Bool -> Maybe XeroConnection -> Html
renderXeroAutoSyncTrigger True (Just connection)
    | connection.connectionStatus == "active" =
        renderFrontendSurfaceActionForm
            (adminXeroAction "sync-xero-payroll-reference-data")
            xeroReferenceSyncActionRoute
                { actionRouteCustomHtmx =
                    [ FrontendSurfaceCustomHtmxAttrs
                        { customHtmxAttrMarker = "load-reference-sync-custom-htmx"
                        , customHtmxAttrValues =
                            [ ("hx-trigger", "load")
                            , ("hx-push-url", pathTo XeroAction)
                            , ("hx-indicator", "#xero-connection-status-badge")
                            ]
                        }
                    ]
                , actionRouteStandardUrl = Just (pathTo SyncXeroPayrollReferenceDataAction)
                , actionRouteExtraAttrs =
                    [ ("id", "xero-auto-reference-sync")
                    , ("data-disable-javascript-submission", "true")
                    ]
                }
            mempty
renderXeroAutoSyncTrigger _ _ =
    mempty

renderXeroConnectionBody :: Maybe XeroConnection -> Bool -> Html
renderXeroConnectionBody Nothing connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            {renderXeroDisconnectedConnectionDetails connectionActionsAllowed}
        </section>
    </div>
|]
renderXeroConnectionBody (Just connection) connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            <div class="d-flex flex-column gap-3">
                {renderXeroConnectionDetails connection}
                {renderXeroActionControls connection connectionActionsAllowed}
            </div>
        </section>
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
        , actionRouteFields = []
        , actionRouteCustomHtmx =
            [ FrontendSurfaceCustomHtmxAttrs
                { customHtmxAttrMarker = "load-reference-sync-custom-htmx"
                , customHtmxAttrValues = []
                }
            ]
        , actionRouteStandardUrl = Nothing
        , actionRouteExtraAttrs = []
        }

renderXeroActionControls :: XeroConnection -> Bool -> Html
renderXeroActionControls connection connectionActionsAllowed = [hsx|
    <div class="d-flex flex-wrap gap-2">
        {renderOpenXeroTimesheetPreparationForm canRunXeroActions}
        {renderOpenXeroPayItemImportForm canRunXeroActions}
        {renderXeroReferenceSyncForm canRunXeroActions}
        <form method="POST" action={DisconnectXeroConnectionAction} data-disable-javascript-submission="true">
            <button class="btn btn-outline-danger" type="submit" disabled={not connectionActionsAllowed}>Disconnect</button>
        </form>
    </div>
|]
    where
        canRunXeroActions = connectionActionsAllowed && connection.connectionStatus == "active"

renderXeroReferenceSyncForm :: Bool -> Html
renderXeroReferenceSyncForm actionsAllowed =
    renderFrontendSurfaceActionForm
        (adminXeroAction "sync-xero-payroll-reference-data")
        xeroReferenceSyncActionRoute
        [hsx|<button type="submit" class="btn btn-outline-primary" disabled={not actionsAllowed}>Sync Xero data</button>|]

renderOpenXeroTimesheetPreparationForm :: Bool -> Html
renderOpenXeroTimesheetPreparationForm connectionActionsAllowed =
    renderAppShellActionForm
        (appShellActionByMarker @OpenXeroTimesheetPreparationOverlay)
        (xeroAppShellActionRoute (pathTo OpenXeroTimesheetPreparationAction))
            { appShellActionRouteExtraAttrs = [("data-xero-timesheet-preparation-form", "true")]
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
