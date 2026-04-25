module Web.View.Static.Welcome where
import Web.View.Prelude

data WelcomeView = WelcomeView

instance View WelcomeView where
    html WelcomeView = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card app-auth-card-wide">
                <div class="app-auth-body text-center">
                    <h1 class="display-5 fw-bold mb-2">Bepis</h1>
                    <div class="d-grid">
                        <div class="js-passkey-first-login"
                             data-begin-url={pathTo BeginPasskeyAuthenticationAction}
                             data-finish-url={pathTo FinishPasskeyAuthenticationAction}
                             data-fallback-url={pathTo NewSessionAction}
                             data-success-redirect={RosterWeeksAction}>
                            <a href={NewSessionAction} class="btn btn-primary btn-lg w-100 js-passkey-first-login-button">Sign In</a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    |]
