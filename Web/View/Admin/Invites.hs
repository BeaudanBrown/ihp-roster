{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Invites
    ( renderInvitesSectionFragment
    , renderInvitesSectionFragmentWithSwap
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.FrontendSurface.Runtime (renderFrontendSurfaceMount)
import Application.Helper.UiRegion (UiRegionTransitionProfile (..))
import qualified Text.Blaze.Html as Blaze
import Text.Blaze.Html ((!))
import qualified Text.Blaze.Html5 as Html5
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminInvitesSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderInvitesSection :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSection invitations rosterGroupId =
    renderConfigSection
        "admin-invites-section"
        mempty
        (renderInviteCreateForm rosterGroupId)
        [hsx|
            {if null invitations then renderEmptyState "No invites yet." else renderInviteTable invitations rosterGroupId}
        |]

renderInviteCreateForm :: Id RosterGroup -> Html
renderInviteCreateForm rosterGroupId = [hsx|
    <form
        method="POST"
        action={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        class={appSurfaceClasses "p-3"}
        data-disable-javascript-submission="true"
        hx-post={appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]}
        hx-target="#admin-invites-fragment"
        hx-swap="none"
    >
        <div class="row g-2 align-items-end">
            <div class="col-12 col-md-9">
                <label class="form-label" for="new-invite-email">Email</label>
                <input id="new-invite-email" class="form-control" type="email" name="email" placeholder="new-user@example.com" required="required" />
            </div>
            <div class="col-12 col-md-3">
                <button class="btn btn-outline-primary w-100" type="submit">Send</button>
            </div>
        </div>
    </form>
|]

renderInvitesSectionFragment :: [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragment =
    renderInvitesSectionFragmentWithSwap Nothing

renderInvitesSectionFragmentWithSwap :: Maybe Text -> [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragmentWithSwap maybeSwapOob invitations rosterGroupId =
    renderFrontendSurfaceMount (adminInvitesSurfaceImpl AdminVenueScopeValue { adminVenueId = currentVenueScopeId, adminRosterGroupId = Just (unpackId rosterGroupId) }) $
        Html5.div
            ! attr "id" "admin-invites-fragment"
            ! maybeAttr "hx-swap-oob" maybeSwapOob
            ! uiRegionTransitionAttrs UiRegionTransitionFade
            $ renderInvitesSection invitations rosterGroupId

attr :: Text -> Text -> Blaze.Attribute
attr name value =
    Blaze.customAttribute (Blaze.textTag name) (Blaze.toValue value)

maybeAttr :: Text -> Maybe Text -> Blaze.Attribute
maybeAttr _ Nothing         = mempty
maybeAttr name (Just value) = attr name value

currentVenueScopeId :: (?context :: ControllerContext) => UUID
currentVenueScopeId =
    case currentVenueOrNothing of
        Just venue -> unpackId venue.id
        Nothing -> error "Admin invites live surface requires a current venue"

renderInviteTable :: [VenueInvitation] -> Id RosterGroup -> Html
renderInviteTable invitations rosterGroupId = [hsx|
    <div class="table-responsive">
        <table class="table table-striped align-middle mb-0">
            <thead>
                <tr>
                    <th>Email</th>
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
        <td>{renderInvitationStatusBadge invitation}</td>
        <td>{formatTimestamp (fromMaybe invitation.createdAt invitation.expiresAt)}</td>
        <td class="text-end">{renderInviteRowActions rosterGroupId invitation}</td>
    </tr>
|]

inviteRowId :: Id VenueInvitation -> Text
inviteRowId invitationId = "invite-row-" <> tshow invitationId

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
            hx-swap="none"
        >
            <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
        </form>
    |]
