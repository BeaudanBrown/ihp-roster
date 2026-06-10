module Web.View.Passkeys.Management
    ( formatRelativeLastUsed
    , renderPasskeyManagement
    , renderPasskeyManagementWithAddButton
    )
where

import Data.Time.Clock (diffUTCTime)
import Web.View.Prelude

renderPasskeyManagement :: UTCTime -> [Passkey] -> Text -> Html
renderPasskeyManagement now passkeys =
    renderPasskeyManagementWithAddButton now (null passkeys) passkeys

renderPasskeyManagementWithAddButton :: UTCTime -> Bool -> [Passkey] -> Text -> Html
renderPasskeyManagementWithAddButton now canAddPasskey passkeys successRedirect = [hsx|
    <div class="app-form-width" data-passkey-management="true">
        {renderPasskeyRegistrationAction canAddPasskey successRedirect}
        {renderNewDevicePasskeyAction passkeys}
        <div class="mt-4">
            {renderPasskeyTable now passkeys}
        </div>
    </div>
|]

renderPasskeyRegistrationAction :: (?context :: ControllerContext) => Bool -> Text -> Html
renderPasskeyRegistrationAction False _ = mempty
renderPasskeyRegistrationAction True successRedirect =
    let dialogUrl = appendQueryParams (pathTo ShowPasskeySetupDialogAction) [("successRedirect", successRedirect)]
     in [hsx|
    <div class="mb-3 js-passkey-management-add">
        <h3 class="h6 mb-2">Add a passkey</h3>
        <p class="app-muted mb-3">Use a passkey to sign in with Face ID, Touch ID, Windows Hello, or your device screen lock.</p>
        <a href={dialogUrl}
           class="btn btn-primary"
           hx-get={dialogUrl}
           hx-target={"#" <> dialogOverlayMountId}
           hx-swap="innerHTML"
           hx-push-url="false">Create passkey</a>
    </div>
|]

renderNewDevicePasskeyAction :: [Passkey] -> Html
renderNewDevicePasskeyAction [] = mempty
renderNewDevicePasskeyAction _ = [hsx|
    <form method="POST" action={SendNewDevicePasskeySetupEmailAction} class="mt-3">
        <button type="submit" class="btn btn-outline-secondary btn-sm">Email setup link for another device</button>
        <div class="form-text app-muted">Use this when you are passkey-verified here and want to add a passkey on another device.</div>
    </form>
|]

renderPasskeyTable :: UTCTime -> [Passkey] -> Html
renderPasskeyTable _ [] = [hsx|
    <p class="app-muted mb-0">No passkeys registered yet.</p>
|]
renderPasskeyTable now passkeys = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Name</th>
                    <th>Last used</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach passkeys (renderPasskeyRow now)}
            </tbody>
        </table>
    </div>
|]

renderPasskeyRow :: UTCTime -> Passkey -> Html
renderPasskeyRow now passkey = [hsx|
    <tr>
        <td>{passkey.name}</td>
        <td class="app-muted small">{formatRelativeLastUsed now passkey.lastUsedAt}</td>
        <td class="text-end">
            <form method="POST"
                  action={pathTo (DeletePasskeyAction passkey.id)}
                  class="d-inline"
                  onsubmit="return confirm('Delete this passkey? You may need to verify with a passkey before it is removed.')">
                <input type="hidden" name="_method" value="DELETE"/>
                <button type="submit" class="btn btn-sm btn-outline-danger">Delete</button>
            </form>
        </td>
    </tr>
|]

formatRelativeLastUsed :: UTCTime -> Maybe UTCTime -> Text
formatRelativeLastUsed _ Nothing = "Never"
formatRelativeLastUsed now (Just lastUsedAt)
    | secondsAgo < hourSeconds = "less than 1 hour ago"
    | secondsAgo < daySeconds = lessThan (ceilingUnit hourSeconds) "hour"
    | secondsAgo < weekSeconds = lessThan (ceilingUnit daySeconds) "day"
    | secondsAgo < monthSeconds = lessThan (ceilingUnit weekSeconds) "week"
    | otherwise = lessThan (ceilingUnit monthSeconds) "month"
  where
    secondsAgo = max 0 (floor (diffUTCTime now lastUsedAt) :: Int)
    hourSeconds = 60 * 60
    daySeconds = 24 * hourSeconds
    weekSeconds = 7 * daySeconds
    monthSeconds = 30 * daySeconds
    ceilingUnit unitSeconds = max 1 ((secondsAgo + unitSeconds - 1) `div` unitSeconds)

lessThan :: Int -> Text -> Text
lessThan amount unitName =
    "less than " <> tshow amount <> " " <> pluralize amount unitName <> " ago"

pluralize :: Int -> Text -> Text
pluralize 1 unitName = unitName
pluralize _ unitName = unitName <> "s"
