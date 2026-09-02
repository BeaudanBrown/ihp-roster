module Web.View.PasswordResets.New where

import Web.View.Prelude

data NewView = NewView

instance View NewView where
    html NewView = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Forgot password</h4>
                    <p class="app-muted text-center mb-4">Enter your email address and we’ll send the appropriate account recovery link if the account is eligible.</p>
                    <form method="POST" action={CreatePasswordResetRequestAction}>
                        <div class="mb-3">
                            <label class="form-label" for="password-reset-email">Email address</label>
                            <input
                                id="password-reset-email"
                                name="email"
                                type="email"
                                class="form-control"
                                maxlength="254"
                                autocomplete="email"
                                required="required"
                            />
                        </div>
                        <div class="d-grid mt-4">
                            <button type="submit" class="btn btn-primary">Send recovery email</button>
                        </div>
                    </form>
                    <p class="text-center mt-4 mb-0"><a href={NewSessionAction}>Back to sign in</a></p>
                </div>
            </div>
        </div>
    |]
