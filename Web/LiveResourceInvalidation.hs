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
    candidateScopes <- candidateLiveScopesForResources expandedResources
    let dependencyTargets = planRegisteredLiveSurfaceInvalidations expandedResources (coalesceScopes (activeScopes <> candidateScopes))
    forM_ dependencyTargets performLiveSurfaceInvalidationTarget
    pure observed

invalidateTouchedResourcesWithoutContext :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResourcesWithoutContext label result = do
    observed <- recordLiveMutationDiagnostics label result
    activeScopes <- activeLiveUpdateScopes
    activeRosterScopes <- activeRosterWeekScopes
    let expandedResources = expandLiveResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed)
    let candidateScopes = candidateLiveScopesForResourcesWithoutContext expandedResources
    let dependencyTargets = planRegisteredLiveSurfaceInvalidationsWithoutContext expandedResources (coalesceScopes (activeScopes <> candidateScopes))
    forM_ dependencyTargets performLiveSurfaceInvalidationTargetWithoutContext
    pure observed

candidateLiveScopesForResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Set.Set LiveResource ->
    IO [LiveUpdateScope]
candidateLiveScopesForResources resources =
    coalesceScopes . concat <$> mapM candidateScopesForResource (Set.toList resources)
    where
        candidateScopesForResource (LeaveRequestsResource venueId) =
            pure [LeaveRequestsScope { venueId }]
        candidateScopesForResource (StaffLeaveRequestsResource staffId) =
            staffProfileScope staffId
        candidateScopesForResource (TimesheetWeekResource venueId weekOffset) =
            pure [TimesheetWeekScope { venueId, weekOffset }]
        candidateScopesForResource (TimesheetDayResource venueId weekOffset _) =
            pure [TimesheetWeekScope { venueId, weekOffset }]
        candidateScopesForResource (StaffProfileResource staffId) =
            staffProfileScope staffId
        candidateScopesForResource (StaffPreferencesResource staffId) =
            staffProfileScope staffId
        candidateScopesForResource (StaffRsaDocumentsResource staffId) =
            staffProfileScope staffId
        candidateScopesForResource (RosterWeekResource rosterGroupId weekOffset) =
            pure [RosterWeekScope { venueId = unpackId currentVenueId, rosterGroupId, weekOffset }]
        candidateScopesForResource (AdminInvitesResource venueId) =
            pure [AdminInvitesScope { venueId }]
        candidateScopesForResource (AdminRosterGroupsResource venueId) =
            pure [AdminRosterGroupsScope { venueId }]
        candidateScopesForResource (AdminShiftTypesResource venueId) =
            pure [AdminShiftTypesScope { venueId }]
        candidateScopesForResource (AdminStaffComplianceResource venueId) =
            pure [StaffComplianceScope { venueId }]
        candidateScopesForResource (AdminExportsResource venueId) =
            pure [AdminExportsScope { venueId }]
        candidateScopesForResource (BillingResource venueId) =
            pure [BillingScope { venueId }]
        candidateScopesForResource SupportAwardRatesResource =
            pure [SupportPlatformScope]
        candidateScopesForResource SupportPublicHolidaysResource =
            pure [SupportPlatformScope]
        candidateScopesForResource (XeroConnectionResource venueId) =
            pure [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroMappingsResource venueId) =
            pure [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroPayItemsResource venueId) =
            pure [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroTimesheetsResource venueId) =
            pure [AdminXeroScope { venueId }]
        candidateScopesForResource _ =
            pure []

candidateLiveScopesForResourcesWithoutContext :: Set.Set LiveResource -> [LiveUpdateScope]
candidateLiveScopesForResourcesWithoutContext resources =
    coalesceScopes (concatMap candidateScopesForResource (Set.toList resources))
    where
        candidateScopesForResource (TimesheetWeekResource venueId weekOffset) =
            [TimesheetWeekScope { venueId, weekOffset }]
        candidateScopesForResource (TimesheetDayResource venueId weekOffset _) =
            [TimesheetWeekScope { venueId, weekOffset }]
        candidateScopesForResource (AdminInvitesResource venueId) =
            [AdminInvitesScope { venueId }]
        candidateScopesForResource (BillingResource venueId) =
            [BillingScope { venueId }]
        candidateScopesForResource SupportAwardRatesResource =
            [SupportPlatformScope]
        candidateScopesForResource SupportPublicHolidaysResource =
            [SupportPlatformScope]
        candidateScopesForResource (XeroConnectionResource venueId) =
            [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroMappingsResource venueId) =
            [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroPayItemsResource venueId) =
            [AdminXeroScope { venueId }]
        candidateScopesForResource (XeroTimesheetsResource venueId) =
            [AdminXeroScope { venueId }]
        candidateScopesForResource _ =
            []

staffProfileScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID ->
    IO [LiveUpdateScope]
staffProfileScope staffId = do
    maybeStaff <- currentVenueStaff staffId
    pure
        [ ProfileScope { venueId = staff.venueId, staffId }
        | staff <- maybeToList maybeStaff
        ]

coalesceScopes :: [LiveUpdateScope] -> [LiveUpdateScope]
coalesceScopes =
    Set.toList . Set.fromList

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
