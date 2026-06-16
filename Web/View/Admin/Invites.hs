{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Invites
    ( AdminInvitesLiveFragment (..)
    , AdminInvitesSurfaceKey (..)
    , adminInvitesFragment
    , adminInvitesLiveSurface
    , adminInvitesLiveSurfaceDefinition
    , adminInvitesLiveSurfaceDefinitionForVenue
    , renderInvitesSectionFragment
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface (LiveScopeAuthorizationRequirement (..),
                                       LiveSurfaceConfig (..),
                                       SurfaceFragmentRef, SurfaceScope (..),
                                       TypedLiveSurfaceDefinition (..),
                                       liveFragmentDependsOn,
                                       liveSurfaceAuthorizationByRequirement,
                                       liveSurfaceConfigJson,
                                       mkSurfaceFragmentContract,
                                       mkSurfaceFragmentRef,
                                       mkTypedDefinedLiveSurface)
import Application.Helper.LiveUpdate (LiveFragmentKey (..),
                                      LiveUpdateScope (..))
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
        hx-swap="outerHTML"
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
renderInvitesSectionFragment invitations rosterGroupId = [hsx|
    <div id="admin-invites-fragment"
         data-live-update-surface={liveSurfaceConfigJson (adminInvitesLiveSurface rosterGroupId)}>
        {renderInvitesSection invitations rosterGroupId}
    </div>
|]

data AdminInvitesSurface

data AdminInvitesSurfaceKey = AdminInvitesSurfaceKey
    { adminInvitesRosterGroupId :: !(Maybe (Id RosterGroup))
    }
    deriving (Eq, Show)

data AdminInvitesLiveFragment
    = AdminInvitesLiveFragment
    deriving (Eq, Show)

adminInvitesFragment :: AdminInvitesLiveFragment
adminInvitesFragment =
    AdminInvitesLiveFragment

adminInvitesLiveSurface :: (?context :: ControllerContext) => Id RosterGroup -> LiveSurfaceConfig
adminInvitesLiveSurface rosterGroupId =
    mkTypedDefinedLiveSurface adminInvitesLiveSurfaceDefinition AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Just rosterGroupId }

adminInvitesLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition AdminInvitesSurface AdminInvitesSurfaceKey AdminInvitesLiveFragment
adminInvitesLiveSurfaceDefinition =
    adminInvitesLiveSurfaceDefinitionForVenue currentVenueScopeId

adminInvitesLiveSurfaceDefinitionForVenue :: UUID -> TypedLiveSurfaceDefinition AdminInvitesSurface AdminInvitesSurfaceKey AdminInvitesLiveFragment
adminInvitesLiveSurfaceDefinitionForVenue surfaceVenueId =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "admin-invites"
        , typedSurfaceScope = const (SurfaceScope AdminInvitesScope { venueId = surfaceVenueId })
        , typedSurfaceScopeFromWire = \case
            AdminInvitesScope { venueId } | venueId == surfaceVenueId -> Just AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Nothing }
            _ -> Nothing
        , typedSurfaceDefaultFragments = const [adminInvitesFragment]
        , typedSurfaceFragmentContract = \key fragment ->
            mkSurfaceFragmentContract
                (adminInvitesLiveFragmentRef key fragment)
                (liveFragmentDependsOn (AdminInvitesResource surfaceVenueId) [])
        , typedSurfaceDecorateRequestsWithin = const ["#admin-invites-fragment"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (const (RequireCurrentVenueAdmin surfaceVenueId))
        }

adminInvitesLiveFragmentRef :: AdminInvitesSurfaceKey -> AdminInvitesLiveFragment -> SurfaceFragmentRef AdminInvitesSurface
adminInvitesLiveFragmentRef AdminInvitesSurfaceKey { adminInvitesRosterGroupId } AdminInvitesLiveFragment =
    mkSurfaceFragmentRef
        AdminInvitesFragment
        "admin-invites-fragment"
        (appendQueryParams (pathTo ShowAdminInvitesFragmentAction) (maybe [] (\rosterGroupId -> [("rosterGroupId", tshow rosterGroupId)]) adminInvitesRosterGroupId))

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
            hx-swap="outerHTML"
        >
            <button class="btn btn-sm btn-outline-danger" type="submit">Revoke</button>
        </form>
    |]
