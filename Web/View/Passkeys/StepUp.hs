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
                    (renderStepUpControl stepUpRedirectTo)
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
