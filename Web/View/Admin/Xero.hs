module Web.View.Admin.Xero
    ( XeroView (..)
    , renderXeroSection
    , renderXeroSectionFragment
    , renderXeroSectionFragmentOob
    , renderXeroStaffMappingControlsOob
    , renderXeroPayItemsFragment
    , renderXeroStaffMappingsFragment
    , renderXeroStaffMappingsOob
    , renderXeroTimesheetsFragment
    , xeroPayItemsFragmentRef
    , xeroStaffMappingsFragmentRef
    , xeroTimesheetsFragmentRef
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Application.Helper.XeroAdminTypes
import Web.View.Admin.Common
import Web.View.Admin.Xero.Connection
import Web.View.Admin.Xero.PayItems
import Web.View.Admin.Xero.StaffMappings
import Web.View.Admin.Xero.Timesheets
import Web.View.Prelude

data XeroView = XeroView
    { xeroSectionData            :: XeroAdminSectionData
    , xeroAutoSyncAfterReconnect :: Bool
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
                    , appPanelBody = renderXeroSectionFragmentWithAutoSync xeroAutoSyncAfterReconnect xeroSectionData
                    }
         in renderAppPage AppPageConfig
            { appPageTitle = "Xero"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = xeroPanel
            }

adminXeroLiveSurface :: (?context :: ControllerContext) => Maybe LiveSurfaceConfig
adminXeroLiveSurface =
    fmap
        (\venue ->
        (mkLiveSurface
            "admin-xero"
            AdminXeroScope { venueId = unpackId venue.id }
            [ mkLiveFragmentRef
                AdminXeroFragment
                "admin-xero-fragment"
                (pathTo ShowAdminXeroFragmentAction)
            , xeroPayItemsFragmentRef
            , xeroTimesheetsFragmentRef
            ])
            { decorateRequestsWithin = ["#admin-xero-fragment"] }
        )
        currentVenueOrNothing

renderXeroSection :: XeroAdminSectionData -> Html
renderXeroSection XeroAdminSectionData { xeroConnection = maybeConnection, .. } =
    renderXeroConnectionBody maybeConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroLatestPayItemSyncRun xeroPayrollCalendars xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection xeroReadyChecklist xeroConnectionActionsAllowed xeroTimesheetPanelData

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
renderXeroSectionFragmentWithSwap maybeSwapOob shouldAutoSync xeroSectionData = [hsx|
    <div id="admin-xero-fragment"
         hx-swap-oob={maybeSwapOob}
         data-live-update-surface={liveSurfaceConfigJson <$> adminXeroLiveSurface}>
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
              hx-indicator="#xero-reference-sync-indicator"></form>
    |]
renderXeroAutoSyncTrigger _ _ =
    mempty

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> Maybe XeroSyncRun -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> XeroTimesheetPanelData -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed _ = [hsx|
    <div class="accordion admin-config-accordion" id="admin-xero-sections">
        {renderXeroAccordionItem "connection" "Connection" True (renderXeroDisconnectedConnectionDetails connectionActionsAllowed)}
    </div>
|]
renderXeroConnectionBody (Just connection) maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements maybePayItemSyncRun xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed timesheetPanel = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="accordion admin-config-accordion" id="admin-xero-sections">
            {renderXeroAccordionItem "connection" "Connection" True (renderXeroConnectionDetails connection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEarningsRates xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed)}
            {renderXeroAccordionItem "staff-mappings" "Staff mappings" False (renderXeroStaffMappings xeroEmployees mappingRows mappingCounts)}
            {renderXeroAccordionItem "pay-items" "Pay items" False (renderXeroPayItems xeroEarningsRates payItemRequirements maybePayItemAccountCodeSelection maybePayItemSyncRun connectionActionsAllowed)}
            {renderXeroAccordionItem "draft-timesheets" "Draft timesheets" False (renderXeroTimesheetPanel timesheetPanel)}
        </div>
    </div>
|]

renderXeroStaffMappingsFragment :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingsFragment =
    renderXeroStaffMappingsData

renderXeroPayItemsFragment :: [XeroEarningsRate] -> [XeroPayItemRequirement] -> Maybe XeroPayItemAccountCodeSelection -> Maybe XeroSyncRun -> Bool -> Html
renderXeroPayItemsFragment =
    renderXeroPayItemsData

renderXeroTimesheetsFragment :: XeroTimesheetPanelData -> Html
renderXeroTimesheetsFragment =
    renderXeroTimesheetPanel

xeroPayItemsFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
xeroPayItemsFragmentRef =
    mkLiveFragmentRef
        AdminXeroPayItemsFragment
        "xero-pay-items-data"
        (pathTo ShowAdminXeroPayItemsFragmentAction)

xeroStaffMappingsFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
xeroStaffMappingsFragmentRef =
    mkLiveFragmentRef
        AdminXeroStaffMappingsFragment
        "xero-staff-mappings-data"
        (pathTo ShowAdminXeroStaffMappingsFragmentAction)

xeroTimesheetsFragmentRef :: (?context :: ControllerContext) => LiveFragmentRef
xeroTimesheetsFragmentRef =
    mkLiveFragmentRef
        AdminXeroTimesheetsFragment
        "xero-timesheets-data"
        (pathTo ShowAdminXeroTimesheetsFragmentAction)

renderXeroAccordionItem :: Text -> Text -> Bool -> Html -> Html
renderXeroAccordionItem sectionId title isOpen content =
    renderAppAccordionItem AppAccordionItemConfig
        { appAccordionItemId = "xero-" <> sectionId
        , appAccordionItemParentId = "admin-xero-sections"
        , appAccordionItemTitle = title
        , appAccordionItemIsOpen = isOpen
        , appAccordionItemClass = ""
        , appAccordionItemBodyClass = ""
        , appAccordionItemButtonContent = [hsx|<span class="fw-semibold">{title}</span>|]
        , appAccordionItemBody = content
        }
