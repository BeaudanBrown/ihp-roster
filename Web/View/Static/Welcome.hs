module Web.View.Static.Welcome where
import Web.View.Prelude

data WelcomeView = WelcomeView

instance View WelcomeView where
    html WelcomeView = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card app-auth-card-wide">
                <div class="app-auth-body text-center">
                    <h1 class="display-5 fw-bold mb-2">Welcome</h1>
                    <p class="app-muted mb-5">Sign in with an invited account. New venue access is bootstrapped manually.</p>
                    <div class="d-grid gap-3">
                        <div class="js-passkey-first-login"
                             data-begin-url={pathTo BeginPasskeyAuthenticationAction}
                             data-finish-url={pathTo FinishPasskeyAuthenticationAction}
                             data-fallback-url={pathTo NewSessionAction}
                             data-success-redirect={RosterWeeksAction}>
                            <a href={NewSessionAction} class="btn btn-primary btn-lg js-passkey-first-login-button">Sign In</a>
                        </div>
                        <a href={NewUserAction} class="btn btn-outline-secondary btn-lg">Request Access</a>
                    </div>
                </div>
            </div>
        </div>
    |]
