{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero
    ( XeroView (..)
    , renderXeroSection
    , renderXeroSectionFragment
    , renderXeroSectionFragmentOob
    , renderXeroStaffMappingControlsOob
    , renderXeroPayItemsFragment
    , renderXeroPayItemsFragmentOob
    , renderXeroStaffMappingsFragment
    , renderXeroStaffMappingsOob
    , renderXeroTimesheetsFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendContract.Surface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.View.Overlay (dialogOverlayMountId)
import Application.Helper.XeroAdminTypes
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminXeroPageSurfaceImpl,
                                  adminXeroSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Admin.Xero.Connection
import Web.View.Admin.Xero.PayItems
import Web.View.Admin.Xero.StaffMappings
import Web.View.Admin.Xero.Timesheets
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
renderXeroSection XeroAdminSectionData { xeroConnection = maybeConnection, .. } =
    renderXeroConnectionBody maybeConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroImportedPayItems xeroPayItemAccountCodeOptions xeroLatestPayItemSyncRun xeroPayrollCalendars xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection xeroReadyChecklist xeroConnectionActionsAllowed xeroTimesheetPanelData

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment =
    renderXeroSectionFragmentWithAutoSync False

renderXeroSectionFragmentWithAutoSync :: Bool -> XeroAdminSectionData -> Html
renderXeroSectionFragmentWithAutoSync =
    renderXeroSectionFragmentWithSwap noOobSwap

renderXeroSectionFragmentOob :: XeroAdminSectionData -> Html
renderXeroSectionFragmentOob =
    renderXeroSectionFragmentWithSwap outerHtmlOobSwap False

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
    | connection.connectionStatus == "active" = [hsx|
        <form id="xero-auto-reference-sync"
              method="POST"
              action={SyncXeroPayrollReferenceDataAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SyncXeroPayrollReferenceDataAction}
              hx-trigger="load"
              hx-target="#admin-xero-fragment"
              hx-swap="outerHTML"
              hx-push-url={pathTo XeroAction}
              hx-indicator="#xero-connection-status-badge"></form>
    |]
renderXeroAutoSyncTrigger _ _ =
    mempty

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> [XeroPayItemAccountCodeOption] -> Maybe XeroSyncRun -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> XeroTimesheetPanelData -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed _timesheetPanel = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            {renderXeroDisconnectedConnectionDetails connectionActionsAllowed}
        </section>
    </div>
|]
renderXeroConnectionBody (Just connection) _maybeConnectedByUser _maybeSyncRun _employeeCount _earningsRateCount _payrollCalendarCount _xeroEmployees _mappingRows _mappingCounts _xeroEarningsRates _payItemRequirements _importedPayItems _accountCodeOptions _maybePayItemSyncRun _xeroPayrollCalendars _maybePayrollCalendarSelection _maybePayItemAccountCodeSelection _readyChecklist connectionActionsAllowed timesheetPanel = [hsx|
    <div class="d-flex flex-column gap-4">
        <section class={appSurfaceClasses "p-3"}>
            <div class="d-flex flex-column gap-3">
                {renderXeroConnectionDetails connection}
                {renderXeroActionControls timesheetPanel connectionActionsAllowed}
            </div>
        </section>
    </div>
|]

renderXeroActionControls :: XeroTimesheetPanelData -> Bool -> Html
renderXeroActionControls timesheetPanel connectionActionsAllowed = [hsx|
    <div class="d-flex flex-wrap gap-2">
        <form method="POST"
              action={OpenXeroTimesheetPreparationAction}
              data-xero-timesheet-preparation-form="true"
              hx-post={pathTo OpenXeroTimesheetPreparationAction}
              hx-target={"#" <> dialogOverlayMountId}
              hx-swap="innerHTML">
            <button type="submit"
                    class="btn btn-primary"
                    disabled={not (connectionActionsAllowed && timesheetPanel.xeroTimesheetActionsAllowed)}>
                Upload timesheets
            </button>
        </form>
        <form method="GET"
              action={OpenXeroPayItemImportAction}
              hx-get={pathTo OpenXeroPayItemImportAction}
              hx-target={"#" <> dialogOverlayMountId}
              hx-swap="innerHTML">
            <button type="submit" class="btn btn-outline-primary" disabled={not connectionActionsAllowed}>Import pay items</button>
        </form>
        <form method="POST" action={DisconnectXeroConnectionAction} data-disable-javascript-submission="true">
            <button class="btn btn-outline-danger" type="submit" disabled={not connectionActionsAllowed}>Disconnect</button>
        </form>
    </div>
|]

renderXeroOperationalPanels :: XeroConnection -> XeroTimesheetPanelData -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> [XeroPayItemAccountCodeOption] -> Maybe XeroSyncRun -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroOperationalPanels connection timesheetPanel payItemRequirements importedPayItems accountCodeOptions maybePayItemSyncRun maybePayItemAccountCodeSelection connectionActionsAllowed
    | connection.connectionStatus == "active" = [hsx|
        <section class={appSurfaceClasses "p-3"}>
            {renderXeroTimesheetPanel timesheetPanel}
        </section>
        <section>
            {renderXeroPayItemsFragment accountCodeOptions payItemRequirements importedPayItems maybePayItemAccountCodeSelection maybePayItemSyncRun connectionActionsAllowed}
        </section>
    |]
    | otherwise = mempty

renderXeroStaffMappingsFragment :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingsFragment =
    renderXeroStaffMappingsData

renderXeroPayItemsFragment :: [XeroPayItemAccountCodeOption] -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> Maybe XeroPayItemAccountCodeSelection -> Maybe XeroSyncRun -> Bool -> Html
renderXeroPayItemsFragment =
    renderXeroPayItemsData

renderXeroPayItemsFragmentOob :: [XeroPayItemAccountCodeOption] -> [XeroPayItemRequirement] -> [XeroImportedPayItem] -> Maybe XeroPayItemAccountCodeSelection -> Maybe XeroSyncRun -> Bool -> Html
renderXeroPayItemsFragmentOob =
    renderXeroPayItemsDataOob

renderXeroTimesheetsFragment :: XeroTimesheetPanelData -> Html
renderXeroTimesheetsFragment =
    renderXeroTimesheetPanel
