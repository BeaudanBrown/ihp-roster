module Web.View.Admin.Xero.Connection
    ( renderXeroConnectionDetails
    , renderXeroDisconnectedConnectionDetails
    ) where

import Application.Helper.XeroAdminTypes
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

renderXeroConnectionDetails :: XeroConnection -> Bool -> Html
renderXeroConnectionDetails connection connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="d-flex align-items-center gap-2 flex-wrap">
            <span>{fromMaybe connection.tenantId connection.tenantName}</span>
            {renderXeroConnectionStatus connection}
            {renderXeroConnectionError connection}
        </div>
        {renderXeroConnectionNotice connection}
        <div id="xero-reference-sync-indicator" class="htmx-indicator small app-muted d-inline-flex align-items-center gap-2" aria-live="polite">
            <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
            <span>Syncing Xero payroll reference data...</span>
        </div>
        <div class="d-flex flex-wrap gap-2">
            {renderXeroReconnectControls connectionActionsAllowed}
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
                Xero needs to be reconnected before sync can continue. Use Reconnect to authorize {fromMaybe connection.tenantId connection.tenantName} again; existing staff mappings will be kept. To switch organisations, disconnect first and then connect Xero again.
            </div>
        |]
        "error" -> [hsx|
            <div class="alert alert-danger mb-0" role="alert">
                Xero needs attention before sync can continue. Try Reconnect, or Disconnect if you want this app to remove the linked organisation in Xero.
            </div>
        |]
        _ -> mempty

