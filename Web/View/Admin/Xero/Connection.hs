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

renderXeroConnectionDetails :: XeroConnection -> Bool -> Html
renderXeroConnectionDetails connection connectionActionsAllowed = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="d-flex align-items-center gap-2 flex-wrap">
            <span>{fromMaybe connection.tenantId connection.tenantName}</span>
            {renderXeroConnectionStatus connection}
            {renderXeroConnectionError connection}
        </div>
        {renderXeroConnectionNotice connection}
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
    <form method="POST"
          action={SyncXeroPayrollReferenceDataAction}
          data-disable-javascript-submission="true"
          hx-post={pathTo SyncXeroPayrollReferenceDataAction}
          hx-target="#admin-xero-fragment"
          hx-swap="outerHTML"
          hx-push-url={pathTo XeroAction}
          hx-indicator="#xero-connection-status-badge">
        <button class="btn btn-outline-primary" type="submit">Refresh Xero data</button>
    </form>
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
                Xero needs to be reconnected before sync can continue. Use Reconnect to authorize {fromMaybe connection.tenantId connection.tenantName} again; existing staff mappings will be kept. To switch organisations, disconnect first and then connect Xero again.
            </div>
        |]
        "error" -> [hsx|
            <div class="alert alert-danger mb-0" role="alert">
                Xero needs attention before sync can continue. Try Reconnect, or Disconnect if you want this app to remove the linked organisation in Xero.
            </div>
        |]
        _ -> mempty

