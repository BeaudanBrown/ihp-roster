{-# LANGUAGE TypeApplications #-}

module Web.View.Passkeys.StepUp where

import Application.Helper.FrontendContract.AppShell (OpenPasskeyRecoveryCodeDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             renderAppShellActionLink)
import Web.View.Prelude

data StepUpView = StepUpView
    { stepUpRedirectTo :: Maybe Text
    }

instance View StepUpView where
    html StepUpView { .. } =
        renderAppPage AppPageConfig
            { appPageTitle = "Passkey Verification"
            , appPageDescription = Just "Confirm your identity before continuing to privileged venue administration."
            , appPageActions = mempty
            , appPageWidthClass = "app-form-width"
            , appPageBody =
                simpleAppPanel
                    "Verify with a passkey"
                    (Just "Venue admins and owners need passkey verification for high-security actions.")
                    [hsx|
                        {renderStepUpControl stepUpRedirectTo}
                    |]
            }

renderStepUpControl :: Maybe Text -> Html
renderStepUpControl redirectTo = [hsx|
    <div class="js-passkey-login"
         data-begin-url={pathTo BeginPasskeyStepUpAuthenticationAction}
         data-finish-url={pathTo FinishPasskeyStepUpAuthenticationAction}
         data-status-id="passkey-step-up-status"
         data-success-redirect={fromMaybe (pathTo RosterWeeksAction) redirectTo}>
        <div class="d-grid">
            <button type="button" class="btn btn-primary js-passkey-login-button">Verify with passkey</button>
        </div>
    </div>
    <div id="passkey-step-up-status" class="alert d-none mt-3"></div>
    <div class="text-center mt-3">
        {renderRecoveryCodeDialogLink}
    </div>
|]

renderRecoveryCodeDialogLink :: (?context :: ControllerContext) => Html
renderRecoveryCodeDialogLink =
    renderAppShellActionLink
        (appShellActionByMarker @OpenPasskeyRecoveryCodeDialog)
        AppShellActionRoute
            { appShellActionRouteUrl = pathTo ShowPasskeyRecoveryCodeDialogAction
            , appShellActionRouteFields = []
            , appShellActionRouteCustomHtmx = []
            , appShellActionRouteStandardUrl = Nothing
            , appShellActionRouteExtraAttrs = [("class", "small")]
            }
        [hsx|Can't access your passkey?|]

passkeyRecoveryCodeFormId :: Text
passkeyRecoveryCodeFormId = "passkey-recovery-code-form"

renderPasskeyRecoveryCodeDialog :: Html
renderPasskeyRecoveryCodeDialog =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Recover Passkey Access"
        , dialogOverlayBody = renderPasskeyRecoveryCodeForm
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons =
            [ OverlayButton
                { overlayButtonLabel = "Cancel"
                , overlayButtonClass = "btn btn-outline-secondary"
                , overlayButtonAction = OverlayCloseAction
                }
            , OverlayButton
                { overlayButtonLabel = "Use recovery code"
                , overlayButtonClass = "btn btn-primary"
                , overlayButtonAction = OverlaySubmitFormAction passkeyRecoveryCodeFormId
                }
            ]
        , dialogOverlayDialogClass = ""
        }

renderPasskeyRecoveryCodeForm :: Html
renderPasskeyRecoveryCodeForm = [hsx|
    <p class="app-muted mb-3">
        Try using the same passkey from your phone or another signed-in device. If this is a new device, enter the one-time recovery code you saved when passkeys were first set up.
    </p>
    <form id={passkeyRecoveryCodeFormId} method="POST" action={UsePasskeyRecoveryCodeAction}>
        <label class="form-label" for="passkey-recovery-code">Recovery code</label>
        <input id="passkey-recovery-code"
               class="form-control"
               name="recoveryCode"
               autocomplete="one-time-code"
               placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"/>
    </form>
    <p class="app-muted small mb-0 mt-3">
        Recovery codes can only be used once. If you do not have yours, ask a venue owner or support admin to send a recovery setup link.
    </p>
|]
