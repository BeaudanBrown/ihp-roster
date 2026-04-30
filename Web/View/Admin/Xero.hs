module Web.View.Admin.Xero
    ( XeroView (..)
    , renderXeroSection
    , renderXeroSectionFragment
    , renderXeroSectionFragmentOob
    , renderXeroStaffMappingControlsOob
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
import Web.View.Admin.Xero.Calendars
import Web.View.Admin.Xero.Connection
import Web.View.Admin.Xero.PayItems
import Web.View.Admin.Xero.Readiness
import Web.View.Admin.Xero.StaffMappings
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
                    , appPanelBody = renderXeroSectionFragment xeroSectionData
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
            ])
            { decorateRequestsWithin = ["#admin-xero-fragment"] }
        )
        currentVenueOrNothing

renderXeroSection :: XeroAdminSectionData -> Html
renderXeroSection XeroAdminSectionData { xeroConnection = maybeConnection, .. } =
    renderXeroConnectionBody maybeConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroPayrollCalendars xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection xeroReadyChecklist xeroConnectionActionsAllowed

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment =
    renderXeroSectionFragmentWithSwap noOobSwap

renderXeroSectionFragmentOob :: XeroAdminSectionData -> Html
renderXeroSectionFragmentOob =
    renderXeroSectionFragmentWithSwap outerHtmlOobSwap

renderXeroSectionFragmentWithSwap :: OobSwapAttr -> XeroAdminSectionData -> Html
renderXeroSectionFragmentWithSwap maybeSwapOob xeroSectionData = [hsx|
    <div id="admin-xero-fragment"
         hx-swap-oob={maybeSwapOob}
         data-live-update-surface={liveSurfaceConfigJson <$> adminXeroLiveSurface}>
        {renderXeroSection xeroSectionData}
    </div>
|]

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed = [hsx|
    <div class="accordion admin-config-accordion" id="admin-xero-sections">
        {renderXeroAccordionItem "connection" "Connection" True (renderXeroDisconnectedConnectionDetails connectionActionsAllowed)}
    </div>
|]
renderXeroConnectionBody (Just connection) maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="accordion admin-config-accordion" id="admin-xero-sections">
            {renderXeroAccordionItem "connection" "Connection" True (renderXeroConnectionDetails connection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount connectionActionsAllowed)}
            {renderXeroAccordionItem "staff-mappings" "Staff mappings" False (renderXeroStaffMappings xeroEmployees mappingRows mappingCounts)}
            {renderXeroAccordionItem "pay-items" "Pay items" False (renderXeroPayItems xeroEarningsRates payItemRequirements maybePayItemAccountCodeSelection connectionActionsAllowed)}
            {renderXeroAccordionItem "payroll-calendar" "Payroll calendar" False (renderXeroPayrollCalendarSelection xeroPayrollCalendars maybePayrollCalendarSelection)}
            {renderXeroAccordionItem "readiness" "Readiness" False (renderXeroReadyChecklist readyChecklist)}
        </div>
    </div>
|]

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
