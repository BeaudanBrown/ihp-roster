module Web.View.Passkeys.StepUp where

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
                        {renderRecoveryGuidance}
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
|]

renderRecoveryGuidance :: Html
renderRecoveryGuidance = [hsx|
    <div class="border rounded-3 p-3 mt-4 bg-light">
        <h2 class="h6 mb-2">Can't access your passkey?</h2>
        <p class="app-muted small mb-3">
            Try using the same passkey from your phone or another signed-in device. If this is a new device, use the one-time recovery code you saved when passkeys were first set up.
        </p>
        <form method="POST" action={UsePasskeyRecoveryCodeAction}>
            <label class="form-label" for="passkey-recovery-code">Recovery code</label>
            <input id="passkey-recovery-code" class="form-control" name="recoveryCode" autocomplete="one-time-code" placeholder="XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"/>
            <button type="submit" class="btn btn-outline-primary mt-3">Use recovery code</button>
        </form>
        <p class="app-muted small mb-0 mt-3">
            Recovery codes can only be used once. If you do not have yours, ask a venue owner or support admin to send a recovery setup link.
        </p>
    </div>
|]
