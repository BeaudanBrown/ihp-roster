module Web.RosterWeeks.SurfaceInvalidation
    ( activeRosterResourcesForStaffGroups
    , expandRosterSurfaceResourcesWithoutContext
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster.Resource as RosterResource
import Application.Helper.SurfaceResource
import qualified Data.Set as Set
import Web.Controller.Prelude

-- | Listener-side context-free expansion for broad venue resources. Staff
-- expansion is resolved by the producer before durable publication because a
-- listener has no request/current-venue authority.
expandRosterSurfaceResourcesWithoutContext ::
    [(UUID, UUID, Day, Day, Int)] ->
    Set.Set SurfaceResourceValue ->
    Set.Set SurfaceResourceValue
expandRosterSurfaceResourcesWithoutContext activeRosterScopes resources =
    resources <> Set.unions (map expandOne (Set.toList resources))
  where
    expandOne resourceValue
        | Just venueId <- rosterVenueConfigResourceVenueId resourceValue =
            activeVenueRosterWeekResources activeRosterScopes venueId
        | otherwise =
            Set.empty

rosterVenueConfigResourceVenueId :: SurfaceResourceValue -> Maybe UUID
rosterVenueConfigResourceVenueId resourceValue =
    RosterResource.matchRosterEndTimesConfigResource resourceValue
        <|> RosterResource.matchRosterLayoutConfigResource resourceValue
        <|> RosterResource.matchRosterWeekBoundaryConfigResource resourceValue

activeVenueRosterWeekResources :: [(UUID, UUID, Day, Day, Int)] -> UUID -> Set.Set SurfaceResourceValue
activeVenueRosterWeekResources activeRosterScopes venueId =
    Set.fromList
        [ RosterResource.rosterWeekResource rosterGroupId windowStart windowEnd
        | (activeVenueId, rosterGroupId, windowStart, windowEnd, _calendarRevision) <- activeRosterScopes
        , activeVenueId == venueId
        ]

activeRosterResourcesForStaffGroups ::
    UUID ->
    [(UUID, UUID, Day, Day, Int)] ->
    [Id RosterGroup] ->
    [SurfaceResourceValue]
activeRosterResourcesForStaffGroups venueId activeRosterScopes rosterGroupIds =
    Set.toList $
        Set.fromList
            ( map (RosterResource.rosterGroupStaffResource . unpackId) rosterGroupIds
                <> [ resource
                   | (activeVenueId, rosterGroupId, windowStart, windowEnd, _calendarRevision) <- activeRosterScopes
                   , activeVenueId == venueId
                   , rosterGroupId `Set.member` rosterGroupIdSet
                   , resource <-
                        [ RosterResource.rosterWeekResource rosterGroupId windowStart windowEnd
                        , RosterResource.rosterSlotsContentResource rosterGroupId windowStart windowEnd
                        ]
                   ]
            )
  where
    rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
