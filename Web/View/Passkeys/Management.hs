module Web.View.Passkeys.Management
    ( renderPasskeyManagement
    , renderPasskeyManagementWithAddButton
    )
where

import Application.Helper.Controller (currentUserRequiresMandatoryPasskey)
import qualified Data.Text as Text
import Data.Time.Format (defaultTimeLocale, formatTime)
import Web.View.Prelude

renderPasskeyManagement :: [Passkey] -> Text -> Html
renderPasskeyManagement =
    renderPasskeyManagementWithAddButton True

renderPasskeyManagementWithAddButton :: Bool -> [Passkey] -> Text -> Html
renderPasskeyManagementWithAddButton canAddPasskey passkeys successRedirect = [hsx|
    <div class="app-form-width" data-passkey-management="true">
        {renderPasskeyRegistrationAction canAddPasskey successRedirect}
        {renderNewDevicePasskeyAction passkeys}
        {renderBackupPasskeyPrompt canAddPasskey passkeys}
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
        <div class="mb-3">
            <label class="form-label" for="passkey-management-name">Passkey name</label>
            <input id="passkey-management-name" type="text" class="form-control js-passkey-name" maxlength="120" placeholder="e.g. Work laptop" autocomplete="off"/>
            <div class="form-text app-muted">Use a name you will recognize later, such as this device or security key.</div>
        </div>
        <button type="button" class="btn btn-outline-primary js-passkey-register-button">Add passkey</button>
    </div>
    <div id="passkey-management-status" class="alert d-none mt-3"></div>
|]

renderNewDevicePasskeyAction :: [Passkey] -> Html
renderNewDevicePasskeyAction [] = mempty
renderNewDevicePasskeyAction _ = [hsx|
    <form method="POST" action={SendNewDevicePasskeySetupEmailAction} class="mt-3">
        <button type="submit" class="btn btn-outline-secondary btn-sm">Email setup link for another device</button>
        <div class="form-text app-muted">Use this when you are passkey-verified here and want to add a passkey on another device.</div>
    </form>
|]

renderBackupPasskeyPrompt :: Bool -> [Passkey] -> Html
renderBackupPasskeyPrompt canAddPasskey passkeys
    | currentUserRequiresMandatoryPasskey && length passkeys == 1 = [hsx|
        <div class="alert alert-warning mt-3 mb-0">
            <strong>Add a backup passkey.</strong>
            Venue admins, owners, and support admins should keep at least two passkeys so a lost device does not block privileged access.
            {renderBackupPasskeyPromptAction canAddPasskey}
        </div>
    |]
    | otherwise = mempty

renderBackupPasskeyPromptAction :: Bool -> Html
renderBackupPasskeyPromptAction True = [hsx|
    <div class="small mt-2">Use the add-passkey form on this page, or email yourself a setup link for another device.</div>
|]
renderBackupPasskeyPromptAction False = [hsx|
    <div class="small mt-2">Email yourself a setup link for another device, then open it there to add a backup passkey.</div>
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
