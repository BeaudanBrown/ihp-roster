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
import Application.Helper.XeroPayItems (xeroManagedPayItemNamePrefix)
import qualified Data.List as List
import qualified Data.Text as Text
import Web.View.Admin.Common
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
    renderConfigSection
        "xero"
        "Xero"
        "Connect this venue to a Xero organisation for payroll integration setup."
        (renderXeroSummary maybeConnection)
        mempty
        (renderXeroConnectionBody maybeConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroPayrollCalendars xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection xeroReadyChecklist xeroConnectionActionsAllowed)

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment =
    renderXeroSectionFragmentWithSwap Nothing

renderXeroSectionFragmentOob :: XeroAdminSectionData -> Html
renderXeroSectionFragmentOob =
    renderXeroSectionFragmentWithSwap (Just "outerHTML")

renderXeroSectionFragmentWithSwap :: Maybe Text -> XeroAdminSectionData -> Html
renderXeroSectionFragmentWithSwap maybeSwapOob xeroSectionData = [hsx|
    <div id="admin-xero-fragment"
         hx-swap-oob={maybeSwapOob}
         data-live-update-surface={liveSurfaceConfigJson <$> adminXeroLiveSurface}>
        {renderXeroSection xeroSectionData}
    </div>
|]

renderXeroSummary :: Maybe XeroConnection -> Html
renderXeroSummary Nothing = [hsx|
    <div class="small app-muted mb-3">
        Status: <span class="badge text-bg-secondary">not connected</span>
    </div>
|]
renderXeroSummary (Just connection) = [hsx|
    <div class="small app-muted mb-3">
        Status: {renderXeroConnectionStatus connection}
        <span class="ms-2">{fromMaybe connection.tenantId connection.tenantName}</span>
    </div>
|]

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <p class="mb-0 app-muted">
            Connecting grants ihp-roster access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
    </div>
|]
renderXeroConnectionBody (Just connection) maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed =
    let payItemsContent = [hsx|
                <div class="d-flex flex-column gap-3">
                    {renderXeroPayItemAccountCodeSelection xeroEarningsRates maybePayItemAccountCodeSelection connectionActionsAllowed}
                    {renderXeroPayItemRequirements xeroEarningsRates payItemRequirements maybePayItemAccountCodeSelection connectionActionsAllowed}
                </div>
            |]
     in [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="accordion admin-config-accordion" id="admin-xero-sections">
            {renderXeroAccordionItem "connection" "Connection" True (renderXeroConnectionDetails connection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount connectionActionsAllowed)}
            {renderXeroAccordionItem "staff-mappings" "Staff mappings" False (renderXeroStaffMappings xeroEmployees mappingRows mappingCounts)}
            {renderXeroAccordionItem "pay-items" "Pay items" False payItemsContent}
            {renderXeroAccordionItem "payroll-calendar" "Payroll calendar" False (renderXeroPayrollCalendarSelection xeroPayrollCalendars maybePayrollCalendarSelection)}
            {renderXeroAccordionItem "readiness" "Readiness" False (renderXeroReadyChecklist readyChecklist)}
        </div>
    </div>
|]

renderXeroConnectionDetails :: XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> Bool -> Html
renderXeroConnectionDetails connection maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <dl class="row mb-0">
            <dt class="col-sm-3">Tenant</dt>
            <dd class="col-sm-9">{fromMaybe connection.tenantId connection.tenantName}</dd>
            <dt class="col-sm-3">Tenant ID</dt>
            <dd class="col-sm-9"><code>{connection.tenantId}</code></dd>
            <dt class="col-sm-3">Connected</dt>
            <dd class="col-sm-9">{formatTimestamp connection.connectedAt}{renderConnectedBy maybeConnectedByUser}</dd>
            <dt class="col-sm-3">Connection status</dt>
            <dd class="col-sm-9">{renderXeroConnectionStatus connection}{renderXeroConnectionError connection}</dd>
            <dt class="col-sm-3">Reference data</dt>
            <dd class="col-sm-9">{renderXeroReferenceSummary maybeSyncRun employeeCount earningsRateCount payrollCalendarCount}</dd>
        </dl>
        {renderXeroConnectionNotice connection}
        <div class="d-flex flex-wrap gap-2">
            <form method="POST"
                  action={SyncXeroPayrollReferenceDataAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SyncXeroPayrollReferenceDataAction}
                  hx-target="#admin-xero-fragment"
                  hx-swap="outerHTML">
                <button class="btn btn-outline-primary" type="submit" disabled={connection.connectionStatus /= "active"}>Sync payroll reference data</button>
            </form>
            {renderXeroReconnectControls connectionActionsAllowed}
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

renderXeroConnectControl :: Bool -> Html
renderXeroConnectControl True = [hsx|
    <form method="POST" action={StartXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-primary" type="submit">Connect Xero</button>
    </form>
|]
renderXeroConnectControl False = [hsx|
    <p class="mb-0 small app-muted">Only the venue owner or a super admin can connect Xero for this venue.</p>
|]

renderXeroReconnectControls :: Bool -> Html
renderXeroReconnectControls True = [hsx|
    <form method="POST" action={StartXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-secondary" type="submit">Reconnect</button>
    </form>
    <form method="POST" action={DisconnectXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-danger" type="submit">Disconnect</button>
    </form>
|]
renderXeroReconnectControls False = [hsx|
    <span class="align-self-center small app-muted">Only the venue owner or a super admin can reconnect or disconnect Xero.</span>
|]

renderXeroConnectionStatus :: XeroConnection -> Html
renderXeroConnectionStatus connection =
    case connection.connectionStatus of
        "active" -> [hsx|<span class="badge text-bg-success">connected</span>|]
        "reauthorization_required" -> [hsx|<span class="badge text-bg-warning">reconnect required</span>|]
        "error" -> [hsx|<span class="badge text-bg-danger">attention needed</span>|]
        "disconnected" -> [hsx|<span class="badge text-bg-secondary">disconnected</span>|]
        status -> [hsx|<span class="badge text-bg-secondary">{status}</span>|]

renderXeroConnectionError :: XeroConnection -> Html
renderXeroConnectionError connection =
    case connection.lastError of
        Nothing      -> mempty
        Just message -> [hsx|<span class="ms-2 app-muted">{message}</span>|]

renderXeroConnectionNotice :: XeroConnection -> Html
renderXeroConnectionNotice connection =
    case connection.connectionStatus of
        "reauthorization_required" -> [hsx|
            <div class="alert alert-warning mb-0" role="alert">
                Xero needs to be reconnected before sync can continue. Use Reconnect to authorize the same organisation again; existing staff mappings will be kept.
            </div>
        |]
        "error" -> [hsx|
            <div class="alert alert-danger mb-0" role="alert">
                Xero needs attention before sync can continue. Try Reconnect, or Disconnect if you want this app to remove the linked organisation in Xero.
            </div>
        |]
        _ -> mempty

renderXeroReferenceSummary :: Maybe XeroSyncRun -> Int -> Int -> Int -> Html
renderXeroReferenceSummary maybeSyncRun employeeCount earningsRateCount payrollCalendarCount = [hsx|
    <div class="d-flex flex-column gap-2">
        <div class="d-flex flex-wrap gap-2">
            <span class="badge text-bg-secondary">{tshow employeeCount} employees</span>
            <span class="badge text-bg-secondary">{tshow earningsRateCount} earnings rates</span>
            <span class="badge text-bg-secondary">{tshow payrollCalendarCount} payroll calendars</span>
        </div>
        {renderXeroLatestSync maybeSyncRun}
    </div>
|]

renderXeroLatestSync :: Maybe XeroSyncRun -> Html
renderXeroLatestSync Nothing = [hsx|
    <span class="small app-muted">Not synced yet.</span>
|]
renderXeroLatestSync (Just syncRun) = [hsx|
    <span class="small app-muted">
        Last sync: {renderXeroSyncStatus syncRun.syncStatus} at {formatTimestamp syncRun.startedAt}{renderXeroSyncError syncRun.errorMessage}
    </span>
|]

renderXeroSyncStatus :: Text -> Html
renderXeroSyncStatus "succeeded" = [hsx|<span class="badge text-bg-success">succeeded</span>|]
renderXeroSyncStatus "failed" = [hsx|<span class="badge text-bg-danger">failed</span>|]
renderXeroSyncStatus "running" = [hsx|<span class="badge text-bg-warning">running</span>|]
renderXeroSyncStatus status = [hsx|<span class="badge text-bg-secondary">{status}</span>|]

renderXeroSyncError :: Maybe Text -> Html
renderXeroSyncError Nothing             = mempty
renderXeroSyncError (Just errorMessage) = [hsx|<span> - {errorMessage}</span>|]

renderXeroStaffMappings :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappings xeroEmployees mappingRows mappingCounts
    | null xeroEmployees = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before mapping staff to Xero employees.</p>
        </div>
    |]
    | null mappingRows = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Staff mappings</h3>
            <p class="small app-muted mb-0">No active staff are available for Xero payroll mapping.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Staff mappings</h3>
                    <p class="small app-muted mb-0">Map active staff to synced Xero payroll employees, or mark them as not paid through Xero.</p>
                </div>
                {renderXeroStaffMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff</th>
                            <th>Email</th>
                            <th>Xero employee</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach mappingRows (renderXeroStaffMappingRow xeroEmployees mappingRows)}
                    </tbody>
                </table>
            </div>
        </div>
    |]

renderXeroStaffMappingRow :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingRow xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        mapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue mapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <tr>
            <td>{renderXeroStaffMappingStaffCell row}</td>
            <td>{renderXeroStaffEmail row.mappingRowUser}</td>
            <td>{renderXeroStaffMappingControl selectableEmployees currentSelection staff}</td>
        </tr>
    |]

renderXeroStaffMappingStaffCell :: XeroStaffMappingRow -> Html
renderXeroStaffMappingStaffCell row = [hsx|
    <div class="d-flex flex-column gap-1">
        <span>{staffFullName row.mappingRowStaff}</span>
        {renderXeroStaffPossibleMatchBadge row.mappingRowSuggestedEmployee}
    </div>
|]

renderXeroStaffPossibleMatchBadge :: Maybe XeroEmployee -> Html
renderXeroStaffPossibleMatchBadge Nothing = mempty
renderXeroStaffPossibleMatchBadge (Just employee) = [hsx|
    <span class="badge text-bg-warning align-self-start">Possible Xero match: {employee.displayName}</span>
|]

renderXeroStaffMappingCounts :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCounts =
    renderXeroStaffMappingCountsWith Nothing

renderXeroStaffMappingCountsOob :: XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsOob =
    renderXeroStaffMappingCountsWith (Just "outerHTML")

renderXeroStaffMappingCountsWith :: Maybe Text -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingCountsWith maybeOobSwap mappingCounts = [hsx|
    <div id="xero-staff-mapping-counts" class="d-flex flex-wrap gap-2" hx-swap-oob={maybeOobSwap}>
        <span class="badge text-bg-success">{tshow mappingCounts.xeroStaffVerifiedCount} mapped</span>
        <span class="badge text-bg-info">{tshow mappingCounts.xeroStaffNotApplicableCount} not paid through Xero</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffPossibleMatchCount} possible matches</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffStaleCount} stale</span>
    </div>
|]

renderXeroStaffMappingControl :: [XeroEmployee] -> Text -> Staff -> Html
renderXeroStaffMappingControl selectableEmployees currentSelection staff = [hsx|
    <div id={xeroStaffMappingControlId staff.id} class="d-flex align-items-center gap-2">
        <form class="flex-grow-1"
              method="POST"
              action={SaveXeroStaffMappingAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroStaffMappingAction}
              hx-trigger="change"
              hx-swap="none">
            <input type="hidden" name="staffId" value={tshow staff.id} />
            <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
            </select>
        </form>
        {renderXeroStaffMappingSuggestButton staff}
    </div>
|]

renderXeroStaffMappingControlOob :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingControlOob xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        mapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue mapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <div id={xeroStaffMappingControlId staff.id}
             class="d-flex align-items-center gap-2"
             hx-swap-oob="outerHTML">
            <form class="flex-grow-1"
                  method="POST"
                  action={SaveXeroStaffMappingAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SaveXeroStaffMappingAction}
                  hx-target="#admin-xero-fragment"
                  hx-trigger="change"
                  hx-swap="none">
                <input type="hidden" name="staffId" value={tshow staff.id} />
                <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                    <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                    {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
                </select>
            </form>
            {renderXeroStaffMappingSuggestButton staff}
        </div>
    |]

renderXeroStaffMappingSuggestButton :: Staff -> Html
renderXeroStaffMappingSuggestButton staff = [hsx|
    <form method="POST"
          action={SuggestXeroStaffMappingAction staff.id}
          data-disable-javascript-submission="true"
          hx-post={pathTo (SuggestXeroStaffMappingAction staff.id)}
          hx-target="#admin-xero-fragment"
          hx-swap="none">
        <button class="btn btn-outline-secondary btn-sm" type="submit">Suggest</button>
    </form>
|]

renderXeroStaffMappingControlsOob :: Maybe (Id Staff) -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> Html
renderXeroStaffMappingControlsOob maybeUnchangedStaffId xeroEmployees mappingRows mappingCounts =
    mconcat
        [ renderXeroStaffMappingCountsOob mappingCounts
        , mconcat (map (renderXeroStaffMappingControlOob xeroEmployees mappingRows) changedRows)
        ]
    where
        changedRows =
            case maybeUnchangedStaffId of
                Nothing      -> mappingRows
                Just staffId -> filter (\row -> row.mappingRowStaff.id /= staffId) mappingRows

xeroStaffMappingControlId :: Id Staff -> Text
xeroStaffMappingControlId staffId =
    "xero-staff-mapping-control-" <> tshow staffId

renderXeroPayItemAccountCodeSelection :: [XeroEarningsRate] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemAccountCodeSelection xeroEarningsRates maybeSelection canManagePayItems = [hsx|
    <div class="border rounded p-3">
        <h3 class="h6 mb-2">Pay item account code</h3>
        <p class="small app-muted mb-3">Choose the Xero wages expense account code to use when creating managed pay items.</p>
        <form method="POST"
              action={SaveXeroPayItemAccountCodeSelectionAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroPayItemAccountCodeSelectionAction}
              hx-target="#admin-xero-fragment"
              hx-swap="outerHTML">
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-8">
                    <label class="form-label small" for="xero-pay-item-account-code-selection">Synced account code</label>
                    <select id="xero-pay-item-account-code-selection" class="form-select form-select-sm" name="xeroPayItemAccountCodeSelection" disabled={not canManagePayItems}>
                        <option value="" selected={currentSelection == ""}>Not selected</option>
                        {forEach accountCodeOptions (renderXeroPayItemAccountCodeOption currentSelection)}
                    </select>
                </div>
                <div class="col-12 col-md-4">
                    <button class="btn btn-outline-primary btn-sm w-100" type="submit" disabled={not canManagePayItems}>Save account code</button>
                </div>
            </div>
        </form>
    </div>
|]
    where
        selectedAccountCode =
            case maybeSelection of
                Just selection | selection.selectionStatus == "verified" -> Text.strip <$> selection.accountCode
                _ -> Nothing
        accountCodeOptions = xeroPayItemAccountCodeOptions xeroEarningsRates
        selectedIsObserved = maybe False (`elem` accountCodeOptions) selectedAccountCode
        currentSelection =
            case selectedAccountCode of
                Just accountCode | selectedIsObserved -> accountCode
                _                                     -> ""

xeroPayItemAccountCodeOptions :: [XeroEarningsRate] -> [Text]
xeroPayItemAccountCodeOptions xeroEarningsRates =
    xeroEarningsRates
        |> filter (.isActive)
        |> map (.accountCode)
        |> catMaybes
        |> map Text.strip
        |> filter (not . Text.null)
        |> List.nub
        |> List.sort

renderXeroPayItemAccountCodeOption :: Text -> Text -> Html
renderXeroPayItemAccountCodeOption currentSelection accountCode = [hsx|
    <option value={accountCode} selected={currentSelection == accountCode}>{accountCode}</option>
|]

renderXeroPayItemRequirements :: [XeroEarningsRate] -> [XeroPayItemRequirement] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemRequirements xeroEarningsRates requirements maybePayItemAccountCodeSelection canManagePayItems
    | null requirements = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Pay item requirements</h3>
            <p class="small app-muted mb-0">No award-backed Xero pay item requirements are available yet.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Pay item requirements</h3>
                    <p class="small app-muted mb-0">Review the managed Xero earnings-rate pay items this venue needs before timesheet export mapping. Managed names use the {xeroManagedPayItemNamePrefix} prefix.</p>
                </div>
                <div class="d-flex flex-wrap gap-2">
                    <span class="badge text-bg-success">{tshow matchedCount} matched</span>
                    <span class="badge text-bg-secondary">{tshow proposedCount} proposed</span>
                    <span class="badge text-bg-warning">{tshow rateChangedCount} rate changed</span>
                    <span class="badge text-bg-warning">{tshow staleCount} stale</span>
                    <span class="badge text-bg-light border">{tshow archivedCount} archived</span>
                </div>
            </div>
            {renderCreateMissingXeroPayItemsControl canManagePayItems hasAccountCode proposedCount}
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Value</th>
                            <th>Xero status</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach activeRequirements renderXeroPayItemRequirementRow}
                    </tbody>
                </table>
            </div>
            {renderArchivedXeroPayItemRequirements archivedRequirements}
        </div>
    |]
    where
        activeRequirements = sortPayItemRequirementsByName (filter (.payItemRequirementIsActive) requirements)
        archivedRequirements = sortPayItemRequirementsByName (filter (not . (.payItemRequirementIsActive)) requirements)
        matchedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "matched") activeRequirements)
        proposedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "proposed") activeRequirements)
        rateChangedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "rate_changed") activeRequirements)
        staleCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "stale") activeRequirements)
        archivedCount = length archivedRequirements
        accountCodeOptions = xeroPayItemAccountCodeOptions xeroEarningsRates
        hasAccountCode =
            case maybePayItemAccountCodeSelection of
                Just selection -> selection.selectionStatus == "verified" && maybe False (\accountCode -> Text.strip accountCode `elem` accountCodeOptions) selection.accountCode
                Nothing -> False

sortPayItemRequirementsByName :: [XeroPayItemRequirement] -> [XeroPayItemRequirement]
sortPayItemRequirementsByName =
    List.sortOn (.payItemRequirementName)

renderArchivedXeroPayItemRequirements :: [XeroPayItemRequirement] -> Html
renderArchivedXeroPayItemRequirements [] = mempty
renderArchivedXeroPayItemRequirements requirements = [hsx|
    <details class="mt-3">
        <summary class="small app-muted">Archived pay item requirements ({tshow (length requirements)})</summary>
        <div class="table-responsive mt-2">
            <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>Value</th>
                            <th>Xero status</th>
                        </tr>
                    </thead>
                <tbody>
                    {forEach requirements renderXeroPayItemRequirementRow}
                </tbody>
            </table>
        </div>
    </details>
|]

renderCreateMissingXeroPayItemsControl :: Bool -> Bool -> Int -> Html
renderCreateMissingXeroPayItemsControl canManagePayItems hasAccountCode proposedCount
    | proposedCount <= 0 = mempty
    | otherwise = [hsx|
        <form method="POST"
              action={CreateMissingXeroPayItemsAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo CreateMissingXeroPayItemsAction}
              hx-target="#admin-xero-fragment"
              hx-swap="outerHTML"
              class="mb-3">
            <button class="btn btn-outline-primary btn-sm" type="submit" disabled={not canManagePayItems || not hasAccountCode}>
                Create {tshow proposedCount} missing pay items in Xero
            </button>
            {renderMissingPayItemAccountCodeNotice hasAccountCode}
        </form>
    |]

renderMissingPayItemAccountCodeNotice :: Bool -> Html
renderMissingPayItemAccountCodeNotice True = mempty
renderMissingPayItemAccountCodeNotice False = [hsx|
    <div class="small app-muted mt-2">Choose a pay item account code before creating pay items.</div>
|]

renderXeroPayItemRequirementRow :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementRow requirement = [hsx|
    <tr>
        <td>{requirement.payItemRequirementName}</td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderXeroPayItemRequirementStatus requirement}</td>
    </tr>
|]

renderXeroPayItemRequirementStatus :: XeroPayItemRequirement -> Html
renderXeroPayItemRequirementStatus requirement =
    case (requirement.payItemRequirementStatus, requirement.payItemRequirementMatch) of
        ("matched", Just earningsRate) -> [hsx|<span class="badge text-bg-success">matched</span> <span class="small">{earningsRate.name}</span>|]
        ("created", Just earningsRate) -> [hsx|<span class="badge text-bg-success">created</span> <span class="small">{earningsRate.name}</span>|]
        ("ignored", _)                 -> [hsx|<span class="badge text-bg-light border">ignored</span>|]
        ("stale", _)                   -> [hsx|<span class="badge text-bg-warning">stale</span>|]
        ("rate_changed", _)            -> [hsx|<span class="badge text-bg-warning">rate changed</span>|]
        _                              -> [hsx|<span class="badge text-bg-secondary">proposed</span>|]

renderXeroPayrollCalendarSelection :: [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Html
renderXeroPayrollCalendarSelection payrollCalendars maybeSelection
    | null payrollCalendars = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before selecting the venue's Xero payroll calendar.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Payroll calendar</h3>
            <p class="small app-muted mb-3">Choose the Xero pay calendar this venue uses for timesheet exports.</p>
            <form method="POST"
                  action={SaveXeroPayrollCalendarSelectionAction}
                  data-disable-javascript-submission="true"
                  hx-post={pathTo SaveXeroPayrollCalendarSelectionAction}
                  hx-target="#admin-xero-fragment"
                  hx-trigger="change"
                  hx-swap="outerHTML">
                <select class="form-select form-select-sm" name="xeroPayrollCalendarSelection" aria-label="Xero payroll calendar">
                    <option value="" selected={currentSelection == ""}>Not selected</option>
                    {forEach payrollCalendars (renderXeroPayrollCalendarOption currentSelection)}
                </select>
            </form>
        </div>
    |]
    where
        currentSelection =
            case maybeSelection of
                Just selection | selection.calendarStatus == "verified" -> fromMaybe "" selection.xeroPayrollCalendarId
                _ -> ""

renderXeroPayrollCalendarOption :: Text -> XeroPayrollCalendar -> Html
renderXeroPayrollCalendarOption currentSelection payrollCalendar = [hsx|
    <option value={payrollCalendar.xeroPayrollCalendarId} selected={currentSelection == payrollCalendar.xeroPayrollCalendarId}>
        {xeroPayrollCalendarLabel payrollCalendar}
    </option>
|]

xeroPayrollCalendarLabel :: XeroPayrollCalendar -> Text
xeroPayrollCalendarLabel payrollCalendar =
    Text.intercalate " - " (filter (not . Text.null) [payrollCalendar.name, fromMaybe "" payrollCalendar.calendarType])

renderXeroReadyChecklist :: XeroReadyChecklist -> Html
renderXeroReadyChecklist checklist = [hsx|
    <div class="border rounded p-3">
        <h3 class="h6 mb-3">Ready to submit checklist</h3>
        <div class="d-flex flex-column gap-2 small">
            {renderXeroReadyChecklistItem checklist.xeroReadyConnection "Xero connection is active"}
            {renderXeroReadyChecklistItem checklist.xeroReadyReferenceSync "Latest payroll reference sync succeeded"}
            {renderXeroReadyChecklistItem checklist.xeroReadyStaffMappings "Staff mappings are complete"}
            {renderXeroReadyChecklistItem checklist.xeroReadyPayItemAccountCode "Pay item account code is selected"}
            {renderXeroReadyChecklistItem checklist.xeroReadyPayrollCalendar "Payroll calendar is selected"}
        </div>
    </div>
|]

renderXeroReadyChecklistItem :: Bool -> Text -> Html
renderXeroReadyChecklistItem True label = [hsx|
    <div><span class="badge text-bg-success me-2">ready</span>{label}</div>
|]
renderXeroReadyChecklistItem False label = [hsx|
    <div><span class="badge text-bg-secondary me-2">needed</span>{label}</div>
|]

xeroEmployeeAvailableForRow :: XeroStaffMappingRow -> [XeroStaffMappingRow] -> XeroEmployee -> Bool
xeroEmployeeAvailableForRow currentRow mappingRows employee =
    employee.xeroEmployeeId `List.notElem` usedByOtherStaff
    where
        currentStaffId = unpackId currentRow.mappingRowStaff.id
        usedByOtherStaff =
            mappingRows
                |> mapMaybe verifiedEmployeeForOtherStaff

        verifiedEmployeeForOtherStaff row =
            let mapping = row.mappingRowMapping
             in if rowStaffId row /= currentStaffId && mapping.mappingStatus == "verified"
                    then mapping.xeroEmployeeId
                    else Nothing

        rowStaffId row = unpackId row.mappingRowStaff.id

renderXeroEmployeeOption :: Text -> XeroEmployee -> Html
renderXeroEmployeeOption currentSelection employee = [hsx|
    <option value={employee.xeroEmployeeId} selected={currentSelection == employee.xeroEmployeeId}>
        {xeroEmployeeLabel employee}
    </option>
|]

renderXeroStaffEmail :: Maybe User -> Html
renderXeroStaffEmail Nothing     = renderMutedText "No linked login"
renderXeroStaffEmail (Just user) = [hsx|<span>{user.email}</span>|]

renderMutedText :: Text -> Html
renderMutedText text = [hsx|<span class="app-muted">{text}</span>|]

xeroMappingSelectionValue :: XeroStaffMapping -> Text
xeroMappingSelectionValue mapping
    | mapping.mappingStatus == "not_applicable" = "not_applicable"
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEmployeeId
    | otherwise = "not_applicable"

xeroEmployeeLabel :: XeroEmployee -> Text
xeroEmployeeLabel employee =
    case employee.email of
        Nothing    -> employee.displayName
        Just email -> employee.displayName <> " - " <> email

staffFullName :: Staff -> Text
staffFullName staff =
    Text.strip (staff.firstName <> " " <> staff.lastName)

renderConnectedBy :: Maybe User -> Html
renderConnectedBy Nothing     = mempty
renderConnectedBy (Just user) = [hsx|<span> by {user.email}</span>|]
