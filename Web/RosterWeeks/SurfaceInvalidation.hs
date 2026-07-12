{-# LANGUAGE TypeApplications #-}

module Web.RosterWeeks.SurfaceInvalidation
    ( expandRosterSurfaceResources
    , expandRosterSurfaceResourcesWithoutContext
    ) where

import qualified Application.Helper.FrontendContract.Surface.Profile as ProfileSurface
import qualified Application.Helper.FrontendContract.Surface.Roster as RosterSurface
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.SurfaceResource
import qualified Data.Set as Set
import Data.UUID (UUID)
import Web.Controller.Prelude

-- | Roster owns domain expansion from venue/staff configuration resources to
-- the active roster-week resources whose rendered read models can change.
expandRosterSurfaceResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [(UUID, UUID, Int)] ->
    Set.Set SurfaceResourceValue ->
    IO (Set.Set SurfaceResourceValue)
expandRosterSurfaceResources activeRosterScopes resources = do
    expanded <- Set.unions <$> mapM expandOne (Set.toList resources)
    pure (resources <> expanded)
  where
    expandOne resourceValue
        | rosterVenueConfigResource resourceValue
        , Just venueId <- rosterVenueConfigResourceVenueId resourceValue =
            pure (activeVenueRosterWeekResources activeRosterScopes venueId)
        | rosterStaffResource resourceValue
        , Just staffId <- rosterStaffResourceStaffId resourceValue =
            activeRosterWeekResourcesForStaff activeRosterScopes staffId
        | otherwise =
            pure Set.empty

expandRosterSurfaceResourcesWithoutContext ::
    [(UUID, UUID, Int)] ->
    Set.Set SurfaceResourceValue ->
    Set.Set SurfaceResourceValue
expandRosterSurfaceResourcesWithoutContext activeRosterScopes resources =
    resources <> Set.unions (map expandOne (Set.toList resources))
  where
    expandOne resourceValue
        | rosterVenueConfigResource resourceValue
        , Just venueId <- rosterVenueConfigResourceVenueId resourceValue =
            activeVenueRosterWeekResources activeRosterScopes venueId
        | otherwise =
            Set.empty

rosterVenueConfigResource :: SurfaceResourceValue -> Bool
rosterVenueConfigResource resourceValue =
    resourceMatchesFor @RosterSurface.RosterSurface @RosterSurface.RosterEndTimesConfig resourceValue
        || resourceMatchesFor @RosterSurface.RosterSurface @RosterSurface.RosterWeekBoundaryConfig resourceValue

rosterVenueConfigResourceVenueId :: SurfaceResourceValue -> Maybe UUID
rosterVenueConfigResourceVenueId =
    resourceFieldUuidFor @RosterSurface.RosterSurface @RosterSurface.RosterEndTimesConfig @RosterSurface.VenueId

rosterStaffResource :: SurfaceResourceValue -> Bool
rosterStaffResource resourceValue =
    resourceMatchesFor @ProfileSurface.ProfileSurface @ProfileSurface.StaffProfile resourceValue
        || resourceMatchesFor @ProfileSurface.ProfileSurface @ProfileSurface.StaffPreferences resourceValue

rosterStaffResourceStaffId :: SurfaceResourceValue -> Maybe UUID
rosterStaffResourceStaffId =
    resourceFieldUuidFor @ProfileSurface.ProfileSurface @ProfileSurface.StaffProfile @ProfileSurface.StaffId

activeVenueRosterWeekResources :: [(UUID, UUID, Int)] -> UUID -> Set.Set SurfaceResourceValue
activeVenueRosterWeekResources activeRosterScopes venueId =
    Set.fromList
        [ rosterWeekResource rosterGroupId weekOffset
        | (activeVenueId, rosterGroupId, weekOffset) <- activeRosterScopes
        , activeVenueId == venueId
        ]

activeRosterWeekResourcesForStaff ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [(UUID, UUID, Int)] ->
    UUID ->
    IO (Set.Set SurfaceResourceValue)
activeRosterWeekResourcesForStaff activeRosterScopes staffId = do
    maybeStaff <- currentVenueStaff staffId
    case maybeStaff of
        Nothing -> pure Set.empty
        Just staff -> do
            rosterGroupIds <- fetchStaffRosterGroupIds staff
            let rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
            pure $
                Set.fromList
                    [ rosterWeekResource rosterGroupId weekOffset
                    | (venueId, rosterGroupId, weekOffset) <- activeRosterScopes
                    , venueId == unpackId currentVenueId
                    , rosterGroupId `Set.member` rosterGroupIdSet
                    ]

currentVenueStaff ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID ->
    IO (Maybe Staff)
currentVenueStaff staffId =
    query @Staff
        |> filterWhere (#id, Id staffId :: Id Staff)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
