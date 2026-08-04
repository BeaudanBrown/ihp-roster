module Application.Helper.FrontendContract.Surface.AuthorizationRequirement
    ( SurfaceScopeAuthorizationRequirement (..)
    , authorizeSurfaceScopeRequirement
    ) where

import Application.Helper.Controller (currentVenueOrNothing)
import Data.Coerce (coerce)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data SurfaceScopeAuthorizationRequirement
    = RequireCurrentVenue UUID.UUID
    | RequireCurrentVenueUser UUID.UUID UUID.UUID
    | RequireCurrentVenueStaff UUID.UUID UUID.UUID
    | RequireCurrentVenueRosterGroup UUID.UUID UUID.UUID
    | RequireCurrentVenueAdmin UUID.UUID
    | RequireCurrentVenueManager UUID.UUID
    | RequireCurrentVenueOwner UUID.UUID
    | RequireCurrentVenueAdminRosterGroup UUID.UUID UUID.UUID
    | RequireSupportSuperAdmin
    deriving (Eq, Show)

authorizeSurfaceScopeRequirement ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    SurfaceScopeAuthorizationRequirement ->
    IO Bool
authorizeSurfaceScopeRequirement (RequireCurrentVenue venueId) =
    pure (currentVenueMatches venueId)
authorizeSurfaceScopeRequirement (RequireCurrentVenueUser venueId userId) =
    pure (currentVenueMatches venueId && userId == unpackId effectiveCurrentUser.id)
authorizeSurfaceScopeRequirement (RequireCurrentVenueStaff venueId staffId) =
    if currentVenueMatches venueId
        then do
            maybeStaff <-
                query @Staff
                    |> filterWhere (#id, Id staffId :: Id Staff)
                    |> filterWhere (#venueId, venueId)
                    |> fetchOneOrNothing
            pure (maybe False (\staff -> staff.userId == Just (unpackId effectiveCurrentUser.id)) maybeStaff)
        else pure False
authorizeSurfaceScopeRequirement (RequireCurrentVenueRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
        else pure False
authorizeSurfaceScopeRequirement (RequireCurrentVenueAdmin venueId) =
    pure (currentVenueMatches venueId && hasRole VenueAdmin)
authorizeSurfaceScopeRequirement (RequireCurrentVenueManager venueId) =
    pure (currentVenueMatches venueId && hasRole Manager)
authorizeSurfaceScopeRequirement (RequireCurrentVenueOwner venueId) =
    pure (currentVenueMatches venueId && hasRole VenueOwner)
authorizeSurfaceScopeRequirement (RequireCurrentVenueAdminRosterGroup venueId rosterGroupId) =
    if currentVenueMatches venueId
        then do
            hasRosterGroupAccess <- isAuthorizedCurrentVenueRosterGroupScope rosterGroupId
            pure (hasRosterGroupAccess && hasRole VenueAdmin)
        else pure False
authorizeSurfaceScopeRequirement RequireSupportSuperAdmin =
    pure currentUserIsSuperAdmin

currentVenueMatches :: (?context :: ControllerContext) => UUID.UUID -> Bool
currentVenueMatches venueId =
    maybe False (\venue -> venueId == unpackId venue.id) currentVenueOrNothing

isAuthorizedCurrentVenueRosterGroupScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID.UUID ->
    IO Bool
isAuthorizedCurrentVenueRosterGroupScope rosterGroupId = do
    case currentVenueOrNothing of
        Nothing -> pure False
        Just venue -> do
            rosterGroupOrNothing <-
                query @RosterGroup
                    |> filterWhere (#id, coerce rosterGroupId)
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOneOrNothing
            pure (isJust rosterGroupOrNothing)
