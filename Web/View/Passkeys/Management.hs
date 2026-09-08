{-# LANGUAGE TypeApplications #-}

module Web.View.Passkeys.Management
    ( formatRelativeLastUsed
    , renderPasskeyManagement
    , renderPasskeyManagementWithAddButton
    )
where

import Application.Helper.FrontendContract.AppShell (OpenPasskeySetupDialog,
                                                     SubmitPasskeyProtectedAction)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionForm,
                                                             renderAppShellActionLink)
import Web.View.Prelude

renderPasskeyManagement :: UTCTime -> [Passkey] -> Text -> Html
renderPasskeyManagement now passkeys =
    renderPasskeyManagementWithAddButton now (null passkeys) passkeys

renderPasskeyManagementWithAddButton :: UTCTime -> Bool -> [Passkey] -> Text -> Html
renderPasskeyManagementWithAddButton now canAddPasskey passkeys successRedirect = [hsx|
    <div class="app-form-width">
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
    <div class="mb-3">
        <h3 class="h6 mb-2">{canonicalPasskeyManagementCopy.passkeyManagementAddTitle}</h3>
        <p class="app-muted mb-3">{canonicalPasskeyManagementCopy.passkeyManagementAddBody}</p>
        {renderPasskeySetupDialogLink dialogUrl}
    </div>
|]

renderPasskeySetupDialogLink :: Text -> Html
renderPasskeySetupDialogLink dialogUrl =
    renderAppShellActionLink
        (appShellActionByMarker @OpenPasskeySetupDialog)
        ((defaultAppShellActionRoute (dialogUrl))
            { appShellActionRouteExtraAttrs = [("class", "btn btn-primary")]
            })
        [hsx|{canonicalPasskeyManagementCopy.passkeyManagementCreateLabel}|]

renderNewDevicePasskeyAction :: [Passkey] -> Html
renderNewDevicePasskeyAction [] = mempty
renderNewDevicePasskeyAction _ =
    renderAppShellActionForm
        (appShellActionByMarker @SubmitPasskeyProtectedAction)
        ((defaultAppShellActionRoute (pathTo SendNewDevicePasskeySetupEmailAction))
            { appShellActionRouteExtraAttrs = [("class", "mt-3")]
            })
        [hsx|
            <button type="submit" class="btn btn-outline-secondary btn-sm">{canonicalPasskeyManagementCopy.passkeyManagementNewDeviceLabel}</button>
            <div class="form-text app-muted">{canonicalPasskeyManagementCopy.passkeyManagementNewDeviceHelp}</div>
        |]

renderPasskeyTable :: UTCTime -> [Passkey] -> Html
renderPasskeyTable _ [] = [hsx|
    <p class="app-muted mb-0">{canonicalPasskeyManagementCopy.passkeyManagementEmptyLabel}</p>
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
                  onsubmit={passkeyDeleteConfirmationAttribute}>
                <input type="hidden" name="_method" value="DELETE"/>
                <button type="submit" class="btn btn-sm btn-outline-danger">{canonicalPasskeyManagementCopy.passkeyManagementDeleteLabel}</button>
            </form>
        </td>
    </tr>
|]

passkeyDeleteConfirmationAttribute :: Text
passkeyDeleteConfirmationAttribute =
    "return window.confirm(" <> show canonicalPasskeyManagementCopy.passkeyManagementDeleteConfirmation <> ");"

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
