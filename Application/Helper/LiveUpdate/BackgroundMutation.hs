module Application.Helper.LiveUpdate.BackgroundMutation
    ( withDurableLiveMutationWithoutContext
    , withDurableLiveMutationOutcomeWithoutContext
    ) where

import Application.Bepis.Fact (BepisLiveMechanism (..))
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.LiveUpdate.Diagnostics
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication, withDurableLiveMutationOutcomeTransaction)
import Application.Helper.SurfaceResource
import qualified Data.Set as Set
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Prelude

-- | Atomically commits a worker/background business mutation and its durable
-- invalidation. Listener delivery begins only after the transaction commits.
withDurableLiveMutationWithoutContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    ((?modelContext :: ModelContext) => IO (LiveMutationResult a)) ->
    IO (LiveMutationResult a)
withDurableLiveMutationWithoutContext label businessAction =
    withDurableLiveMutationOutcomeWithoutContext
        (\result -> Just (label, result.liveMutationTouchedResources))
        businessAction

-- | Atomic worker/background seam for outcomes that may not contain a
-- committed live-visible change.
withDurableLiveMutationOutcomeWithoutContext ::
    (?modelContext :: ModelContext) =>
    (outcome -> Maybe (Text, Set.Set SurfaceResourceValue)) ->
    ((?modelContext :: ModelContext) => IO outcome) ->
    IO outcome
withDurableLiveMutationOutcomeWithoutContext publicationFor businessAction = do
    startedAtNs <- getMonotonicTimeNSec
    (outcome, maybePublication) <- withDurableLiveMutationOutcomeTransaction publicationFor businessAction
    case (publicationFor outcome, maybePublication) of
        (Nothing, Nothing) -> pure outcome
        (Just (label, resources), Just publication) ->
            completeBackgroundInvalidation startedAtNs label (LiveMutationResult outcome resources) publication
                |> fmap (.liveMutationValue)
        _ -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "durable background live mutation outcome/publication mismatch"

completeBackgroundInvalidation :: Word64 -> Text -> LiveMutationResult a -> DurablePublication -> IO (LiveMutationResult a)
completeBackgroundInvalidation startedAtNs label result publication = do
    (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
    emitDurablePublicationLog label publication
    completedAtNs <- getMonotonicTimeNSec
    let profile =
            liveInvalidationProfile
                label
                (durationBetweenMs startedAtNs completedAtNs)
                (liveMutationTouchedResources observed)
                []
                (liveMutationTouchedResources observed)
                []
                []
                LiveInvalidationStageDurations
                    { observeDurationMs
                    , activeDurationMs = 0
                    , expandDurationMs = 0
                    , planDurationMs = 0
                    , broadcastDurationMs = 0
                    }
    emitLiveInvalidationProfileLog profile
    emitLiveFactFromProfile BepisBackgroundLiveInvalidation profile
    pure observed
