module Web.View.Users.New where

import Application.Helper.View.VenueBootstrap (renderVenueBootstrapFields)
import Web.View.Prelude

data NewView
    = InviteOnlyView
    | InvitationSignupView { user :: User, venueInvitation :: VenueInvitation }
    | VenueOnboardingSignupView
        { user :: User
        , onboardingInvitation :: VenueOnboardingInvitation
        , venue :: Venue
        , venueTimezone :: Text
        , venueRosterWeekStartsOn :: Int
        }

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
    html InvitationSignupView { user, venueInvitation } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Accept Invitation</h4>
                    <p class="app-muted mb-4 text-center">
                        You have been invited to join this venue as {invitationRoleLabel venueInvitation.inviteRole}.
                    </p>
                    {renderInvitationForm user venueInvitation}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Already have an account?
                        <a href={NewSessionAction}>Sign in</a>
                    </p>
                </div>
            </div>
        </div>
    |]
    html VenueOnboardingSignupView { user, onboardingInvitation, venue, venueTimezone, venueRosterWeekStartsOn } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Create Your Venue</h4>
                    <p class="app-muted mb-4 text-center">
                        Create your account and configure your venue before it is created.
                    </p>
                    {renderVenueOnboardingForm user onboardingInvitation venue venueTimezone venueRosterWeekStartsOn}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Already have an account?
                        <a href={NewSessionAction}>Sign in</a>
                    </p>
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

renderVenueOnboardingForm :: User -> VenueOnboardingInvitation -> Venue -> Text -> Int -> Html
renderVenueOnboardingForm user invitation venue venueTimezone venueRosterWeekStartsOn = [hsx|
    <form method="POST" action={CreateVenueOnboardingUserAction} data-disable-javascript-submission="true">
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
        <div class="mb-3">
            <label class="form-label" for="passwordHash">Password</label>
            <input
                id="passwordHash"
                name="passwordHash"
                type="password"
                class="form-control"
                placeholder="••••••••"
                required="required"
                value={user.passwordHash}
            />
        </div>
        <div class="mb-3">
            <label class="form-label" for="passwordConfirmation">Confirm Password</label>
            <input
                id="passwordConfirmation"
                name="passwordConfirmation"
                type="password"
                class="form-control"
                placeholder="••••••••"
                required="required"
            />
        </div>
        <div class="row g-3">
            {renderVenueBootstrapFields venue venueTimezone venueRosterWeekStartsOn}
        </div>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Create Account And Venue</button>
        </div>
    </form>
|]

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "venue owner"
        "venue_admin" -> "venue admin"
        "manager"     -> "manager"
        _             -> "worker"
