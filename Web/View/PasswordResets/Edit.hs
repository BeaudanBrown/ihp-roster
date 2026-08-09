module Web.View.PasswordResets.Edit where

import Web.View.Prelude

data EditView = EditView
    { targetEmail :: Text
    , rawToken    :: Text
    }

instance View EditView where
    html EditView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Reset Password</h4>
                    <p class="app-muted text-center mb-4">Set a new password for {targetEmail}. This signs the account out on all devices but preserves its passkeys.</p>
                    <form method="POST" action={UpdatePasswordResetAction}>
                        <input type="hidden" name="token" value={rawToken}/>
                        <div class="mb-3">
                            <label class="form-label" for="password-reset-password">New password</label>
                            <input id="password-reset-password"
                                   name="password"
                                   type="password"
                                   class="form-control"
                                   maxlength="256"
                                   autocomplete="new-password"
                                   required="required"/>
                        </div>
                        <div class="mb-3">
                            <label class="form-label" for="password-reset-confirmation">Confirm new password</label>
                            <input id="password-reset-confirmation"
                                   name="passwordConfirmation"
                                   type="password"
                                   class="form-control"
                                   maxlength="256"
                                   autocomplete="new-password"
                                   required="required"/>
                        </div>
                        <div class="d-grid mt-4">
                            <button type="submit" class="btn btn-primary">Reset password</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    |]
