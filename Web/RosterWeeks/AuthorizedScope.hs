{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Web.RosterWeeks.AuthorizedScope
    ( RosterAuthorizationContext
    , loadRosterAuthorizationContext
    , authorizationVenueConfig
    , authorizationRosterGroups
    , AuthorizedRosterScope
    , authorizeRosterScope
    , authorizeRosterScopeWithContext
    , authorizedRosterWindowScope
    , authorizedVenueConfig
    , authorizedRosterGroups
    , authorizedRosterGroup
    , authorizedCurrentStaff
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.Profiling (profileActionSpan)
import Application.Helper.RosterGroups (fetchViewableRosterGroupsForCurrentStaff)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..),
                                  rosterWindowScopeMatchesConfig)

-- Loaded once for a roster request, then reused for group resolution, scope
-- construction, and the authorized snapshot.
data RosterAuthorizationContext = RosterAuthorizationContext
    { authorizationVenueConfig  :: !VenueConfig
    , authorizationRosterGroups :: ![RosterGroup]
    , authorizationCurrentStaff :: !(Maybe Staff)
    }

loadRosterAuthorizationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO RosterAuthorizationContext
loadRosterAuthorizationContext = do
    authorizationVenueConfig <- profileActionSpan "roster.snapshot.fetch_venue_config" fetchVenueConfig
    authorizationCurrentStaff <- profileActionSpan "roster.snapshot.fetch_current_staff" (pure effectiveStaffOrNothing)
    authorizationRosterGroups <- profileActionSpan "roster.snapshot.fetch_viewable_groups" (fetchViewableRosterGroupsForCurrentStaff authorizationCurrentStaff)
    pure RosterAuthorizationContext { .. }

-- The constructor is intentionally private. Possession proves that the scope is
-- current-venue, current-calendar, and viewable by the effective roster actor.
data AuthorizedRosterScope = AuthorizedRosterScope
    { authorizedRosterWindowScope :: !RosterWindowScope
    , authorizedVenueConfig       :: !VenueConfig
    , authorizedRosterGroups      :: ![RosterGroup]
    , authorizedRosterGroup       :: !RosterGroup
    , authorizedCurrentStaff      :: !(Maybe Staff)
    }

authorizeRosterScope :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO AuthorizedRosterScope
authorizeRosterScope authorizedRosterWindowScope = do
    authorizationContext <- loadRosterAuthorizationContext
    authorizeRosterScopeWithContext authorizationContext authorizedRosterWindowScope

authorizeRosterScopeWithContext :: (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) => RosterAuthorizationContext -> RosterWindowScope -> IO AuthorizedRosterScope
authorizeRosterScopeWithContext authorizationContext authorizedRosterWindowScope =
    profileActionSpan "roster.snapshot.authorize_scope" do
        let authorizedVenueConfig = authorizationContext.authorizationVenueConfig
        let authorizedCurrentStaff = authorizationContext.authorizationCurrentStaff
        let authorizedRosterGroups = authorizationContext.authorizationRosterGroups
        accessDeniedUnless (authorizedRosterWindowScope.rosterWindowVenueId == currentVenueId)
        accessDeniedUnless (rosterWindowScopeMatchesConfig authorizedVenueConfig authorizedRosterWindowScope)
        let authorizedRosterGroupOrNothing = find ((== authorizedRosterWindowScope.rosterWindowRosterGroupId) . (.id)) authorizedRosterGroups
        accessDeniedUnless (isJust authorizedRosterGroupOrNothing)
        let authorizedRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") authorizedRosterGroupOrNothing
        pure AuthorizedRosterScope { .. }
