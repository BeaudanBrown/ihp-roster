{-# LANGUAGE TypeApplications #-}

module Application.Helper.View.Passkey
    ( PasskeyLoginControl (..)
    , PasskeyLoginControlKind (..)
    , PasskeyManagementCopy (..)
    , PasskeyRegistrationControl (..)
    , PasskeyRegistrationControlKind (..)
    , canonicalPasskeyManagementCopy
    , renderPasskeyLoginControl
    , renderPasskeyPromptDialogOverlay
    , renderPasskeyRegistrationControl
    ) where

import qualified Application.Helper.FrontendContract.Passkey as Contract
import Application.Helper.FrontendContract.Passkey.Runtime
import Application.Helper.View.Overlay (DialogOverlayConfig,
                                        renderDialogOverlayWithCloseRole)
import IHP.ViewPrelude

data PasskeyLoginControlKind
    = PasskeySignInControl
    | PasskeyStepUpControl
    | PasskeyStepUpOverlayControl
    deriving (Eq, Show)

data PasskeyLoginControl = PasskeyLoginControl
    { passkeyLoginControlKind     :: !PasskeyLoginControlKind
    , passkeyLoginBeginUrl        :: !Text
    , passkeyLoginFinishUrl       :: !Text
    , passkeyLoginSuccessRedirect :: !(Maybe Text)
    }

data PasskeyManagementCopy = PasskeyManagementCopy
    { passkeyManagementAddTitle           :: !Text
    , passkeyManagementAddBody            :: !Text
    , passkeyManagementCreateLabel        :: !Text
    , passkeyManagementNewDeviceLabel     :: !Text
    , passkeyManagementNewDeviceHelp      :: !Text
    , passkeyManagementEmptyLabel         :: !Text
    , passkeyManagementDeleteLabel        :: !Text
    , passkeyManagementDeleteConfirmation :: !Text
    }
    deriving (Eq, Show)

canonicalPasskeyManagementCopy :: PasskeyManagementCopy
canonicalPasskeyManagementCopy = PasskeyManagementCopy
    { passkeyManagementAddTitle = "Add a passkey"
    , passkeyManagementAddBody = "Use a passkey to sign in with Face ID, Touch ID, Windows Hello, or your device screen lock."
    , passkeyManagementCreateLabel = "Create passkey"
    , passkeyManagementNewDeviceLabel = "Email setup link for another device"
    , passkeyManagementNewDeviceHelp = "Use this when you are passkey-verified here and want to add a passkey on another device."
    , passkeyManagementEmptyLabel = "No passkeys registered yet."
    , passkeyManagementDeleteLabel = "Delete"
    , passkeyManagementDeleteConfirmation = "Delete this passkey? You may need to verify with a passkey before it is removed."
    }

data PasskeyRegistrationControlKind
    = PasskeyDialogRegistrationControl
    | PasskeySetupLinkRegistrationControl
    deriving (Eq, Show)

data PasskeyRegistrationControl = PasskeyRegistrationControl
    { passkeyRegistrationControlKind     :: !PasskeyRegistrationControlKind
    , passkeyRegistrationBeginUrl        :: !Text
    , passkeyRegistrationFinishUrl       :: !Text
    , passkeyRegistrationSuccessRedirect :: !(Maybe Text)
    }

renderPasskeyLoginControl :: PasskeyLoginControl -> Html
renderPasskeyLoginControl control = [hsx|
    <div {...passkeyLoginAttrs control.passkeyLoginBeginUrl control.passkeyLoginFinishUrl control.passkeyLoginSuccessRedirect (passkeyLoginAutoStarts control.passkeyLoginControlKind) (passkeyLoginClosesOverlay control.passkeyLoginControlKind)}>
        <div class="d-grid">
            <button type="button"
                    class={passkeyLoginButtonClass control.passkeyLoginControlKind}
                    {...passkeyActionButtonAttrs}>
                {passkeyLoginButtonLabel control.passkeyLoginControlKind}
            </button>
        </div>
        {renderPasskeyStatusRegion}
    </div>
|]

renderPasskeyPromptDialogOverlay :: DialogOverlayConfig -> Html
renderPasskeyPromptDialogOverlay =
    renderDialogOverlayWithCloseRole @Contract.PasskeyDismissal

renderPasskeyRegistrationControl :: PasskeyRegistrationControl -> Html
renderPasskeyRegistrationControl control = [hsx|
    <div {...passkeyRegistrationAttrs control.passkeyRegistrationBeginUrl control.passkeyRegistrationFinishUrl control.passkeyRegistrationSuccessRedirect}>
        <div class="mb-3">
            <label class="form-label" for={passkeyRegistrationNameId control.passkeyRegistrationControlKind}>Passkey name</label>
            <input id={passkeyRegistrationNameId control.passkeyRegistrationControlKind}
                   type="text"
                   class="form-control"
                   maxlength="120"
                   placeholder={passkeyRegistrationNamePlaceholder control.passkeyRegistrationControlKind}
                   autocomplete="off"
                   {...passkeyDeviceNameAttrs}/>
            <div class="form-text app-muted">Use a name you will recognize later, such as this device or security key.</div>
        </div>
        {renderPasskeyRegistrationButton control.passkeyRegistrationControlKind}
        {renderPasskeyRegistrationStatusRegion control.passkeyRegistrationSuccessRedirect}
    </div>
|]

renderPasskeyStatusRegion :: Html
renderPasskeyStatusRegion = [hsx|
    <div class="alert d-none mt-3"
         role="status"
         aria-live="polite"
         aria-atomic="true">
        <span {...passkeyStatusAttrs}></span>
    </div>
|]

renderPasskeyRegistrationStatusRegion :: Maybe Text -> Html
renderPasskeyRegistrationStatusRegion successRedirect = [hsx|
    <div class="alert d-none mt-3 mb-0"
         role="status"
         aria-live="polite"
         aria-atomic="true">
        <span {...passkeyStatusAttrs}></span>
        <div hidden="hidden" {...passkeyRecoveryAttrs}>
            <strong>Save this recovery code now.</strong>
            <p class="mb-2">This code is shown once and can be used if you lose access to your passkey.</p>
            <code class="d-block fs-5 my-2 user-select-all"></code>
            {renderPasskeyRecoveryContinue successRedirect}
        </div>
    </div>
|]

renderPasskeyRecoveryContinue :: Maybe Text -> Html
renderPasskeyRecoveryContinue Nothing = mempty
renderPasskeyRecoveryContinue (Just successRedirect) = [hsx|
    <a class="btn btn-sm btn-primary mt-2" href={successRedirect}>I have saved it</a>
|]

renderPasskeyRegistrationButton :: PasskeyRegistrationControlKind -> Html
renderPasskeyRegistrationButton PasskeyDialogRegistrationControl = [hsx|
    <button type="button" class="btn btn-primary" {...passkeyActionButtonAttrs}>Create passkey</button>
|]
renderPasskeyRegistrationButton PasskeySetupLinkRegistrationControl = [hsx|
    <div class="d-grid">
        <button type="button" class="btn btn-primary" {...passkeyActionButtonAttrs}>Create passkey</button>
    </div>
|]

passkeyRegistrationNameId :: PasskeyRegistrationControlKind -> Text
passkeyRegistrationNameId PasskeyDialogRegistrationControl = "passkey-setup-modal-name"
passkeyRegistrationNameId PasskeySetupLinkRegistrationControl = "passkey-setup-link-name"

passkeyRegistrationNamePlaceholder :: PasskeyRegistrationControlKind -> Text
passkeyRegistrationNamePlaceholder PasskeyDialogRegistrationControl = "This device"
passkeyRegistrationNamePlaceholder PasskeySetupLinkRegistrationControl = "e.g. New laptop"

passkeyLoginButtonClass :: PasskeyLoginControlKind -> Text
passkeyLoginButtonClass PasskeySignInControl = "btn btn-outline-primary"
passkeyLoginButtonClass PasskeyStepUpControl = "btn btn-primary"
passkeyLoginButtonClass PasskeyStepUpOverlayControl = "btn btn-primary"

passkeyLoginButtonLabel :: PasskeyLoginControlKind -> Text
passkeyLoginButtonLabel PasskeySignInControl = "Sign in with a passkey"
passkeyLoginButtonLabel PasskeyStepUpControl = "Verify with passkey"
passkeyLoginButtonLabel PasskeyStepUpOverlayControl = "Verify with passkey"

passkeyLoginAutoStarts :: PasskeyLoginControlKind -> Bool
passkeyLoginAutoStarts PasskeyStepUpOverlayControl = True
passkeyLoginAutoStarts _ = False

passkeyLoginClosesOverlay :: PasskeyLoginControlKind -> Bool
passkeyLoginClosesOverlay PasskeyStepUpOverlayControl = True
passkeyLoginClosesOverlay _ = False
