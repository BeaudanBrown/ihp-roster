module Web.View.Passkeys.NewSetup where

import Web.View.Prelude

data NewSetupView = NewSetupView
    { targetEmail :: Text
    , beginUrl    :: Text
    }

instance View NewSetupView where
    html NewSetupView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Set Up New Passkey</h4>
                    <p class="app-muted text-center mb-4">Create a passkey for {targetEmail}. This setup link can only add a passkey and cannot sign you in by itself.</p>
                    <div class="js-passkey-register"
                         data-begin-url={beginUrl}
                         data-finish-url={pathTo FinishPasskeySetupRegistrationAction}
                         data-status-id="passkey-setup-link-status"
                         data-success-redirect={pathTo NewSessionAction}>
                        <div class="mb-3">
                            <label class="form-label" for="passkey-setup-link-name">Passkey name</label>
                            <input id="passkey-setup-link-name" type="text" class="form-control js-passkey-name" maxlength="120" placeholder="e.g. New laptop" autocomplete="off"/>
                            <div class="form-text app-muted">Use a name you will recognize later, such as this device or security key.</div>
                        </div>
                        <div class="d-grid">
                            <button type="button" class="btn btn-primary js-passkey-register-button">Create passkey</button>
                        </div>
                    </div>
                    <div id="passkey-setup-link-status" class="alert d-none mt-3"></div>
                </div>
            </div>
        </div>
    |]
