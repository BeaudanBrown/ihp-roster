module Web.View.Passkeys.Management
    ( renderPasskeyManagement
    , renderPasskeyManagementWithAddButton
    )
where

import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

renderPasskeyManagement :: [Passkey] -> Text -> Html
renderPasskeyManagement =
    renderPasskeyManagementWithAddButton True

renderPasskeyManagementWithAddButton :: Bool -> [Passkey] -> Text -> Html
renderPasskeyManagementWithAddButton canAddPasskey passkeys successRedirect = [hsx|
    <div class="app-form-width">
        {renderPasskeyRegistrationAction canAddPasskey successRedirect}
        <div class="mt-4">
            {renderPasskeyTable passkeys}
        </div>
    </div>
|]

renderPasskeyRegistrationAction :: Bool -> Text -> Html
renderPasskeyRegistrationAction False _ = mempty
renderPasskeyRegistrationAction True successRedirect = [hsx|
    <div class="js-passkey-register"
         data-begin-url={pathTo BeginPasskeyRegistrationAction}
         data-finish-url={pathTo FinishPasskeyRegistrationAction}
         data-status-id="passkey-management-status"
         data-success-redirect={successRedirect}>
        <button type="button" class="btn btn-outline-primary js-passkey-register-button">Add passkey</button>
    </div>
    <div id="passkey-management-status" class="alert d-none mt-3"></div>
|]

renderPasskeyTable :: [Passkey] -> Html
renderPasskeyTable [] = [hsx|
    <p class="app-muted mb-0">No passkeys registered yet.</p>
|]
renderPasskeyTable passkeys = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Created</th>
                    <th>Last used</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach passkeys renderPasskeyRow}
            </tbody>
        </table>
    </div>
|]

renderPasskeyRow :: Passkey -> Html
renderPasskeyRow passkey = [hsx|
    <tr>
        <td>
            <form method="POST" action={pathTo (UpdatePasskeyNameAction passkey.id)} class="d-flex gap-2">
                <input type="text" class="form-control form-control-sm" name="name" value={passkey.name} aria-label="Passkey name"/>
                <button type="submit" class="btn btn-sm btn-outline-secondary">Rename</button>
            </form>
        </td>
        <td class="app-muted small">{formatDateTime passkey.createdAt}</td>
        <td class="app-muted small">{maybe "Never" formatDateTime passkey.lastUsedAt}</td>
        <td class="text-end">
            <form method="POST" action={pathTo (DeletePasskeyAction passkey.id)} class="d-inline">
                <input type="hidden" name="_method" value="DELETE"/>
                <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
            </form>
        </td>
    </tr>
|]

formatDateTime :: UTCTime -> Text
formatDateTime = Text.pack . formatTime defaultTimeLocale "%d/%m/%Y %H:%M"
