module Web.View.Admin.Invites
    ( adminInvitesLiveSurface
    , renderInvitesSectionFragment
    ) where

import Application.Helper.LiveSurface (LiveSurfaceConfig (..),
                                       liveSurfaceConfigJson, mkLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveFragmentProtection (..),
                                      LiveFragmentRef (..),
                                      LiveUpdateScope (..), mkLiveFragmentRef)
import Web.View.Admin.Common
import Web.View.Prelude

renderInvitesSection :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSection invitations rosterGroupId =
    renderConfigSection
        "invites"
        "Invites"
        "Queue an invitation immediately, track delivery status, revoke pending invites, and see when they are accepted."
        (renderInviteSummary invitations)
        (renderInviteCreateForm rosterGroupId)
        [hsx|
            {if null invitations then renderEmptyState "No invites yet." else renderInviteTable invitations rosterGroupId}
        |]

renderInviteSummary :: [VenueInvitation] -> Html
renderInviteSummary invitations = [hsx|
    <p class="small app-muted mb-3">
        {tshow activePendingCount} active pending {inviteLabel}; {tshow sentCount} sent and {tshow acceptedCount} accepted.
    </p>
|]
    where
        activePendingCount = length (filter invitationIsActivePending invitations)
        sentCount = length (filter invitationWasSent invitations)
        acceptedCount = length (filter invitationWasAccepted invitations)
        inviteLabel :: Text
        inviteLabel =
            if activePendingCount == 1
                then "invite"
                else "invites"

renderInviteCreateForm :: Id RosterGroup -> Html
renderInviteCreateForm rosterGroupId = [hsx|
    <form
        method="POST"
        action={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        class={appSurfaceClasses "p-3"}
        data-disable-javascript-submission="true"
        hx-post={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        hx-target="#admin-invites-fragment"
        hx-swap="outerHTML"
    >
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-9">
                <label class="form-label" for="new-invite-email">Email</label>
                <input id="new-invite-email" class="form-control" type="email" name="email" placeholder="new-user@example.com" required="required" />
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-primary w-100" type="submit">Queue Invite Email</button>
            </div>
        </div>
    </form>
|]

renderInvitesSectionFragment :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragment invitations rosterGroupId = [hsx|
    <div id="admin-invites-fragment">
        {renderInvitesSection invitations rosterGroupId}
    </div>
|]

adminInvitesLiveSurface :: (?context :: ControllerContext) => Id RosterGroup -> LiveUpdateScope -> LiveSurfaceConfig
adminInvitesLiveSurface rosterGroupId scope =
    (mkLiveSurface
        "admin-invites"
        scope
        [ mkLiveFragmentRef
            AdminInvitesFragment
            "admin-invites-fragment"
            (appendQueryParams (pathTo ShowAdminInvitesFragmentAction) [("rosterGroupId", tshow rosterGroupId)])
        ])
        { decorateRequestsWithin = ["#admin-invites-fragment"] }

renderInviteTable :: [VenueInvitation] -> Id RosterGroup -> Html
renderInviteTable invitations rosterGroupId = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle mb-0">
            <thead>
                <tr>
                    <th>Email</th>
                    <th>Role</th>
                    <th>Status</th>
                    <th>Expires</th>
                    <th class="text-end">Actions</th>
                </tr>
            </thead>
            <tbody>
                {forEach invitations (renderInviteRow rosterGroupId)}
            </tbody>
        </table>
    </div>
|]

renderInviteRow :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRow rosterGroupId invitation = [hsx|
    <tr id={inviteRowId invitation.id}>
        <td>{invitation.email}</td>
        <td>{invitationRoleLabel invitation.inviteRole}</td>
        <td>{renderInvitationStatusBadge invitation}</td>
        <td>{formatTimestamp (fromMaybe invitation.createdAt invitation.expiresAt)}</td>
        <td class="text-end">{renderInviteRowActions rosterGroupId invitation}</td>
    </tr>
|]

inviteRowId :: Id VenueInvitation -> Text
inviteRowId invitationId = "invite-row-" <> tshow invitationId

invitationIsActivePending :: VenueInvitation -> Bool
invitationIsActivePending invitation =
    inputValue invitation.status == "pending" && not (invitationWasAccepted invitation)

invitationWasAccepted :: VenueInvitation -> Bool
invitationWasAccepted invitation = inputValue invitation.status == "accepted"

invitationWasSent :: VenueInvitation -> Bool
invitationWasSent invitation = inputValue invitation.deliveryStatus == "sent"

renderInvitationStatusBadge :: VenueInvitation -> Html
renderInvitationStatusBadge invitation =
    renderInvitationStatusOrDeliveryBadge (inputValue invitation.status) (inputValue invitation.deliveryStatus)

renderInviteRowActions :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRowActions rosterGroupId invitation
    | inputValue invitation.status /= "pending" = mempty
    | otherwise = [hsx|
        <form
            method="POST"
            action={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            class="d-inline"
            data-disable-javascript-submission="true"
            hx-post={appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]}
            hx-target="#admin-invites-fragment"
            hx-swap="outerHTML"
        >
            <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
        </form>
    |]

invitationRoleLabel :: InputValue value => value -> Text
invitationRoleLabel value =
    case inputValue value of
        "venue_owner" -> "Venue Owner"
        "venue_admin" -> "Venue Admin"
        "manager"     -> "Manager"
        _             -> "Worker"
