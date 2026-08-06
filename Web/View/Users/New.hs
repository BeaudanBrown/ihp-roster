module Web.View.Users.New where

import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue (..))
import qualified Application.Helper.FrontendContract.Surface.Profile.Action as ProfileAction
import Application.Helper.View.VenueBootstrap (renderVenueBootstrapFields)
import Application.VenueRole (venueRoleMailLabel)
import Web.View.Prelude
import Web.View.StaffProfileForm (StaffProfileDetailsSurfaceValues (..),
                                  renderPersonalProfileFields,
                                  staffProfileDetailsSurfaceValues)
import Web.View.StaffProfileSections

data NewView
    = InviteOnlyView
    | InvitationSignupView { user :: User, venueInvitation :: VenueInvitation, staff :: Staff }
    | VenueOnboardingSignupView
        { user                       :: User
        , onboardingInvitation       :: VenueOnboardingInvitation
        , venue                      :: Venue
        , staff                      :: Staff
        , venueRosterWeekStartsOn    :: Int
        , venueRosterEndTimesEnabled :: Bool
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
                        {invitationSignupIntro venueInvitation}
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
    html VenueOnboardingSignupView { user, onboardingInvitation, venue, staff, venueRosterWeekStartsOn, venueRosterEndTimesEnabled } = [hsx|
        <div class="app-page-auth">
            <div class="app-auth-card">
                <div class="app-auth-body">
                    <h4 class="card-title mb-3 text-center">Create Your Venue</h4>
                    <p class="app-muted mb-4 text-center">
                        Create your account and configure your venue before it is created.
                    </p>
                    {renderVenueOnboardingForm user onboardingInvitation venue staff venueRosterWeekStartsOn venueRosterEndTimesEnabled}
                </div>
            </div>
        </div>
    |]

invitationSignupIntro :: VenueInvitation -> Text
invitationSignupIntro invitation
    | isJust invitation.staffId = "You have been invited to claim an existing trial staff profile. Review the prefilled details, update anything that has changed, and create your account."
    | otherwise = "You have been invited to join this venue as " <> venueRoleMailLabel invitation.inviteRole <> "."

renderInvitationForm :: User -> VenueInvitation -> Staff -> Html
renderInvitationForm user invitation staff =
    renderInvitedProfileDetailsForm
        NewAccountProfileFormConfig
            { newAccountProfileFormId = "new-invited-account-form"
            , newAccountProfileFormAction = pathTo CreateUserAction
            , newAccountProfileFormHiddenInputs = [hsx|<input type="hidden" name="invitationId" value={tshow invitation.id}/>|]
            , newAccountProfileFormBeforeAccountFields = mempty
            , newAccountProfileFormSubmitLabel = "Create Account"
            }
        user
        staff
        invitation.email

renderVenueOnboardingForm :: User -> VenueOnboardingInvitation -> Venue -> Staff -> Int -> Bool -> Html
renderVenueOnboardingForm user invitation venue staff venueRosterWeekStartsOn venueRosterEndTimesEnabled =
    renderInvitedProfileDetailsForm
        NewAccountProfileFormConfig
            { newAccountProfileFormId = "new-venue-owner-account-form"
            , newAccountProfileFormAction = pathTo CreateVenueOnboardingUserAction
            , newAccountProfileFormHiddenInputs = [hsx|<input type="hidden" name="invitationId" value={tshow invitation.id}/>|]
            , newAccountProfileFormBeforeAccountFields = [hsx|
                <section class="mb-4">
                    <h5 class="mb-3">Venue setup</h5>
                    <div class="row g-3">
                        {renderVenueBootstrapFields venue venueRosterWeekStartsOn}
                        {renderVenueDefaultToggles venueRosterEndTimesEnabled}
                    </div>
                </section>
                <hr/>
            |]
            , newAccountProfileFormSubmitLabel = "Create Account And Venue"
            }
        user
        staff
        invitation.email

data NewAccountProfileFormConfig = NewAccountProfileFormConfig
    { newAccountProfileFormId                  :: Text
    , newAccountProfileFormAction              :: Text
    , newAccountProfileFormHiddenInputs        :: Html
    , newAccountProfileFormBeforeAccountFields :: Html
    , newAccountProfileFormSubmitLabel         :: Text
    }

renderInvitedProfileDetailsForm :: NewAccountProfileFormConfig -> User -> Staff -> Text -> Html
renderInvitedProfileDetailsForm NewAccountProfileFormConfig { .. } user staff email =
    renderStaffProfileDetailsForm
        StaffProfileDetailsFormConfig
            { staffProfileDetailsFormId = newAccountProfileFormId
            , staffProfileDetailsFormAction = newAccountProfileFormAction
            , staffProfileDetailsFormClass = ""
            , staffProfileDetailsFormRequestMode = Nothing
            , staffProfileDetailsSurfaceFields = fields
            , staffProfileDetailsFormAttributes = []
            , staffProfileDetailsFormHiddenInputs = newAccountProfileFormHiddenInputs
            , staffProfileDetailsFormBeforeFields = [hsx|
                {newAccountProfileFormBeforeAccountFields}
                <section class="mb-4">
                    <h5 class="mb-3">Account Details</h5>
                    {renderAccountPasswordFields user}
                </section>
                <hr/>
            |]
            , staffProfileDetailsFormFieldsHeading = Just "Confirm your staff details"
            , staffProfileDetailsFormEmailField = renderPersonalProfileFields
            , staffProfileDetailsFormAfterFields = mempty
            , staffProfileDetailsFormManagement = Nothing
            , staffProfileDetailsFormManagementBody = \_ _ -> mempty
            , staffProfileDetailsFormSubmitLabel = newAccountProfileFormSubmitLabel
            }
        staff
        (Just email)
  where
    values = staffProfileDetailsSurfaceValues StaffProfileDetailsSection staff Nothing
    fields =
        ProfileAction.updateProfileDetailsActionFields
            values.profileDetailsFirstName
            values.profileDetailsLastName
            values.profileDetailsPreferredName
            values.profileDetailsPhone
            values.profileDetailsIdealShiftsPerWeek
            values.profileDetailsEmergencyContactName
            values.profileDetailsEmergencyContactPhone
            values.profileDetailsSection
            values.profileDetailsVenueRole
            values.profileDetailsEmploymentBasis
            values.profileDetailsPayRateSelection
            values.profileDetailsRosterGroupIds

renderAccountPasswordFields :: User -> Html
renderAccountPasswordFields user = [hsx|
    <div class="row g-3 mb-3">
        <div class="col-12 col-lg-6">
            <label class="form-label" for="passwordHash">Password</label>
            <input
                id="passwordHash"
                name="passwordHash"
                type="password"
                class={classes ["form-control", ("is-invalid", isJust (getValidationFailure #passwordHash user))]}
                placeholder="••••••••"
                required="required"
                value={user.passwordHash}
            />
            {renderPasswordValidation user}
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
|]

renderPasswordValidation :: User -> Html
renderPasswordValidation user =
    case getValidationFailure #passwordHash user of
        Just message -> [hsx|<div class="invalid-feedback">{message}</div>|]
        Nothing      -> mempty

renderVenueDefaultToggles :: Bool -> Html
renderVenueDefaultToggles rosterEndTimesEnabled = [hsx|
    <div class="col-12">
        <div class={appSurfaceClasses "p-3"}>
            <div class="form-check form-switch mb-0">
                <input
                    id="venue-roster-end-times-enabled"
                    class="form-check-input"
                    type="checkbox"
                    name="rosterEndTimesEnabled"
                    value="true"
                    checked={rosterEndTimesEnabled}
                />
                <label class="form-check-label fw-semibold" for="venue-roster-end-times-enabled">Show shift end times in roster</label>
                <p class="small app-muted mb-0">Shift end times are always collected; this controls whether they appear in the roster.</p>
            </div>
        </div>
    </div>
|]
