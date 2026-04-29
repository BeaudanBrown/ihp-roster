module Web.View.Admin.Xero
    ( renderXeroSection
    , renderXeroSectionFragment
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
        (renderXeroConnectionBody maybeConnection xeroConnectedByUser xeroLatestSyncRun xeroEmployeeCount xeroEarningsRateCount xeroPayrollCalendarCount xeroEmployees xeroStaffMappingRows xeroStaffMappingCounts xeroEarningsRates xeroPayItemRequirements xeroEarningsBucketRows xeroEarningsRateMappingCounts xeroPayrollCalendars xeroPayrollCalendarSelection xeroPayItemAccountCodeSelection xeroReadyChecklist xeroConnectionActionsAllowed)

renderXeroSectionFragment :: XeroAdminSectionData -> Html
renderXeroSectionFragment xeroSectionData = [hsx|
    <div id="admin-xero-fragment"
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

renderXeroConnectionBody :: Maybe XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingCounts -> [XeroEarningsRate] -> [XeroPayItemRequirement] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionBody Nothing _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <p class="mb-0 app-muted">
            Connecting grants ihp-roster access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
    </div>
|]
renderXeroConnectionBody (Just connection) maybeConnectedByUser maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEmployees mappingRows mappingCounts xeroEarningsRates payItemRequirements earningsBucketRows earningsMappingCounts xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed = [hsx|
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
        {renderXeroStaffMappings xeroEmployees mappingRows mappingCounts}
        {renderXeroPayItemAccountCodeSelection xeroEarningsRates maybePayItemAccountCodeSelection connectionActionsAllowed}
        {renderXeroPayItemRequirements payItemRequirements maybePayItemAccountCodeSelection connectionActionsAllowed}
        {renderXeroEarningsRateMappings xeroEarningsRates earningsBucketRows earningsMappingCounts}
        {renderXeroPayrollCalendarSelection xeroPayrollCalendars maybePayrollCalendarSelection}
        {renderXeroReadyChecklist readyChecklist}
    </div>
|]

renderXeroConnectControl :: Bool -> Html
renderXeroConnectControl True = [hsx|
    <form method="POST" action={StartXeroConnectionAction} data-disable-javascript-submission="true">
        <button class="btn btn-outline-primary" type="submit">Connect Xero</button>
    </form>
|]
renderXeroConnectControl False = [hsx|
    <p class="mb-0 small app-muted">Only the venue owner can connect Xero for this venue.</p>
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
    <span class="align-self-center small app-muted">Only the venue owner can reconnect or disconnect Xero.</span>
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
                    <p class="small app-muted mb-0">Map active staff to synced Xero payroll employees. Unmapped staff are allowed during setup.</p>
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
        maybeMapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue maybeMapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <tr>
            <td>{staffFullName staff}</td>
            <td>{renderXeroStaffEmail row.mappingRowUser}</td>
            <td>{renderXeroStaffMappingControl selectableEmployees currentSelection staff}</td>
        </tr>
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
        <span class="badge text-bg-secondary">{tshow mappingCounts.xeroStaffUnmappedCount} unmapped</span>
        <span class="badge text-bg-info">{tshow mappingCounts.xeroStaffNotApplicableCount} not paid through Xero</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroStaffStaleCount} stale</span>
    </div>
|]

renderXeroStaffMappingControl :: [XeroEmployee] -> Text -> Staff -> Html
renderXeroStaffMappingControl selectableEmployees currentSelection staff = [hsx|
    <form id={xeroStaffMappingControlId staff.id}
          method="POST"
          action={SaveXeroStaffMappingAction}
          data-disable-javascript-submission="true"
          hx-post={pathTo SaveXeroStaffMappingAction}
          hx-trigger="change"
          hx-swap="none">
        <input type="hidden" name="staffId" value={tshow staff.id} />
        <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
            <option value="" selected={currentSelection == ""}>Unmapped</option>
            <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
            {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
        </select>
    </form>
|]

renderXeroStaffMappingControlOob :: [XeroEmployee] -> [XeroStaffMappingRow] -> XeroStaffMappingRow -> Html
renderXeroStaffMappingControlOob xeroEmployees mappingRows row =
    let staff = row.mappingRowStaff
        maybeMapping = row.mappingRowMapping
        currentSelection = xeroMappingSelectionValue maybeMapping
        selectableEmployees = filter (xeroEmployeeAvailableForRow row mappingRows) xeroEmployees
     in [hsx|
        <form id={xeroStaffMappingControlId staff.id}
              method="POST"
              action={SaveXeroStaffMappingAction}
              data-disable-javascript-submission="true"
              hx-post={pathTo SaveXeroStaffMappingAction}
              hx-target="#admin-xero-fragment"
              hx-trigger="change"
              hx-swap="none"
              hx-swap-oob="outerHTML">
            <input type="hidden" name="staffId" value={tshow staff.id} />
            <select class="form-select form-select-sm" name="xeroEmployeeSelection" aria-label={"Xero employee for " <> staffFullName staff}>
                <option value="" selected={currentSelection == ""}>Unmapped</option>
                <option value="not_applicable" selected={currentSelection == "not_applicable"}>Not paid through Xero</option>
                {forEach selectableEmployees (renderXeroEmployeeOption currentSelection)}
            </select>
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
                <div class="col-12 col-md-5">
                    <label class="form-label small" for="xero-pay-item-account-code-selection">Synced account code</label>
                    <select id="xero-pay-item-account-code-selection" class="form-select form-select-sm" name="xeroPayItemAccountCodeSelection" disabled={not canManagePayItems}>
                        <option value="" selected={currentSelection == ""}>Not selected</option>
                        {forEach accountCodeOptions (renderXeroPayItemAccountCodeOption currentSelection)}
                        <option value="__manual__" selected={currentSelection == "__manual__"}>Use manual code</option>
                    </select>
                </div>
                <div class="col-12 col-md-4">
                    <label class="form-label small" for="xero-pay-item-account-code-manual">Manual account code</label>
                    <input id="xero-pay-item-account-code-manual" class="form-control form-control-sm" name="xeroPayItemAccountCodeManual" value={manualValue} disabled={not canManagePayItems} />
                </div>
                <div class="col-12 col-md-3">
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
        accountCodeOptions =
            xeroEarningsRates
                |> filter (.isActive)
                |> map (.accountCode)
                |> catMaybes
                |> map Text.strip
                |> filter (not . Text.null)
                |> List.nub
        selectedIsObserved = maybe False (`elem` accountCodeOptions) selectedAccountCode
        currentSelection =
            case selectedAccountCode of
                Just accountCode | selectedIsObserved -> accountCode
                Just _                                -> "__manual__"
                Nothing                               -> ""
        manualValue =
            if selectedIsObserved then "" else fromMaybe "" selectedAccountCode

renderXeroPayItemAccountCodeOption :: Text -> Text -> Html
renderXeroPayItemAccountCodeOption currentSelection accountCode = [hsx|
    <option value={accountCode} selected={currentSelection == accountCode}>{accountCode}</option>
|]

renderXeroPayItemRequirements :: [XeroPayItemRequirement] -> Maybe XeroPayItemAccountCodeSelection -> Bool -> Html
renderXeroPayItemRequirements requirements maybePayItemAccountCodeSelection canManagePayItems
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
                            <th>Required pay item</th>
                            <th>Type</th>
                            <th>Value</th>
                            <th>Xero status</th>
                            <th>Source</th>
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
        activeRequirements = filter (.payItemRequirementIsActive) requirements
        archivedRequirements = filter (not . (.payItemRequirementIsActive)) requirements
        matchedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "matched") activeRequirements)
        proposedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "proposed") activeRequirements)
        rateChangedCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "rate_changed") activeRequirements)
        staleCount = length (filter (\requirement -> requirement.payItemRequirementStatus == "stale") activeRequirements)
        archivedCount = length archivedRequirements
        hasAccountCode =
            case maybePayItemAccountCodeSelection of
                Just selection -> selection.selectionStatus == "verified" && maybe False (not . Text.null . Text.strip) selection.accountCode
                Nothing -> False

renderArchivedXeroPayItemRequirements :: [XeroPayItemRequirement] -> Html
renderArchivedXeroPayItemRequirements [] = mempty
renderArchivedXeroPayItemRequirements requirements = [hsx|
    <details class="mt-3">
        <summary class="small app-muted">Archived pay item requirements ({tshow (length requirements)})</summary>
        <div class="table-responsive mt-2">
            <table class="table table-sm align-middle mb-0">
                <thead>
                    <tr>
                        <th>Required pay item</th>
                        <th>Type</th>
                        <th>Value</th>
                        <th>Xero status</th>
                        <th>Source</th>
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
        <td>
            <div>{requirement.payItemRequirementName}</div>
            <div class="small app-muted">{requirement.payItemRequirementKey}</div>
        </td>
        <td><span class="badge text-bg-light border">{requirement.payItemRequirementRateType}</span></td>
        <td>{fromMaybe "per employee ordinary rate" requirement.payItemRequirementValue}</td>
        <td>{renderXeroPayItemRequirementStatus requirement}</td>
        <td class="small app-muted">{requirement.payItemRequirementSource}</td>
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

renderXeroEarningsRateMappings :: [XeroEarningsRate] -> [XeroEarningsBucketRow] -> XeroEarningsRateMappingCounts -> Html
renderXeroEarningsRateMappings xeroEarningsRates bucketRows mappingCounts
    | null xeroEarningsRates = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Earnings-rate mappings</h3>
            <p class="small app-muted mb-0">Sync payroll reference data before mapping local earning buckets to Xero earnings rates.</p>
        </div>
    |]
    | null bucketRows = [hsx|
        <div class="border rounded p-3">
            <h3 class="h6 mb-2">Earnings-rate mappings</h3>
            <p class="small app-muted mb-0">No active local earning buckets are available.</p>
        </div>
    |]
    | otherwise = [hsx|
        <div class="border rounded p-3">
            <div class="d-flex flex-wrap align-items-center justify-content-between gap-2 mb-3">
                <div>
                    <h3 class="h6 mb-1">Earnings-rate mappings</h3>
                    <p class="small app-muted mb-0">Map each local payroll earnings bucket to a synced Xero earnings rate.</p>
                </div>
                {renderXeroEarningsRateMappingCounts mappingCounts}
            </div>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Local bucket</th>
                            <th>Xero earnings rate</th>
                        </tr>
                    </thead>
                    <tbody>
                        {forEach bucketRows (renderXeroEarningsRateMappingRow xeroEarningsRates)}
                    </tbody>
                </table>
            </div>
        </div>
    |]

renderXeroEarningsRateMappingCounts :: XeroEarningsRateMappingCounts -> Html
renderXeroEarningsRateMappingCounts mappingCounts = [hsx|
    <div class="d-flex flex-wrap gap-2">
        <span class="badge text-bg-success">{tshow mappingCounts.xeroEarningsVerifiedCount} mapped</span>
        <span class="badge text-bg-secondary">{tshow mappingCounts.xeroEarningsUnmappedCount} unmapped</span>
        <span class="badge text-bg-warning">{tshow mappingCounts.xeroEarningsStaleCount} stale</span>
    </div>
|]

renderXeroEarningsRateMappingRow :: [XeroEarningsRate] -> XeroEarningsBucketRow -> Html
renderXeroEarningsRateMappingRow xeroEarningsRates row =
    let bucket = row.earningsBucketRowBucket
        currentSelection = xeroEarningsRateSelectionValue row.earningsBucketRowMapping
     in [hsx|
        <tr>
            <td>{bucket.localBucketLabel}</td>
            <td>
                <form method="POST"
                      action={SaveXeroEarningsRateMappingAction}
                      data-disable-javascript-submission="true"
                      hx-post={pathTo SaveXeroEarningsRateMappingAction}
                      hx-target="#admin-xero-fragment"
                      hx-trigger="change"
                      hx-swap="outerHTML">
                    <input type="hidden" name="localBucketKey" value={bucket.localBucketKey} />
                    <select class="form-select form-select-sm" name="xeroEarningsRateSelection" aria-label={"Xero earnings rate for " <> bucket.localBucketLabel}>
                        <option value="" selected={currentSelection == ""}>Unmapped</option>
                        {forEach xeroEarningsRates (renderXeroEarningsRateOption currentSelection)}
                    </select>
                </form>
            </td>
        </tr>
    |]

renderXeroEarningsRateOption :: Text -> XeroEarningsRate -> Html
renderXeroEarningsRateOption currentSelection earningsRate = [hsx|
    <option value={earningsRate.xeroEarningsRateId} selected={currentSelection == earningsRate.xeroEarningsRateId}>
        {xeroEarningsRateLabel earningsRate}
    </option>
|]

xeroEarningsRateSelectionValue :: Maybe XeroEarningsRateMapping -> Text
xeroEarningsRateSelectionValue Nothing = ""
xeroEarningsRateSelectionValue (Just mapping)
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEarningsRateId
    | otherwise = ""

xeroEarningsRateLabel :: XeroEarningsRate -> Text
xeroEarningsRateLabel earningsRate =
    Text.intercalate " - " (filter (not . Text.null) [earningsRate.name, fromMaybe "" earningsRate.earningsType])

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
            {renderXeroReadyChecklistItem checklist.xeroReadyEarningsMappings "Earnings-rate mappings are complete"}
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
            case row.mappingRowMapping of
                Just mapping
                    | rowStaffId row /= currentStaffId
                    , mapping.mappingStatus == "verified" -> mapping.xeroEmployeeId
                _ -> Nothing

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

xeroMappingSelectionValue :: Maybe XeroStaffMapping -> Text
xeroMappingSelectionValue Nothing = ""
xeroMappingSelectionValue (Just mapping)
    | mapping.mappingStatus == "not_applicable" = "not_applicable"
    | mapping.mappingStatus == "verified" = fromMaybe "" mapping.xeroEmployeeId
    | otherwise = ""

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
