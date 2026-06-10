module Web.View.Users.New where

import Application.Helper.View.VenueBootstrap (renderVenueBootstrapFields)
import Web.View.Prelude
import Web.View.StaffProfileForm (renderPersonalProfileFieldsWithEmailId)

data NewView
    = InviteOnlyView
    | InvitationSignupView { user :: User, venueInvitation :: VenueInvitation, staff :: Staff }
    | VenueOnboardingSignupView
        { user                    :: User
        , onboardingInvitation    :: VenueOnboardingInvitation
        , venue                   :: Venue
        , staff                   :: Staff
        , venueRosterWeekStartsOn           :: Int
        , venueRosterEndTimesEnabled        :: Bool
        , venueAutoTimesheetCreationEnabled :: Bool
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
    html InvitationSignupView { user, venueInvitation, staff } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Accept Invitation</h4>
                    <p class="app-muted mb-4 text-center">
                        You have been invited to join this venue as {invitationRoleLabel venueInvitation.inviteRole}.
                    </p>
                    {renderInvitationForm user venueInvitation staff}
                    <hr/>
                    <p class="text-center mb-0 app-muted small">
                        Already have an account?
                        <a href={NewSessionAction}>Sign in</a>
                    </p>
                </div>
            </div>
        </div>
    |]
    html VenueOnboardingSignupView { user, onboardingInvitation, venue, staff, venueRosterWeekStartsOn, venueRosterEndTimesEnabled, venueAutoTimesheetCreationEnabled } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Create Your Venue</h4>
                    <p class="app-muted mb-4 text-center">
                        Create your account and configure your venue before it is created.
                    </p>
                    {renderVenueOnboardingForm user onboardingInvitation venue staff venueRosterWeekStartsOn venueRosterEndTimesEnabled venueAutoTimesheetCreationEnabled}
                </div>
            </div>
        </div>
    |]

renderInvitationForm :: User -> VenueInvitation -> Staff -> Html
renderInvitationForm user invitation staff = formForWithoutJavascript user [hsx|
    <input type="hidden" name="invitationId" value={tshow invitation.id} />
    <div class="mb-3">
        <label class="form-label" for="invite-email">Email address</label>
        <input
            id="invite-email"
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
    <hr/>
    <h5 class="mb-3">Confirm your staff details</h5>
    {renderPersonalProfileFieldsWithEmailId "staff-email" staff (Just invitation.email)}
    <div class="d-grid mt-4">
        <button type="submit" class="btn btn-primary">Create Account</button>
    </div>
|]

renderVenueOnboardingForm :: User -> VenueOnboardingInvitation -> Venue -> Staff -> Int -> Bool -> Bool -> Html
renderVenueOnboardingForm user invitation venue staff venueRosterWeekStartsOn venueRosterEndTimesEnabled venueAutoTimesheetCreationEnabled = [hsx|
    <form method="POST" action={CreateVenueOnboardingUserAction} data-disable-javascript-submission="true">
        <input type="hidden" name="invitationId" value={tshow invitation.id} />
        <section class="mb-4">
            <h5 class="mb-3">Venue setup</h5>
            <div class="row g-3">
                {renderVenueBootstrapFields venue venueRosterWeekStartsOn}
                {renderVenueDefaultToggles venueRosterEndTimesEnabled venueAutoTimesheetCreationEnabled}
            </div>
        </section>
        <hr/>
        <section>
            <h5 class="mb-3">Account Details</h5>
            <div class="row g-3 mb-3">
                <div class="col-12 col-lg-6">
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
                <div class="col-12 col-lg-6">
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
            </div>
            {renderPersonalProfileFieldsWithEmailId "staff-email" staff (Just invitation.email)}
        </section>
        <div class="d-grid mt-4">
            <button type="submit" class="btn btn-primary">Create Account And Venue</button>
        </div>
    </form>
|]

renderVenueDefaultToggles :: Bool -> Bool -> Html
renderVenueDefaultToggles rosterEndTimesEnabled autoTimesheetCreationEnabled = [hsx|
    <div class="col-12">
        <div class={appSurfaceClasses "p-3"}>
            <div class="form-check form-switch mb-3">
                <input
                    id="venue-roster-end-times-enabled"
                    class="form-check-input"
                    type="checkbox"
                    name="rosterEndTimesEnabled"
                    value="true"
                    checked={rosterEndTimesEnabled}
                />
                <label class="form-check-label fw-semibold" for="venue-roster-end-times-enabled">Roster end times</label>
                <p class="small app-muted mb-0">Require staffed shifts to have start and end times before going live.</p>
            </div>
            <div class="form-check form-switch mb-0">
                <input
                    id="venue-auto-timesheet-creation-enabled"
                    class="form-check-input"
                    type="checkbox"
                    name="autoTimesheetCreationEnabled"
                    value="true"
                    checked={autoTimesheetCreationEnabled}
                />
                <label class="form-check-label fw-semibold" for="venue-auto-timesheet-creation-enabled">Auto-create pending timesheets</label>
                <p class="small app-muted mb-0">When a live rostered shift ends, create a pending timesheet after a 2-hour grace period.</p>
            </div>
        </div>
    </div>
|]

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "venue owner"
        "venue_admin" -> "venue admin"
        "manager"     -> "manager"
        _             -> "worker"
