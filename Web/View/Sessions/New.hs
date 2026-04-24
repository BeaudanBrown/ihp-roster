module Web.View.Sessions.New where
import IHP.AuthSupport.View.Sessions.New
import Web.View.Prelude

instance View (NewView User) where
    html NewView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-4 text-center">Sign In</h4>
                    {renderPasskeyLogin}
                    <div class="position-relative my-4">
                        <hr/>
                        <span class="position-absolute top-50 start-50 translate-middle bg-body px-3 app-muted small">or</span>
                    </div>
                    {renderForm user}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Don't have an account?
                        <a href={NewUserAction}>Create one</a>
                    </p>
                </div>
            </div>
        </div>
    |]

renderForm :: User -> Html
renderForm user = [hsx|
    <form method="POST" action={CreateSessionAction}>
        <div class="mb-3">
            <label class="form-label" for="email">Email address</label>
            <input
                id="email"
                name="email"
                value={user.email}
                type="email"
                class="form-control"
                placeholder="you@example.com"
                required="required"
                autofocus="autofocus"
            />
        </div>
        <div class="mb-3">
            <label class="form-label" for="password">Password</label>
            <input
                id="password"
                name="password"
                type="password"
                class="form-control"
                placeholder="••••••••"
                required="required"
            />
        </div>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Sign In</button>
        </div>
    </form>
|]

renderPasskeyLogin :: Html
renderPasskeyLogin = [hsx|
    <div class="js-passkey-login"
         data-begin-url={pathTo BeginPasskeyAuthenticationAction}
         data-finish-url={pathTo FinishPasskeyAuthenticationAction}
         data-status-id="passkey-login-status"
         data-success-redirect={pathTo DashboardAction}>
        <div class="d-grid">
            <button type="button" class="btn btn-outline-primary js-passkey-login-button">Sign in with passkey</button>
        </div>
        <div id="passkey-login-status" class="alert d-none mt-3"></div>
    </div>
|]
