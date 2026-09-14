{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Invites
    ( renderInvitesSectionFragment
    , renderInvitesSectionFragmentWithSwap
    ) where

import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceActionRoute (..),
                                                            defaultFrontendSurfaceActionRoute,
                                                            renderFrontendSurfaceActionForm,
                                                            renderFrontendSurfaceMount)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.UiRegion (UiRegionTransitionProfile (..))
import Application.Helper.VenueInvitation (venueInvitationEffectiveExpiresAt)
import Web.Admin.FrontendSurface (AdminVenueScopeValue (..),
                                  adminInvitesSurfaceImpl)
import Web.View.Admin.Common
import Web.View.Prelude

renderInvitesSection :: UTCTime -> [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSection now invitations rosterGroupId =
    renderConfigSection
        "admin-invites-section"
        mempty
        (renderInviteCreateForm rosterGroupId)
        [hsx|
            {if null invitations then renderEmptyState "No invites yet." else renderInviteTable now invitations rosterGroupId}
        |]

renderInviteCreateForm :: Id RosterGroup -> Html
renderInviteCreateForm rosterGroupId =
    renderFrontendSurfaceActionForm
        (AdminAction.createVenueInvitationAction fields)
        (inviteCreateRoute rosterGroupId)
        [hsx|
            <div class="row g-2 align-items-end">
                <div class="col-12 col-md-9">
                    <label class="form-label" for="new-invite-email">Email</label>
                    <input id="new-invite-email" class="form-control" type="email" name={surfaceFieldNameFrom @Surface.Email fields} placeholder="new-user@example.com" required="required" />
                </div>
                <div class="col-12 col-md-3">
                    <button class="btn btn-outline-primary w-100" type="submit">Send</button>
                </div>
            </div>
        |]
  where
    fields = AdminAction.createVenueInvitationActionFields ""

inviteCreateRoute :: Id RosterGroup -> FrontendSurfaceActionRoute
inviteCreateRoute rosterGroupId = ((defaultFrontendSurfaceActionRoute (appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)]))
    { actionRouteStandardUrl = Just (appendQueryParams (pathTo CreateVenueInvitationAction) [("rosterGroupId", tshow rosterGroupId)])
    , actionRouteExtraAttrs = [("class", appSurfaceClasses "p-3")]
    })

renderInvitesSectionFragment :: UTCTime -> [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragment =
    renderInvitesSectionFragmentWithSwap Nothing

renderInvitesSectionFragmentWithSwap :: Maybe Text -> UTCTime -> [VenueInvitation] -> Id RosterGroup -> Html
renderInvitesSectionFragmentWithSwap maybeSwapOob now invitations rosterGroupId =
    renderFrontendSurfaceMount (adminInvitesSurfaceImpl AdminVenueScopeValue { adminVenueId = currentAdminVenueScopeId, adminRosterGroupId = Just (unpackId rosterGroupId) }) $
        [hsx|<div {...attributes}>{renderInvitesSection now invitations rosterGroupId}</div>|]
  where
    attributes = [("id", surfaceFragmentTargetId @Surface.AdminInvitesSurface @Surface.AdminInvitesFragment noSurfaceFields)]
        <> maybe [] (\value -> [("hx-swap-oob", value)]) maybeSwapOob
        <> uiRegionTransitionAttrs UiRegionTransitionFade

renderInviteTable :: UTCTime -> [VenueInvitation] -> Id RosterGroup -> Html
renderInviteTable now invitations rosterGroupId = [hsx|
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
                {forEach invitations (renderInviteRow now rosterGroupId)}
            </tbody>
        </table>
    </div>
|]

renderInviteRow :: UTCTime -> Id RosterGroup -> VenueInvitation -> Html
renderInviteRow now rosterGroupId invitation = [hsx|
    <tr id={inviteRowId invitation.id}>
        <td>{invitation.email}</td>
        <td>{renderInvitationStatusBadge now invitation}</td>
        <td>{formatTimestamp (venueInvitationEffectiveExpiresAt invitation)}</td>
        <td class="text-end">{renderInviteRowActions rosterGroupId invitation}</td>
    </tr>
|]

inviteRowId :: Id VenueInvitation -> Text
inviteRowId invitationId = "invite-row-" <> tshow invitationId

renderInvitationStatusBadge :: UTCTime -> VenueInvitation -> Html
renderInvitationStatusBadge now invitation
    | invitationStatusAllowsRenewal invitation.status
        && venueInvitationEffectiveExpiresAt invitation <= now = renderAppStatusBadge AppStatusNeutral "Expired"
    | otherwise = renderInvitationStatusOrDeliveryBadge invitation.status invitation.deliveryStatus

renderInviteRowActions :: Id RosterGroup -> VenueInvitation -> Html
renderInviteRowActions rosterGroupId invitation
    | not (invitationStatusAllowsRenewal invitation.status) = mempty
    | otherwise = [hsx|
        <div class="d-flex flex-column flex-lg-row justify-content-end gap-2">
            {renderRenewVenueInvitationForm rosterGroupId invitation}
            {renderRevokeVenueInvitationForm rosterGroupId invitation}
        </div>
        |]

renderRenewVenueInvitationForm :: Id RosterGroup -> VenueInvitation -> Html
renderRenewVenueInvitationForm rosterGroupId invitation =
    renderFrontendSurfaceActionForm (AdminAction.renewVenueInvitationAction fields) route [hsx|
        <div class="input-group input-group-sm">
            <input class="form-control" type="email" name={surfaceFieldNameFrom @Surface.Email fields} value={invitation.email} required="required" aria-label="Renewal email" />
            <button class="btn btn-outline-primary" type="submit">Renew</button>
        </div>
    |]
    where
        fields = AdminAction.renewVenueInvitationActionFields (Just invitation.email)
        renewUrl = appendQueryParams (pathTo (RenewVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]
        route = ((defaultFrontendSurfaceActionRoute (renewUrl))
            { actionRouteStandardUrl = Just renewUrl
            , actionRouteExtraAttrs = [("class", "d-inline")]
            })

renderRevokeVenueInvitationForm :: Id RosterGroup -> VenueInvitation -> Html
renderRevokeVenueInvitationForm rosterGroupId invitation =
    renderFrontendSurfaceActionForm (AdminAction.revokeVenueInvitationAction AdminAction.revokeVenueInvitationActionFields) route [hsx|
        <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
    |]
    where
        revokeUrl = appendQueryParams (pathTo (RevokeVenueInvitationAction invitation.id)) [("rosterGroupId", tshow rosterGroupId)]
        route = ((defaultFrontendSurfaceActionRoute (revokeUrl))
            { actionRouteStandardUrl = Just revokeUrl
            , actionRouteExtraAttrs = [("class", "d-inline")]
            })
