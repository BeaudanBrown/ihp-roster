module Web.LiveResourceInvalidation
    ( expandLiveResources
    , expandLiveResourcesWithoutContext
    , invalidateTouchedResources
    , invalidateTouchedResourcesWithoutContext
    , leaveRequestsContentDependsOn
    , profileLeaveRequestsDependsOn
    , rosterWeekLeaveCalendarDependsOn
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate (LiveUpdateScope (..), activeLiveUpdateScopes, activeRosterWeekScopes)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import qualified Data.Set as Set
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.LiveSurfaceRegistry (performLiveSurfaceInvalidationTarget,
                                performLiveSurfaceInvalidationTargetWithoutContext,
                                planRegisteredLiveSurfaceInvalidations,
                                planRegisteredLiveSurfaceInvalidationsWithoutContext)

leaveRequestsContentDependsOn :: Id Venue -> [LiveResource]
leaveRequestsContentDependsOn venueId =
    [LeaveRequestsResource (unpackId venueId)]

profileLeaveRequestsDependsOn :: UUID -> [LiveResource]
profileLeaveRequestsDependsOn staffId =
    [StaffLeaveRequestsResource staffId]

rosterWeekLeaveCalendarDependsOn :: Id Venue -> Int -> [LiveResource]
rosterWeekLeaveCalendarDependsOn venueId weekOffset =
    [LeaveCalendarResource (unpackId venueId) weekOffset]

expandLiveResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [LiveUpdateScope] ->
    Set.Set LiveResource ->
    IO (Set.Set LiveResource)
expandLiveResources activeScopes resources = do
    expanded <- Set.unions <$> mapM expandOne (Set.toList resources)
    pure (resources <> expanded)
    where
        expandOne (LeaveCalendarResource venueId weekOffset) =
            pure (expandLeaveCalendarResource activeScopes venueId weekOffset)
        expandOne (StaffProfileResource staffId) =
            activeRosterWeekResourcesForStaff activeScopes staffId
        expandOne (StaffPreferencesResource staffId) =
            activeRosterWeekResourcesForStaff activeScopes staffId
        expandOne (StaffRosterMembershipResource staffId) =
            activeRosterWeekResourcesForStaff activeScopes staffId
        expandOne (StaffPayProfileResource staffId) =
            staffVenueResource staffId XeroMappingsResource
        expandOne _ =
            pure Set.empty

expandLiveResourcesWithoutContext :: [(UUID, UUID, Int)] -> Set.Set LiveResource -> Set.Set LiveResource
expandLiveResourcesWithoutContext activeRosterScopes resources =
    resources <> Set.unions (map expandOne (Set.toList resources))
    where
        expandOne (LeaveCalendarResource venueId weekOffset) =
            Set.fromList
                [ RosterWeekResource rosterGroupId weekOffset
                | (activeVenueId, rosterGroupId, activeWeekOffset) <- activeRosterScopes
                , activeVenueId == venueId
                , activeWeekOffset == weekOffset
                ]
        expandOne _ =
            Set.empty

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result = do
    observed <- recordLiveMutationDiagnostics label result
    activeScopes <- activeLiveUpdateScopes
    expandedResources <- expandLiveResources activeScopes (liveMutationTouchedResources observed)
    let dependencyTargets = planRegisteredLiveSurfaceInvalidations expandedResources activeScopes
    forM_ dependencyTargets performLiveSurfaceInvalidationTarget
    pure observed

invalidateTouchedResourcesWithoutContext :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResourcesWithoutContext label result = do
    observed <- recordLiveMutationDiagnostics label result
    activeScopes <- activeLiveUpdateScopes
    activeRosterScopes <- activeRosterWeekScopes
    let expandedResources = expandLiveResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed)
    let dependencyTargets = planRegisteredLiveSurfaceInvalidationsWithoutContext expandedResources activeScopes
    forM_ dependencyTargets performLiveSurfaceInvalidationTargetWithoutContext
    pure observed

expandLeaveCalendarResource :: [LiveUpdateScope] -> UUID -> Int -> Set.Set LiveResource
expandLeaveCalendarResource activeScopes venueId weekOffset =
    Set.fromList
        [ RosterWeekResource rosterGroupId weekOffset
        | RosterWeekScope { venueId = activeVenueId, rosterGroupId, weekOffset = activeWeekOffset } <- activeScopes
        , activeVenueId == venueId
        , activeWeekOffset == weekOffset
        ]

activeRosterWeekResourcesForStaff ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [LiveUpdateScope] ->
    UUID ->
    IO (Set.Set LiveResource)
activeRosterWeekResourcesForStaff activeScopes staffId = do
    maybeStaff <- currentVenueStaff staffId
    case maybeStaff of
        Nothing -> pure Set.empty
        Just staff -> do
            rosterGroupIds <- fetchStaffRosterGroupIds staff
            let rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
            pure $
                Set.fromList
                    [ RosterWeekResource rosterGroupId weekOffset
                    | RosterWeekScope { venueId, rosterGroupId, weekOffset } <- activeScopes
                    , venueId == unpackId currentVenueId
                    , rosterGroupId `Set.member` rosterGroupIdSet
                    ]

staffVenueResource ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID ->
    (UUID -> LiveResource) ->
    IO (Set.Set LiveResource)
staffVenueResource staffId mkResource = do
    maybeStaff <- currentVenueStaff staffId
    pure $ maybe Set.empty (Set.singleton . mkResource . (.venueId)) maybeStaff

currentVenueStaff ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID ->
    IO (Maybe Staff)
currentVenueStaff staffId =
    query @Staff
        |> filterWhere (#id, Id staffId :: Id Staff)
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOneOrNothing
