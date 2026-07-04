module Web.SurfaceInvalidation
    ( LiveInvalidationProfile (..)
    , LiveInvalidationStageDurations (..)
    , SurfaceInvalidationTarget (..)
    , authorizeSurfaceScope
    , candidateLiveScopesForSurfaceResourcesWithoutContext
    , expandSurfaceResources
    , expandSurfaceResourcesWithoutContext
    , invalidateTouchedResources
    , invalidateTouchedResourcesWithoutContext
    , liveInvalidationProfile
    , performSurfaceInvalidationTarget
    , performSurfaceInvalidationTargetWithoutContext
    , planSurfaceInvalidations
    , planSurfaceInvalidationsWithoutContext
    , renderLiveInvalidationProfile
    ) where

import Application.Bepis.Fact (BepisFact (..), BepisLiveFact (..),
                               BepisLiveMechanism (..), emitBepisFact)
import Application.Helper.FrontendSurface.Authorization (authorizeFrontendSurfaceLiveScope)
import Application.Helper.FrontendSurface.DependencyPlanner (planFrontendSurfaceWireInvalidation)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Profiling (profileActionSpanWithDetail)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.SurfaceResource
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.UUID (UUID)
import GHC.Clock (getMonotonicTimeNSec)
import qualified System.Environment as Environment
import Web.Controller.Prelude

data SurfaceInvalidationTarget = SurfaceInvalidationTarget
    { targetScope     :: !LiveUpdateScope
    , targetFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

authorizeSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeSurfaceScope = authorizeFrontendSurfaceLiveScope

planSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> [LiveUpdateSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidations = planSurfaceInvalidationsWithoutContext

planSurfaceInvalidationsWithoutContext :: Set.Set SurfaceResourceValue -> [LiveUpdateSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidationsWithoutContext resources subscriptions =
    coalesceTargets $ mapMaybe (planSubscriptionInvalidation resources) subscriptions

performSurfaceInvalidationTarget :: (?context :: ControllerContext, ?request :: Request) => SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTarget target = broadcastLiveInvalidationDetailed target.targetScope liveUpdateSourceClientId target.targetFragments

performSurfaceInvalidationTargetWithoutContext :: SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTargetWithoutContext target = broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

planSubscriptionInvalidation :: Set.Set SurfaceResourceValue -> LiveUpdateSubscription -> Maybe SurfaceInvalidationTarget
planSubscriptionInvalidation resources subscription = do
    let fragments = planFrontendSurfaceWireInvalidation resources subscription.subscriptionScope subscription.subscriptionMountedFragments
    if null fragments then Nothing else Just SurfaceInvalidationTarget { targetScope = subscription.subscriptionScope, targetFragments = fragments }

coalesceTargets :: [SurfaceInvalidationTarget] -> [SurfaceInvalidationTarget]
coalesceTargets targets =
    [ SurfaceInvalidationTarget scope (coalesceLiveUpdateWireFragments fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
    where
        grouped = Map.fromListWith (<>) [(target.targetScope, target.targetFragments) | target <- targets]

expandSurfaceResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [(UUID, UUID, Int)] ->
    Set.Set SurfaceResourceValue ->
    IO (Set.Set SurfaceResourceValue)
expandSurfaceResources activeRosterScopes resources = do
    expanded <- Set.unions <$> mapM expandOne (Set.toList resources)
    pure (resources <> expanded)
    where
        expandOne resourceValue
            | resourceMatches "roster-end-times-config" resourceValue || resourceMatches "roster-week-boundary-config" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue =
                pure (expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId)
            | resourceMatches "staff-profile" resourceValue || resourceMatches "staff-preferences" resourceValue
            , Just staffId <- resourceFieldUuid "staffId" resourceValue =
                activeRosterWeekResourcesForStaff activeRosterScopes staffId
            | otherwise =
                pure Set.empty

expandSurfaceResourcesWithoutContext :: [(UUID, UUID, Int)] -> Set.Set SurfaceResourceValue -> Set.Set SurfaceResourceValue
expandSurfaceResourcesWithoutContext activeRosterScopes resources =
    resources <> Set.unions (map expandOne (Set.toList resources))
    where
        expandOne resourceValue
            | resourceMatches "roster-end-times-config" resourceValue || resourceMatches "roster-week-boundary-config" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue =
                expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId
            | otherwise =
                Set.empty

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result =
    profileActionSpanWithDetail "surface_resources.invalidate" do
        startedAtNs <- getMonotonicTimeNSec
        (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
        (activeSubscriptions, activeSubscriptionDurationMs) <- measureDuration activeLiveUpdateSubscriptions
        (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWeekScopes
        let activeDurationMs = activeSubscriptionDurationMs + activeRosterDurationMs
        let activeScopes = coalesceScopes (map (.subscriptionScope) activeSubscriptions)
        (expandedResources, expandDurationMs) <- measureDuration (expandSurfaceResources activeRosterScopes (liveMutationTouchedResources observed))
        (candidateScopes, candidateDurationMs) <- measureDuration (candidateLiveScopesForSurfaceResources expandedResources)
        let planningScopes = coalesceScopes (activeScopes <> candidateScopes)
        (dependencyTargets, planDurationMs) <- measureDuration (pure (planSurfaceInvalidations expandedResources activeSubscriptions))
        (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performSurfaceInvalidationTarget dependencyTargets)
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
        emitLiveFactFromProfile BepisWebSocketFragmentRefetch profile
        pure (observed, Just (renderLiveInvalidationProfile profile))

invalidateTouchedResourcesWithoutContext :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResourcesWithoutContext label result = do
    startedAtNs <- getMonotonicTimeNSec
    (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
    (activeSubscriptions, activeDurationMs) <- measureDuration activeLiveUpdateSubscriptions
    let activeScopes = coalesceScopes (map (.subscriptionScope) activeSubscriptions)
    (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWeekScopes
    let activeDurationMs' = activeDurationMs + activeRosterDurationMs
    (expandedResources, expandDurationMs) <- measureDuration (pure (expandSurfaceResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed)))
    (candidateScopes, candidateDurationMs) <- measureDuration (pure (candidateLiveScopesForSurfaceResourcesWithoutContext expandedResources))
    let planningScopes = coalesceScopes (activeScopes <> candidateScopes)
    (dependencyTargets, planDurationMs) <- measureDuration (pure (planSurfaceInvalidationsWithoutContext expandedResources activeSubscriptions))
    (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performSurfaceInvalidationTargetWithoutContext dependencyTargets)
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
    emitLiveFactFromProfile BepisBackgroundLiveInvalidation profile
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
    Set.Set SurfaceResourceValue ->
    [LiveUpdateScope] ->
    Set.Set SurfaceResourceValue ->
    [LiveUpdateScope] ->
    [LiveUpdateScope] ->
    [SurfaceInvalidationTarget] ->
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

emitLiveFactFromProfile :: BepisLiveMechanism -> LiveInvalidationProfile -> IO ()
emitLiveFactFromProfile mechanism profile =
    emitBepisFact $ BepisLiveFactValue BepisLiveFact
        { liveFactLabel = profile.profileLabel
        , liveFactTouchedResourceCount = profile.profileTouchedResourceCount
        , liveFactExpandedResourceCount = profile.profileExpandedResourceCount
        , liveFactPlannedScopeCount = profile.profilePlanningScopeCount
        , liveFactPlannedFragmentCount = profile.profileTargetFragmentCount
        , liveFactMechanism = mechanism
        }

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

candidateLiveScopesForSurfaceResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    Set.Set SurfaceResourceValue ->
    IO [LiveUpdateScope]
candidateLiveScopesForSurfaceResources resources =
    coalesceScopes . concat <$> mapM candidateScopesForResource (Set.toList resources)
    where
        candidateScopesForResource resourceValue
            | resourceMatches "leave-requests" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [leaveRequestsLiveScope venueId]
            | resourceMatches "staff-leave-requests" resourceValue || resourceMatches "staff-profile" resourceValue || resourceMatches "staff-preferences" resourceValue || resourceMatches "staff-rsa-documents" resourceValue
            , Just staffId <- resourceFieldUuid "staffId" resourceValue = staffProfileScope staffId
            | resourceMatches "timesheet-week" resourceValue || resourceMatches "timesheet-day" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue
            , Just weekOffset <- resourceFieldInt "weekOffset" resourceValue = pure [timesheetWeekLiveScope venueId weekOffset]
            | resourceMatches "roster-week" resourceValue
            , Just rosterGroupId <- resourceFieldUuid "rosterGroupId" resourceValue
            , Just weekOffset <- resourceFieldInt "weekOffset" resourceValue = pure [rosterWeekLiveScope (unpackId currentVenueId) rosterGroupId weekOffset]
            | resourceMatches "admin-venue-settings" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminVenueConfigLiveScope venueId]
            | resourceMatches "admin-invites" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminInvitesLiveScope venueId]
            | resourceMatches "admin-roster-groups" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminRosterGroupsLiveScope venueId]
            | resourceMatches "admin-shift-types" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminShiftTypesLiveScope venueId]
            | resourceMatches "admin-exports" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminExportsLiveScope venueId]
            | resourceMatches "billing" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [billingLiveScope venueId]
            | resourceMatches "support-award-rates" resourceValue || resourceMatches "support-public-holidays" resourceValue = pure [supportPlatformLiveScope]
            | resourceMatches "xero-connection" resourceValue || resourceMatches "xero-mappings" resourceValue || resourceMatches "xero-pay-items" resourceValue || resourceMatches "xero-timesheets" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = pure [adminXeroLiveScope venueId]
            | otherwise = pure []

candidateLiveScopesForSurfaceResourcesWithoutContext :: Set.Set SurfaceResourceValue -> [LiveUpdateScope]
candidateLiveScopesForSurfaceResourcesWithoutContext resources =
    coalesceScopes (concatMap candidateScopesForResource (Set.toList resources))
    where
        candidateScopesForResource resourceValue
            | resourceMatches "timesheet-week" resourceValue || resourceMatches "timesheet-day" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue
            , Just weekOffset <- resourceFieldInt "weekOffset" resourceValue = [timesheetWeekLiveScope venueId weekOffset]
            | resourceMatches "admin-venue-settings" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = [adminVenueConfigLiveScope venueId]
            | resourceMatches "admin-invites" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = [adminInvitesLiveScope venueId]
            | resourceMatches "billing" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = [billingLiveScope venueId]
            | resourceMatches "support-award-rates" resourceValue || resourceMatches "support-public-holidays" resourceValue = [supportPlatformLiveScope]
            | resourceMatches "xero-connection" resourceValue || resourceMatches "xero-mappings" resourceValue || resourceMatches "xero-pay-items" resourceValue || resourceMatches "xero-timesheets" resourceValue
            , Just venueId <- resourceFieldUuid "venueId" resourceValue = [adminXeroLiveScope venueId]
            | otherwise = []

staffProfileScope ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID ->
    IO [LiveUpdateScope]
staffProfileScope staffId = do
    maybeStaff <- currentVenueStaff staffId
    pure
        [ profileLiveScope staff.venueId staffId
        | staff <- maybeToList maybeStaff
        ]

coalesceScopes :: [LiveUpdateScope] -> [LiveUpdateScope]
coalesceScopes =
    Set.toList . Set.fromList

expandActiveVenueRosterWeekResourcesWithoutContext :: [(UUID, UUID, Int)] -> UUID -> Set.Set SurfaceResourceValue
expandActiveVenueRosterWeekResourcesWithoutContext activeRosterScopes venueId =
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
