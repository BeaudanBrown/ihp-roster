module Web.View.Passkeys.SetupModal
    ( PasskeySetupView (..)
    , PasskeySetupMode (..)
    , renderPasskeySetupDialog
    , renderPasskeySetupModal
    ) where

import Web.View.Prelude

newtype PasskeySetupView = PasskeySetupView
    { passkeySetupRedirectTo :: Text
    }

instance View PasskeySetupView where
    html PasskeySetupView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Passkey Setup"
            , appPageDescription = Just "Create a passkey before continuing to restricted account or venue administration."
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = renderPasskeySetupModal MandatoryFirstPasskey passkeySetupRedirectTo (Just (pathTo DismissMandatoryPasskeySetupAction))
            }

data PasskeySetupMode
    = OptionalFirstPasskey
    | OptionalAdditionalDevice
    | MandatoryFirstPasskey
    | RecoveryReplacementPasskey
    deriving (Eq, Show)

renderPasskeySetupDialog :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> Html
renderPasskeySetupDialog mode successRedirect =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = passkeySetupTitle mode
        , dialogOverlayBody = renderPasskeySetupBody mode successRedirect
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = []
        , dialogOverlayDialogClass = ""
        }

renderPasskeySetupModal :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> Maybe Text -> Html
renderPasskeySetupModal mode successRedirect maybeDismissUrl = [hsx|
    <div class="modal fade show d-block js-passkey-setup-modal"
         data-passkey-setup-modal="true"
         tabindex="-1"
         role="dialog"
         aria-modal="true"
         aria-labelledby="passkey-setup-modal-title">
        <div class="modal-dialog modal-dialog-centered" role="document">
            <div class="modal-content shadow">
                <div class="modal-header">
                    <h5 class="modal-title" id="passkey-setup-modal-title">{passkeySetupTitle mode}</h5>
                    {renderPasskeyDismissButton maybeDismissUrl}
                </div>
                <div class="modal-body">
                    {renderPasskeySetupBody mode successRedirect}
                </div>
            </div>
        </div>
    </div>
    <div class="modal-backdrop fade show js-passkey-setup-modal-backdrop" data-passkey-setup-dismiss={fromMaybe "" maybeDismissUrl}></div>
|]

renderPasskeySetupBody :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> Html
renderPasskeySetupBody mode successRedirect = [hsx|
    <p class="app-muted">{passkeySetupBodyText mode}</p>
    <div class="js-passkey-register"
         data-begin-url={pathTo BeginPasskeyRegistrationAction}
         data-finish-url={pathTo FinishPasskeyRegistrationAction}
         data-status-id="passkey-setup-modal-status"
         data-success-redirect={successRedirect}>
        <div class="mb-3">
            <label class="form-label" for="passkey-setup-modal-name">Passkey name</label>
            <input id="passkey-setup-modal-name" type="text" class="form-control js-passkey-name" maxlength="120" placeholder="This device" autocomplete="off"/>
            <div class="form-text app-muted">Use a name you will recognize later, such as this device or security key.</div>
        </div>
        <button type="button" class="btn btn-primary js-passkey-register-button">Create passkey</button>
    </div>
    <div id="passkey-setup-modal-status" class="alert d-none mt-3 mb-0"></div>
|]

renderPasskeyDismissButton :: Maybe Text -> Html
renderPasskeyDismissButton Nothing = mempty
renderPasskeyDismissButton (Just dismissUrl) = [hsx|
    <a href={dismissUrl} class="btn-close js-passkey-setup-dismiss" aria-label="Close"></a>
|]

passkeySetupTitle :: PasskeySetupMode -> Text
passkeySetupTitle OptionalFirstPasskey = "Set up faster sign-in"
passkeySetupTitle OptionalAdditionalDevice = "Add this device as a passkey"
passkeySetupTitle MandatoryFirstPasskey = "Create a passkey for admin access"
passkeySetupTitle RecoveryReplacementPasskey = "Create a replacement passkey"

passkeySetupBodyText :: PasskeySetupMode -> Text
passkeySetupBodyText OptionalFirstPasskey =
    "A passkey lets you sign in with Face ID, Touch ID, Windows Hello or your device screen lock instead of typing your password. You can skip this for now."
passkeySetupBodyText OptionalAdditionalDevice =
    "This account already has a passkey. Add one here if you want this browser or device to offer the same quick sign-in."
passkeySetupBodyText MandatoryFirstPasskey =
    "You can keep using the roster, but restricted venue administration requires a passkey to protect staff and payroll data."
passkeySetupBodyText RecoveryReplacementPasskey =
    "Your recovery code has been accepted. Create a new passkey now to restore restricted account access."
