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
import Web.View.Admin.Xero.Calendars
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

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed = [hsx|
    <div class="accordion admin-config-accordion" id="admin-xero-sections">
        {renderXeroAccordionItem "connection" "Connection" True (renderXeroDisconnectedConnectionDetails connectionActionsAllowed)}
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

renderXeroDisconnectedConnectionDetails :: Bool -> Html
renderXeroDisconnectedConnectionDetails connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <dl class="row mb-0">
            <dt class="col-sm-3">Connection status</dt>
            <dd class="col-sm-9"><span class="badge text-bg-secondary">not connected</span></dd>
        </dl>
        <p class="mb-0 app-muted">
            Connecting grants ihp-roster access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
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

renderConnectedBy :: Maybe User -> Html
renderConnectedBy Nothing     = mempty
renderConnectedBy (Just user) = [hsx|<span> by {user.email}</span>|]
