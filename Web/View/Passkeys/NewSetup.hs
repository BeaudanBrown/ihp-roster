module Web.View.Passkeys.NewSetup where

import Web.View.Prelude

data NewSetupView = NewSetupView
    { targetEmail :: Text
    , beginUrl    :: Text
    }

instance View NewSetupView where
    html NewSetupView { .. } =
        let registrationControl = PasskeyRegistrationControl
                { passkeyRegistrationControlKind = PasskeySetupLinkRegistrationControl
                , passkeyRegistrationBeginUrl = beginUrl
                , passkeyRegistrationFinishUrl = pathTo FinishPasskeySetupRegistrationAction
                , passkeyRegistrationSuccessRedirect = Just (pathTo NewSessionAction)
                }
         in [hsx|
            <div class="app-page-auth">
                <div class="app-auth-card">
                    <div class="app-auth-body">
                        <h4 class="card-title mb-3 text-center">Set Up New Passkey</h4>
                        <p class="app-muted text-center mb-4">Create a passkey for {targetEmail}. This setup link can only add a passkey and cannot sign you in by itself.</p>
                        {renderPasskeyRegistrationControl registrationControl}
                    </div>
                </div>
            </div>
        |]
