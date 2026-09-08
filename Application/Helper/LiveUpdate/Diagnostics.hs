module Application.Helper.LiveUpdate.Diagnostics
    ( LiveInvalidationProfile (..)
    , LiveInvalidationStageDurations (..)
    , liveInvalidationProfile
    , renderLiveInvalidationProfile
    , bepisLiveFactFromProfile
    , emitLiveFactFromProfile
    , emitDurablePublicationLog
    , emitLiveInvalidationProfileLog
    , measureDuration
    , durationBetweenMs
    ) where

import Application.Bepis.Fact (BepisFact (..), BepisLiveFact (..), BepisLiveMechanism (..), emitBepisFact)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (SurfaceInvalidationTarget (..))
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..))
import Application.Helper.LiveUpdate.Runtime (SurfaceScope, LiveUpdateBroadcastResult (..))
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Prelude
import qualified System.Environment as Environment

data LiveInvalidationProfile = LiveInvalidationProfile
    { profileLabel                    :: !Text
    , profileTotalDurationMs          :: !Double
    , profileTouchedResourceCount     :: !Int
    , profileActiveScopeCount         :: !Int
    , profileExpandedResourceCount    :: !Int
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
    , planDurationMs      :: !Double
    , broadcastDurationMs :: !Double
    }
    deriving (Eq, Show)

liveInvalidationProfile ::
    Text ->
    Double ->
    Set.Set SurfaceResourceValue ->
    [SurfaceScope] ->
    Set.Set SurfaceResourceValue ->
    [SurfaceInvalidationTarget] ->
    [LiveUpdateBroadcastResult] ->
    LiveInvalidationStageDurations ->
    LiveInvalidationProfile
liveInvalidationProfile label totalDurationMs touchedResources activeScopes expandedResources targets broadcastResults stageDurations =
    LiveInvalidationProfile
        { profileLabel = label
        , profileTotalDurationMs = totalDurationMs
        , profileTouchedResourceCount = Set.size touchedResources
        , profileActiveScopeCount = length activeScopes
        , profileExpandedResourceCount = Set.size expandedResources
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
        , "targets=" <> tshow profile.profileTargetCount
        , "target_fragments=" <> tshow profile.profileTargetFragmentCount
        , "broadcasts=" <> tshow profile.profileBroadcastCount
        , "subscribers=" <> tshow profile.profileBroadcastSubscriberCount
        , "total_ms=" <> renderDuration profile.profileTotalDurationMs
        , "observe_ms=" <> renderDuration profile.profileStageDurations.observeDurationMs
        , "active_ms=" <> renderDuration profile.profileStageDurations.activeDurationMs
        , "expand_ms=" <> renderDuration profile.profileStageDurations.expandDurationMs
        , "plan_ms=" <> renderDuration profile.profileStageDurations.planDurationMs
        , "broadcast_ms=" <> renderDuration profile.profileStageDurations.broadcastDurationMs
        ]

emitLiveFactFromProfile :: BepisLiveMechanism -> LiveInvalidationProfile -> IO ()
emitLiveFactFromProfile mechanism profile =
    emitBepisFact (BepisLiveFactValue (bepisLiveFactFromProfile mechanism profile))

bepisLiveFactFromProfile :: BepisLiveMechanism -> LiveInvalidationProfile -> BepisLiveFact
bepisLiveFactFromProfile mechanism profile =
    BepisLiveFact
        { liveFactLabel = profile.profileLabel
        , liveFactTouchedResourceCount = profile.profileTouchedResourceCount
        , liveFactExpandedResourceCount = profile.profileExpandedResourceCount
        , liveFactTargetCount = profile.profileTargetCount
        , liveFactTargetFragmentCount = profile.profileTargetFragmentCount
        , liveFactMechanism = mechanism
        }

emitDurablePublicationLog :: Text -> DurablePublication -> IO ()
emitDurablePublicationLog label publication = do
    enabled <- liveInvalidationProfilingLogEnabled
    when enabled do
        TextIO.putStrLn $
            "[live-invalidation] publication"
                <> " label=" <> label
                <> " event_id=" <> tshow publication.durablePublicationEventId
                <> " resources=" <> tshow publication.durablePublicationResourceCount
                <> " payload_bytes=" <> tshow publication.durablePublicationPayloadBytes
                <> " publish_ms=" <> renderDuration publication.durablePublicationDurationMs

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
