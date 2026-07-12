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
            Connecting grants Bepis access to the selected Xero organisation for payroll integration setup.
        </p>
        {renderXeroConnectControl connectionActionsAllowed}
    </div>
|]

renderXeroConnectionDetails :: XeroConnection -> Html
renderXeroConnectionDetails connection = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="d-flex align-items-center gap-2 flex-wrap">
            <span>{fromMaybe connection.tenantId connection.tenantName}</span>
            {renderXeroConnectionStatus connection}
            {renderXeroConnectionError connection}
        </div>
        {renderXeroConnectionNotice connection}
    </div>
|]

renderXeroConnectControl :: Bool -> Html
renderXeroConnectControl True = [hsx|
    <form method="POST" action={StartXeroConnectionAction}>
        <button class="btn btn-outline-primary" type="submit">Connect Xero</button>
    </form>
|]
renderXeroConnectControl False = [hsx|
    <p class="mb-0 small app-muted">Only the venue owner or a super admin can connect Xero for this venue.</p>
|]

renderXeroConnectionStatus :: XeroConnection -> Html
renderXeroConnectionStatus connection =
    case connection.connectionStatus of
        "active" -> [hsx|
            <span id="xero-connection-status-badge" class="badge app-status-badge app-status-success xero-connection-status-badge" role="status" aria-live="polite">
                <span class="xero-connection-status-label">connected</span>
                <span class="xero-connection-sync-label">
                    <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
                    <span>syncing</span>
                </span>
            </span>
        |]
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
                Xero needs to be reconnected before sync can continue. Start a Xero action to authorize {fromMaybe connection.tenantId connection.tenantName} again; existing staff mappings will be kept. To switch organisations, disconnect first and then connect Xero again.
            </div>
        |]
        "error" -> [hsx|
            <div class="alert alert-danger mb-0" role="alert">
                Xero needs attention before sync can continue. Try a Xero action again, or disconnect if you want this app to remove the linked organisation in Xero.
            </div>
        |]
        _ -> mempty

