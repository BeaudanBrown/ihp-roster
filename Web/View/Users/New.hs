module Web.View.Users.New where
import Web.View.Prelude

newtype NewView = NewView { user :: User }

instance View NewView where
    html NewView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-4 text-center">Create Account</h4>
                    {renderForm user}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Already have an account?
                        <a href={NewSessionAction}>Sign in</a>
                    </p>
                </div>
            </div>
        </div>
    |]

renderForm :: User -> Html
renderForm user = formFor user [hsx|
    {(textField #email) { fieldLabel = "Email address", placeholder = "you@example.com", autofocus = True }}
    {(passwordField #passwordHash) { fieldLabel = "Password", placeholder = "••••••••", required = True }}
    {(passwordField #passwordHash)
        { fieldLabel = "Confirm Password"
        , placeholder = "••••••••"
        , fieldName = "passwordConfirmation"
        , validatorResult = Nothing
        , required = True
        }}
    <div class="d-grid mt-4">
        <button type="submit" class="btn btn-primary">Create Account</button>
    </div>
|]
