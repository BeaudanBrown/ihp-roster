module Web.View.Admin.Xero.Connection
    ( renderXeroConnectionDetails
    , renderXeroDisconnectedConnectionDetails
    ) where

import Application.Helper.XeroAdminTypes
import Web.View.Admin.Xero.Calendars (renderXeroPayrollCalendarSelection)
import Web.View.Admin.Xero.PayItems (renderXeroPayItemAccountCodeSelection)
import Web.View.Admin.Xero.Readiness (renderXeroReadyChecklist)
import Web.View.Prelude

renderXeroDisconnectedConnectionDetails :: Bool -> Html
renderXeroDisconnectedConnectionDetails connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <dl class="row mb-0">
            <dt class="col-sm-3">Connection status</dt>
            <dd class="col-sm-9">{renderAppStatusBadge AppStatusNeutral "not connected"}</dd>
        </dl>
        <p class="mb-0 app-muted">
            Connecting grants ihp-roster access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
    </div>
|]

renderXeroConnectionDetails :: XeroConnection -> Maybe User -> Maybe XeroSyncRun -> Int -> Int -> Int -> [XeroEarningsRate] -> [XeroPayrollCalendar] -> Maybe XeroPayrollCalendarSelection -> Maybe XeroPayItemAccountCodeSelection -> XeroReadyChecklist -> Bool -> Html
renderXeroConnectionDetails connection _ maybeSyncRun employeeCount earningsRateCount payrollCalendarCount xeroEarningsRates xeroPayrollCalendars maybePayrollCalendarSelection maybePayItemAccountCodeSelection readyChecklist connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <dl class="row mb-0">
            <dt class="col-sm-3">Tenant</dt>
            <dd class="col-sm-9">{fromMaybe connection.tenantId connection.tenantName}</dd>
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
                  hx-swap="outerHTML"
                  hx-indicator="#xero-reference-sync-indicator">
                <button class="btn btn-outline-primary" type="submit" disabled={connection.connectionStatus /= "active"}>Sync payroll reference data</button>
            </form>
            {renderXeroReconnectControls connectionActionsAllowed}
        </div>
        {renderXeroReferenceSyncIndicator maybeSyncRun}
        <div class="row g-3">
            <div class="col-12 col-xl-6">
                {renderXeroPayItemAccountCodeSelection xeroEarningsRates maybePayItemAccountCodeSelection connectionActionsAllowed}
            </div>
            <div class="col-12 col-xl-6">
                {renderXeroPayrollCalendarSelection xeroPayrollCalendars maybePayrollCalendarSelection}
            </div>
            <div class="col-12">
                {renderXeroReadyChecklist readyChecklist}
            </div>
        </div>
    </div>
|]

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
        "active" -> renderAppStatusBadge AppStatusSuccess "connected"
        "reauthorization_required" -> renderAppStatusBadge AppStatusWarning "reconnect required"
        "error" -> renderAppStatusBadge AppStatusDanger "attention needed"
        "disconnected" -> renderAppStatusBadge AppStatusNeutral "disconnected"
        status -> renderAppStatusBadge AppStatusNeutral status

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
            {renderAppStatusBadge AppStatusNeutral (tshow employeeCount <> " employees")}
            {renderAppStatusBadge AppStatusNeutral (tshow earningsRateCount <> " earnings rates")}
            {renderAppStatusBadge AppStatusNeutral (tshow payrollCalendarCount <> " payroll calendars")}
            {renderXeroReferenceSyncStatus maybeSyncRun}
        </div>
    </div>
|]

renderXeroReferenceSyncStatus :: Maybe XeroSyncRun -> Html
renderXeroReferenceSyncStatus (Just syncRun)
    | syncRun.syncStatus == "running" = renderAppStatusBadge AppStatusInfo "syncing"
    | otherwise = mempty
renderXeroReferenceSyncStatus Nothing =
    mempty

renderXeroReferenceSyncIndicator :: Maybe XeroSyncRun -> Html
renderXeroReferenceSyncIndicator maybeSyncRun =
    mconcat
        [ renderClientSideIndicator
        , renderServerSideRunningIndicator maybeSyncRun
        ]

renderClientSideIndicator :: Html
renderClientSideIndicator = [hsx|
    <div id="xero-reference-sync-indicator" class="htmx-indicator d-flex align-items-center gap-2 small text-primary" role="status" aria-live="polite">
        <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
        <span>Syncing payroll reference data...</span>
    </div>
|]

renderServerSideRunningIndicator :: Maybe XeroSyncRun -> Html
renderServerSideRunningIndicator (Just syncRun)
    | syncRun.syncStatus == "running" = [hsx|
        <div class="d-flex align-items-center gap-2 small text-primary" role="status" aria-live="polite">
            <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
            <span>Syncing payroll reference data...</span>
        </div>
    |]
    | otherwise = mempty
renderServerSideRunningIndicator Nothing =
    mempty
