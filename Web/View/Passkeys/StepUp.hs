{-# LANGUAGE TypeApplications #-}

module Web.View.Passkeys.StepUp where

import Application.Helper.FrontendContract.AppShell (OpenPasskeyRecoveryCodeDialog)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
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
        , appPageHelpTopic = Nothing
            , appPageWidthClass = "app-form-width"
            , appPageBody =
                simpleAppPanel
                    "Verify with a passkey"
                    (Just "Venue admins and owners need passkey verification for high-security actions.")
                    [hsx|
                        {renderStepUpControl stepUpRedirectTo}
                    |]
            }

renderStepUpDialog :: Maybe Text -> Html
renderStepUpDialog redirectTo =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Passkey Verification"
            [hsx|
            <p class="app-muted">Confirm your identity to continue. The protected action has not run; retry it after verification.</p>
            {renderStepUpOverlayControl redirectTo}
        |]
            [ dialogOverlayCloseButton "Cancel"
            ])

renderStepUpControl :: Maybe Text -> Html
renderStepUpControl = renderStepUpControlWithKind PasskeyStepUpControl

renderStepUpOverlayControl :: Maybe Text -> Html
renderStepUpOverlayControl = renderStepUpControlWithKind PasskeyStepUpOverlayControl

renderStepUpControlWithKind :: PasskeyLoginControlKind -> Maybe Text -> Html
renderStepUpControlWithKind controlKind redirectTo =
    let loginControl = PasskeyLoginControl
            { passkeyLoginControlKind = controlKind
            , passkeyLoginBeginUrl = pathTo BeginPasskeyStepUpAuthenticationAction
            , passkeyLoginFinishUrl = pathTo FinishPasskeyStepUpAuthenticationAction
            , passkeyLoginSuccessRedirect = Just (fromMaybe (pathTo RosterWeeksAction) redirectTo)
            }
     in [hsx|
        {renderPasskeyLoginControl loginControl}
        <div class="text-center mt-3">
            {renderRecoveryCodeDialogLink}
        </div>
    |]

renderRecoveryCodeDialogLink :: (?context :: ControllerContext) => Html
renderRecoveryCodeDialogLink =
    renderAppShellActionLink
        (appShellActionByMarker @OpenPasskeyRecoveryCodeDialog)
        ((defaultAppShellActionRoute (pathTo ShowPasskeyRecoveryCodeDialogAction))
            { appShellActionRouteExtraAttrs = [("class", "small")]
            })
        [hsx|Can't access your passkey?|]

passkeyRecoveryCodeFormId :: Text
passkeyRecoveryCodeFormId = "passkey-recovery-code-form"

renderPasskeyRecoveryCodeDialog :: Html
renderPasskeyRecoveryCodeDialog =
    renderDialogOverlay (defaultDialogOverlayConfig
            "Recover Passkey Access"
            renderPasskeyRecoveryCodeForm
            [ dialogOverlayCloseButton "Cancel"
            , dialogOverlaySubmitButton "Use recovery code" passkeyRecoveryCodeFormId
            ])

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
