module Web.View.Support.Index where

import Application.Helper.Controller (currentVenueOrNothing)
import Web.View.Prelude

data IndexView = IndexView
    { venues       :: [Venue]
    , venue        :: Venue
    , onboardingInvitation :: VenueOnboardingInvitation
    , onboardingInvitations :: [VenueOnboardingInvitation]
    , createdVenue :: Maybe Venue
    }

instance View IndexView where
    html IndexView { .. } =
        let switchVenuePanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Nothing
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = ""
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <div class="border rounded p-3 bg-light-subtle mb-4">
                            <div class="small text-uppercase app-muted mb-1">Current support venue</div>
                            <div class="fw-semibold">
                                {maybe "No active venue selected" (.name) currentVenueOrNothing}
                            </div>
                        </div>
                        <form method="POST" action={SwitchSupportVenueAction} class="row g-3 align-items-end" data-disable-javascript-submission="true">
                            <div class="col-12 col-lg-9">
                                <label class="form-label" for="support-venue-id">Active venue</label>
                                <select id="support-venue-id" class="form-select" name="venueId">
                                    {forEach venues renderVenueOption}
                                </select>
                            </div>
                            <div class="col-12 col-lg-3">
                                <button class="btn btn-primary w-100" type="submit">Switch Venue</button>
                            </div>
                        </form>
                    |]
                    }
            createVenuePanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Just "Create Venue"
                    , appPanelDescription = Nothing
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = ""
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <form method="POST" action={CreateSupportVenueAction} class="row g-3" data-disable-javascript-submission="true">
                            <div class="col-12">
                                <label class="form-label" for="support-create-venue-name">Venue name</label>
                                <input
                                    id="support-create-venue-name"
                                    class={classes [("form-control", True), ("is-invalid", hasVenueErrorFor venue "name")]}
                                    type="text"
                                    name="name"
                                    value={venue.name}
                                    required="required"
                                />
                                {renderVenueError venue "name"}
                            </div>
                            <div class="col-12 col-lg-6 d-flex align-items-end">
                                <button class="btn btn-primary w-100" type="submit">Create Venue</button>
                            </div>
                        </form>
                    |]
                    }
            inviteVenueOwnerPanel =
                renderAppPanel AppPanelConfig
                    { appPanelTitle = Just "Invite Venue Owner"
                    , appPanelDescription = Just "Send a one-time onboarding link so the owner can create their account and configure their venue before it exists."
                    , appPanelHasActions = False
                    , appPanelActions = mempty
                    , appPanelHasCustomHeader = False
                    , appPanelCustomHeader = mempty
                    , appPanelClass = ""
                    , appPanelBodyClass = ""
                    , appPanelBody = [hsx|
                        <form method="POST" action={CreateSupportVenueOnboardingInvitationAction} class="row g-3" data-disable-javascript-submission="true">
                            <div class="col-12 col-lg-7">
                                <label class="form-label" for="support-create-onboarding-email">Owner email</label>
                                <input
                                    id="support-create-onboarding-email"
                                    class={classes [("form-control", True), ("is-invalid", hasOnboardingInvitationErrorFor onboardingInvitation "email")]}
                                    type="email"
                                    name="email"
                                    value={onboardingInvitation.email}
                                    required="required"
                                />
                                {renderOnboardingInvitationError onboardingInvitation "email"}
                            </div>
                            <div class="col-12 col-lg-5 d-flex align-items-end">
                                <button class="btn btn-primary w-100" type="submit">Send Owner Invite</button>
                            </div>
                        </form>
                        {renderVenueOnboardingInvitationList onboardingInvitations}
                    |]
                    }
         in renderAppPage (AppPageConfig
            { appPageTitle = "Support"
            , appPageDescription = Nothing
            , appPageActions = mempty
            , appPageWidthClass = ""
            , appPageBody = [hsx|
                {renderCreatedVenueBanner createdVenue}
                <div class="app-page-stack">
                    {switchVenuePanel}
                    {inviteVenueOwnerPanel}
                    {createVenuePanel}
                </div>
            |]
            })

renderVenueOption :: Venue -> Html
renderVenueOption venue = [hsx|
    <option value={venue.id} selected={Just venue.id == fmap (.id) currentVenueOrNothing}>
        {venue.name}
    </option>
|]

renderCreatedVenueBanner :: Maybe Venue -> Html
renderCreatedVenueBanner maybeVenue =
    case maybeVenue of
        Nothing -> mempty
        Just venue -> [hsx|
            <div class="alert alert-success d-flex flex-column flex-lg-row justify-content-between align-items-lg-center gap-3" role="alert">
                <div>
                    <div class="fw-semibold">Venue ready for founder setup</div>
                    <div>{venue.name} was created with minimum Bepis roster defaults. You can switch into it now and invite users later.</div>
                </div>
                <form method="POST" action={SwitchSupportVenueAction} class="m-0">
                    <input type="hidden" name="venueId" value={tshow venue.id} />
                    <input type="hidden" name="next" value={pathTo SupportAction} />
                    <button class="btn btn-success" type="submit">Switch To This Venue</button>
                </form>
            </div>
        |]

renderVenueError :: Venue -> Text -> Html
renderVenueError venue fieldName =
    case lookup fieldName venue.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasVenueErrorFor :: Venue -> Text -> Bool
hasVenueErrorFor venue fieldName = isJust (lookup fieldName venue.meta.annotations)

renderOnboardingInvitationError :: VenueOnboardingInvitation -> Text -> Html
renderOnboardingInvitationError invitation fieldName =
    case lookup fieldName invitation.meta.annotations of
        Just (TextViolation messageText) -> [hsx|<div class="invalid-feedback d-block">{messageText}</div>|]
        Just (HtmlViolation messageHtml) -> [hsx|<div class="invalid-feedback d-block">{messageHtml}</div>|]
        Nothing -> mempty

hasOnboardingInvitationErrorFor :: VenueOnboardingInvitation -> Text -> Bool
hasOnboardingInvitationErrorFor invitation fieldName = isJust (lookup fieldName invitation.meta.annotations)

renderVenueOnboardingInvitationList :: [VenueOnboardingInvitation] -> Html
renderVenueOnboardingInvitationList invitations =
    case invitations of
        [] -> [hsx|<p class="app-muted small mb-0 mt-4">No venue owner onboarding invites yet.</p>|]
        _ -> [hsx|
            <div class="mt-4">
                <div class="small text-uppercase app-muted mb-2">Recent owner invites</div>
                <div class="table-responsive">
                    <table class="table table-sm align-middle mb-0">
                        <thead>
                            <tr>
                                <th scope="col">Email</th>
                                <th scope="col">Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            {forEach invitations renderVenueOnboardingInvitationRow}
                        </tbody>
                    </table>
                </div>
            </div>
        |]

renderVenueOnboardingInvitationRow :: VenueOnboardingInvitation -> Html
renderVenueOnboardingInvitationRow invitation = [hsx|
    <tr>
        <td>{invitation.email}</td>
        <td>{inputValue invitation.status}</td>
    </tr>
|]
