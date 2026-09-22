{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Web.RosterWeeks.AuthorizedScope
    ( AuthorizedRosterScope
    , authorizeRosterScope
    , authorizedRosterWindowScope
    , authorizedVenueConfig
    , authorizedRosterGroups
    , authorizedRosterGroup
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..),
                                  externalRuntimeInvariantFailure)
import Application.Helper.ControllerAccess (fetchVenueConfig)
import Application.Helper.Profiling (profileActionSpan)
import Application.Helper.RosterGroups (fetchViewableRosterGroups)
import Web.Controller.Prelude
import Web.RosterWeeks.DateRange (RosterWindowScope (..),
                                  rosterWindowScopeMatchesConfig)

-- The constructor is intentionally private. Possession proves that the scope is
-- current-venue, current-calendar, and viewable by the effective roster actor.
data AuthorizedRosterScope = AuthorizedRosterScope
    { authorizedRosterWindowScope :: !RosterWindowScope
    , authorizedVenueConfig       :: !VenueConfig
    , authorizedRosterGroups      :: ![RosterGroup]
    , authorizedRosterGroup       :: !RosterGroup
    }

authorizeRosterScope :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO AuthorizedRosterScope
authorizeRosterScope authorizedRosterWindowScope =
    profileActionSpan "roster.snapshot.authorize_scope" do
        authorizedVenueConfig <- profileActionSpan "roster.snapshot.fetch_venue_config" fetchVenueConfig
        accessDeniedUnless (authorizedRosterWindowScope.rosterWindowVenueId == currentVenueId)
        accessDeniedUnless (rosterWindowScopeMatchesConfig authorizedVenueConfig authorizedRosterWindowScope)
        authorizedRosterGroups <- profileActionSpan "roster.snapshot.fetch_viewable_groups" fetchViewableRosterGroups
        let authorizedRosterGroupOrNothing = find ((== authorizedRosterWindowScope.rosterWindowRosterGroupId) . (.id)) authorizedRosterGroups
        accessDeniedUnless (isJust authorizedRosterGroupOrNothing)
        let authorizedRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") authorizedRosterGroupOrNothing
        pure AuthorizedRosterScope { .. }
