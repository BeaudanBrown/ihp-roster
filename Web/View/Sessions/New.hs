module Web.View.Sessions.New where
import Web.View.Prelude

data NewView = NewView
    { user                     :: User
    , pendingVerificationEmail :: Maybe Text
    }

instance View NewView where
    html NewView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-4 text-center">Sign In</h4>
                    {renderPendingVerification pendingVerificationEmail}
                    {renderForm user}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Need venue access?
                        <a href={NewUserAction}>Request an invitation</a>
                    </p>
                </div>
            </div>
        </div>
    |]

renderForm :: User -> Html
renderForm user = [hsx|
    <form method="POST" action={CreateSessionAction} data-disable-javascript-submission="true">
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

renderPendingVerification :: Maybe Text -> Html
renderPendingVerification Nothing = mempty
renderPendingVerification (Just email) = [hsx|
    <div class="alert alert-warning mb-4">
        <div class="mb-2">Verify your email before signing in.</div>
        <form method="POST" action={ResendVerificationAction} class="d-flex gap-2 align-items-center">
            <input type="hidden" name="email" value={email} />
            <span class="small text-muted flex-grow-1">{email}</span>
            <button type="submit" class="btn btn-sm btn-outline-primary">Resend email</button>
        </form>
    </div>
|]
