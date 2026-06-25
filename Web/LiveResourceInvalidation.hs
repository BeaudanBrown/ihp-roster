module Web.LiveResourceInvalidation
    ( LiveInvalidationProfile (..)
    , LiveInvalidationStageDurations (..)
    , candidateLiveScopesForResourcesWithoutContext
    , expandLiveResources
    , expandLiveResourcesWithoutContext
    , invalidateTouchedResources
    , invalidateTouchedResourcesWithoutContext
    , liveInvalidationProfile
    , renderLiveInvalidationProfile
    ) where

import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveUpdateBroadcastResult (..),
                                              LiveUpdateScope (..),
                                              activeLiveUpdateScopes,
                                              activeRosterWeekScopes)
import Application.Helper.Profiling (profileActionSpanWithDetail)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.UUID (UUID)
import GHC.Clock (getMonotonicTimeNSec)
import qualified System.Environment as Environment
import Web.Controller.Prelude
import Web.LiveSurfaceRegistry (LiveSurfaceInvalidationTarget (..),
                                performLiveSurfaceInvalidationTarget,
                                performLiveSurfaceInvalidationTargetWithoutContext,
                                planRegisteredLiveSurfaceInvalidations,
                                planRegisteredLiveSurfaceInvalidationsWithoutContext)

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
        expandOne (RosterEndTimesConfigResource venueId) =
            pure (expandActiveVenueRosterWeekResources activeScopes venueId)
        expandOne (RosterWeekBoundaryConfigResource venueId) =
            pure (expandActiveVenueRosterWeekResources activeScopes venueId)
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
        expandOne (RosterEndTimesConfigResource venueId) =
            expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId
        expandOne (RosterWeekBoundaryConfigResource venueId) =
            expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId
        expandOne _ =
            Set.empty

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result =
    profileActionSpanWithDetail "live_resources.invalidate" do
        startedAtNs <- getMonotonicTimeNSec
        (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
        (activeScopes, activeDurationMs) <- measureDuration activeLiveUpdateScopes
        (expandedResources, expandDurationMs) <- measureDuration (expandLiveResources activeScopes (liveMutationTouchedResources observed))
        (candidateScopes, candidateDurationMs) <- measureDuration (candidateLiveScopesForResources expandedResources)
        let planningScopes = coalesceScopes (activeScopes <> candidateScopes)
        (dependencyTargets, planDurationMs) <- measureDuration (pure (planRegisteredLiveSurfaceInvalidations expandedResources planningScopes))
        (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performLiveSurfaceInvalidationTarget dependencyTargets)
        completedAtNs <- getMonotonicTimeNSec
        let profile =
                liveInvalidationProfile
                    label
                    (durationBetweenMs startedAtNs completedAtNs)
                    (liveMutationTouchedResources observed)
                    activeScopes
                    expandedResources
                    candidateScopes
                    planningScopes
                    dependencyTargets
                    broadcastResults
                    LiveInvalidationStageDurations { observeDurationMs, activeDurationMs, expandDurationMs, candidateDurationMs, planDurationMs, broadcastDurationMs }
        emitLiveInvalidationProfileLog profile
        pure (observed, Just (renderLiveInvalidationProfile profile))

invalidateTouchedResourcesWithoutContext :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResourcesWithoutContext label result = do
    startedAtNs <- getMonotonicTimeNSec
    (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
    (activeScopes, activeDurationMs) <- measureDuration activeLiveUpdateScopes
    (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWeekScopes
    let activeDurationMs' = activeDurationMs + activeRosterDurationMs
    (expandedResources, expandDurationMs) <- measureDuration (pure (expandLiveResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed)))
    (candidateScopes, candidateDurationMs) <- measureDuration (pure (candidateLiveScopesForResourcesWithoutContext expandedResources))
    let planningScopes = coalesceScopes (activeScopes <> candidateScopes)
    (dependencyTargets, planDurationMs) <- measureDuration (pure (planRegisteredLiveSurfaceInvalidationsWithoutContext expandedResources planningScopes))
    (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performLiveSurfaceInvalidationTargetWithoutContext dependencyTargets)
    completedAtNs <- getMonotonicTimeNSec
    let profile =
            liveInvalidationProfile
                label
                (durationBetweenMs startedAtNs completedAtNs)
                (liveMutationTouchedResources observed)
                activeScopes
                expandedResources
                candidateScopes
                planningScopes
                dependencyTargets
                broadcastResults
                LiveInvalidationStageDurations { observeDurationMs, activeDurationMs = activeDurationMs', expandDurationMs, candidateDurationMs, planDurationMs, broadcastDurationMs }
    emitLiveInvalidationProfileLog profile
    pure observed

data LiveInvalidationProfile = LiveInvalidationProfile
    { profileLabel                    :: !Text
    , profileTotalDurationMs          :: !Double
    , profileTouchedResourceCount     :: !Int
    , profileActiveScopeCount         :: !Int
    , profileExpandedResourceCount    :: !Int
    , profileCandidateScopeCount      :: !Int
    , profilePlanningScopeCount       :: !Int
    , profileTargetCount              :: !Int
    , profileTargetFragmentCount      :: !Int
    , profileBroadcastCount           :: !Int
    , profileBroadcastSubscriberCount :: !Int
    , profileStageDurations           :: !LiveInvalidationStageDurations
    }
    deriving (Eq, Show)

data LiveInvalidationStageDurations = LiveInvalidationStageDurations
    { observeDurationMs   :: !Double
    , activeDurationMs    :: !Double
    , expandDurationMs    :: !Double
    , candidateDurationMs :: !Double
    , planDurationMs      :: !Double
    , broadcastDurationMs :: !Double
    }
    deriving (Eq, Show)

liveInvalidationProfile ::
    Text ->
    Double ->
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    Set.Set LiveResource ->
    [LiveUpdateScope] ->
    [LiveUpdateScope] ->
    [LiveSurfaceInvalidationTarget] ->
    [LiveUpdateBroadcastResult] ->
    LiveInvalidationStageDurations ->
    LiveInvalidationProfile
liveInvalidationProfile label totalDurationMs touchedResources activeScopes expandedResources candidateScopes planningScopes targets broadcastResults stageDurations =
    LiveInvalidationProfile
        { profileLabel = label
        , profileTotalDurationMs = totalDurationMs
        , profileTouchedResourceCount = Set.size touchedResources
        , profileActiveScopeCount = length activeScopes
        , profileExpandedResourceCount = Set.size expandedResources
        , profileCandidateScopeCount = length candidateScopes
        , profilePlanningScopeCount = length planningScopes
        , profileTargetCount = length targets
        , profileTargetFragmentCount = sum (map (length . (.targetFragments)) targets)
        , profileBroadcastCount = length broadcastResults
        , profileBroadcastSubscriberCount = sum (map (.broadcastSubscriberCount) broadcastResults)
        , profileStageDurations = stageDurations
        }

renderLiveInvalidationProfile :: LiveInvalidationProfile -> Text
renderLiveInvalidationProfile profile =
    Text.intercalate
        " "
        [ "label=" <> profile.profileLabel
        , "touched=" <> tshow profile.profileTouchedResourceCount
        , "active_scopes=" <> tshow profile.profileActiveScopeCount
        , "expanded=" <> tshow profile.profileExpandedResourceCount
        , "candidate_scopes=" <> tshow profile.profileCandidateScopeCount
        , "planning_scopes=" <> tshow profile.profilePlanningScopeCount
        , "targets=" <> tshow profile.profileTargetCount
        , "target_fragments=" <> tshow profile.profileTargetFragmentCount
        , "broadcasts=" <> tshow profile.profileBroadcastCount
        , "subscribers=" <> tshow profile.profileBroadcastSubscriberCount
        , "total_ms=" <> renderDuration profile.profileTotalDurationMs
        , "observe_ms=" <> renderDuration profile.profileStageDurations.observeDurationMs
        , "active_ms=" <> renderDuration profile.profileStageDurations.activeDurationMs
        , "expand_ms=" <> renderDuration profile.profileStageDurations.expandDurationMs
        , "candidate_ms=" <> renderDuration profile.profileStageDurations.candidateDurationMs
        , "plan_ms=" <> renderDuration profile.profileStageDurations.planDurationMs
        , "broadcast_ms=" <> renderDuration profile.profileStageDurations.broadcastDurationMs
        ]

emitLiveInvalidationProfileLog :: LiveInvalidationProfile -> IO ()
emitLiveInvalidationProfileLog profile = do
    enabled <- liveInvalidationProfilingLogEnabled
    when enabled do
        TextIO.putStrLn ("[live-invalidation] " <> renderLiveInvalidationProfile profile)

liveInvalidationProfilingLogEnabled :: IO Bool
liveInvalidationProfilingLogEnabled = do
    value <- Environment.lookupEnv "LIVE_INVALIDATION_PROFILING"
    pure (maybe False (`elem` ["1", "true", "TRUE", "yes", "YES", "on", "ON"]) value)

measureDuration :: IO a -> IO (a, Double)
measureDuration action = do
    startedAtNs <- getMonotonicTimeNSec
    result <- action
    completedAtNs <- getMonotonicTimeNSec
    pure (result, durationBetweenMs startedAtNs completedAtNs)

durationBetweenMs :: Word64 -> Word64 -> Double
durationBetweenMs startedAtNs completedAtNs =
    fromIntegral (completedAtNs - startedAtNs) / 1000000

renderDuration :: Double -> Text
renderDuration durationMs =
    tshow (fromIntegral (round (durationMs * 10)) / 10 :: Double)

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
        candidateScopesForResource (AdminVenueSettingsResource venueId) =
            pure [AdminVenueConfigScope { venueId }]
        candidateScopesForResource (AdminInvitesResource venueId) =
            pure [AdminInvitesScope { venueId }]
        candidateScopesForResource (AdminRosterGroupsResource venueId) =
            pure [AdminRosterGroupsScope { venueId }]
        candidateScopesForResource (AdminShiftTypesResource venueId) =
            pure [AdminShiftTypesScope { venueId }]
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
        candidateScopesForResource (AdminVenueSettingsResource venueId) =
            [AdminVenueConfigScope { venueId }]
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

expandActiveVenueRosterWeekResources :: [LiveUpdateScope] -> UUID -> Set.Set LiveResource
expandActiveVenueRosterWeekResources activeScopes venueId =
    Set.fromList
        [ RosterWeekResource rosterGroupId weekOffset
        | RosterWeekScope { venueId = activeVenueId, rosterGroupId, weekOffset } <- activeScopes
        , activeVenueId == venueId
        ]

expandActiveVenueRosterWeekResourcesWithoutContext :: [(UUID, UUID, Int)] -> UUID -> Set.Set LiveResource
expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId =
    Set.fromList
        [ RosterWeekResource rosterGroupId weekOffset
        | (activeVenueId, rosterGroupId, weekOffset) <- activeRosterScopes
        , activeVenueId == venueId
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
