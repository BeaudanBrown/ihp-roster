module Web.View.Passkeys.SetupModal
    ( PasskeySetupView (..)
    , PasskeySetupMode (..)
    , renderPasskeySetupDialog
    , renderPasskeySetupPageDialog
    , renderPasskeySetupPromptDialog
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
        , appPageHelpTopic = Nothing
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
    renderDialogOverlay (passkeySetupDialogConfig mode successRedirect)

renderPasskeySetupPromptDialog :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> Html
renderPasskeySetupPromptDialog mode successRedirect =
    renderPasskeyPromptDialogOverlay (passkeySetupDialogConfig mode successRedirect)

passkeySetupDialogConfig :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> DialogOverlayConfig
passkeySetupDialogConfig mode successRedirect = defaultDialogOverlayConfig
            (passkeySetupTitle mode)
            (renderPasskeySetupBody mode successRedirect)
            []

renderPasskeySetupPageDialog :: (?context :: ControllerContext) => Text -> PasskeySetupMode -> Text -> Html
renderPasskeySetupPageDialog closeUrl mode successRedirect =
    renderPageDialogModal closeUrl (defaultDialogOverlayConfig
            (passkeySetupTitle mode)
            (renderPasskeySetupBody mode successRedirect)
            [])
            { dialogOverlayDialogClass = "modal-dialog-centered"
            }

renderPasskeySetupBody :: (?context :: ControllerContext) => PasskeySetupMode -> Text -> Html
renderPasskeySetupBody mode successRedirect =
    let registrationControl = PasskeyRegistrationControl
            { passkeyRegistrationControlKind = PasskeyDialogRegistrationControl
            , passkeyRegistrationBeginUrl = pathTo BeginPasskeyRegistrationAction
            , passkeyRegistrationFinishUrl = pathTo FinishPasskeyRegistrationAction
            , passkeyRegistrationSuccessRedirect = Just successRedirect
            }
     in [hsx|
        <p class="app-muted">{passkeySetupBodyText mode}</p>
        {renderPasskeyRegistrationControl registrationControl}
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
