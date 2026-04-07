module Web.View.Users.New where

import Web.View.Prelude

data NewView
    = InviteOnlyView
    | InvitationSignupView { user :: User, invitation :: VenueInvitation }
    | VerificationSentView { email :: Text }

instance View NewView where
    html InviteOnlyView = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Invitation Required</h4>
                    <p class="app-muted mb-4 text-center">
                        New venues are bootstrapped manually. Ask the founder or support team for an invitation link before creating an account.
                    </p>
                    <div class="d-grid gap-3">
                        <a href={NewSessionAction} class="btn btn-primary">Sign In</a>
                    </div>
                </div>
            </div>
        </div>
    |]
    html InvitationSignupView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Accept Invitation</h4>
                    <p class="app-muted mb-4 text-center">
                        You have been invited to join this venue as {invitationRoleLabel invitation.inviteRole}.
                    </p>
                    {renderInvitationForm user invitation}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Already have an account?
                        <a href={NewSessionAction}>Sign in</a>
                    </p>
                </div>
            </div>
        </div>
    |]
    html VerificationSentView { .. } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Verify Your Email</h4>
                    <p class="app-muted mb-4 text-center">
                        We sent a verification link to <strong>{email}</strong>. You need to verify that email before you can sign in.
                    </p>
                    <form method="POST" action={ResendVerificationAction} class="d-grid gap-3">
                        <input type="hidden" name="email" value={email} />
                        <button type="submit" class="btn btn-primary">Resend Verification Email</button>
                        <a href={NewSessionAction} class="btn btn-outline-secondary">Back to Sign In</a>
                    </form>
                </div>
            </div>
        </div>
    |]

renderInvitationForm :: User -> VenueInvitation -> Html
renderInvitationForm user invitation = formForWithoutJavascript user [hsx|
    <input type="hidden" name="invitationId" value={tshow invitation.id} />
    <div class="mb-3">
        <label class="form-label" for="email">Email address</label>
        <input
            id="email"
            type="email"
            class="form-control"
            value={invitation.email}
            readonly="readonly"
        />
    </div>
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

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "venue owner"
        "venue_admin" -> "venue admin"
        "manager"     -> "manager"
        _             -> "worker"
