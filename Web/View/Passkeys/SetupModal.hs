module Web.View.Passkeys.SetupModal
    ( PasskeySetupView (..)
    , PasskeySetupMode (..)
    , renderPasskeySetupDialog
    , renderPasskeySetupPageDialog
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
            , appPageBody = renderPasskeySetupPageDialog (pathTo DismissMandatoryPasskeySetupAction) MandatoryFirstPasskey passkeySetupRedirectTo
            }

data PasskeySetupMode
    = OptionalFirstPasskey
    | OptionalAdditionalDevice
    | MandatoryFirstPasskey
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

renderPasskeySetupPageDialog :: (?context :: ControllerContext) => Text -> PasskeySetupMode -> Text -> Html
renderPasskeySetupPageDialog closeUrl mode successRedirect =
    renderPageDialogModal closeUrl DialogOverlayConfig
        { dialogOverlayTitle = passkeySetupTitle mode
        , dialogOverlayBody = renderPasskeySetupBody mode successRedirect
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = []
        , dialogOverlayDialogClass = "modal-dialog-centered"
        }

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

passkeySetupTitle :: PasskeySetupMode -> Text
passkeySetupTitle OptionalFirstPasskey     = "Set up faster sign-in"
passkeySetupTitle OptionalAdditionalDevice = "Add this device as a passkey"
passkeySetupTitle MandatoryFirstPasskey    = "Create a passkey for admin access"

passkeySetupBodyText :: PasskeySetupMode -> Text
passkeySetupBodyText OptionalFirstPasskey =
    "A passkey lets you sign in with Face ID, Touch ID, Windows Hello or your device screen lock instead of typing your password. You can skip this for now."
passkeySetupBodyText OptionalAdditionalDevice =
    "This account already has a passkey. Add one here if you want this browser or device to offer the same quick sign-in."
passkeySetupBodyText MandatoryFirstPasskey =
    "You can keep using the roster, but restricted venue administration requires a passkey to protect staff and payroll data."
