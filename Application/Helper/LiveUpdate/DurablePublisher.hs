module Application.Helper.LiveUpdate.DurablePublisher
    ( DurablePublication (..)
    , withDurableLiveMutationOutcomeTransaction
    , persistDurableInvalidationInCurrentTransaction
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.LiveUpdate.DurableCodec
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LazyByteString
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.UUID (UUID)
import Database.PostgreSQL.Simple (Only (..))
import GHC.Clock (getMonotonicTimeNSec)
import IHP.ModelSupport (sqlExec, sqlQuery, sqlQueryScalar, withTransaction)
import IHP.Prelude

-- | Sanitized persistence diagnostics.  No resource names or resource fields
-- are exposed here, because those can contain domain identifiers.
data DurablePublication = DurablePublication
    { durablePublicationEventId       :: !UUID
    , durablePublicationEventSequence :: !Int
    , durablePublicationResourceCount :: !Int
    , durablePublicationPayloadBytes  :: !Int
    , durablePublicationDurationMs    :: !Double
    }
    deriving (Eq, Show)

-- | General transaction seam for mutation outcomes that can legitimately
-- represent no business change (for example validation, stale locks, or
-- idempotent no-ops). Returning 'Nothing' commits without an invalidation;
-- returning resources atomically publishes exactly one durable event.
withDurableLiveMutationOutcomeTransaction ::
    (?modelContext :: ModelContext) =>
    (outcome -> Maybe (Text, Set.Set SurfaceResourceValue)) ->
    ((?modelContext :: ModelContext) => IO outcome) ->
    IO (outcome, Maybe DurablePublication)
withDurableLiveMutationOutcomeTransaction publicationFor businessAction =
    withTransaction do
        outcome <- businessAction
        publication <- forM (publicationFor outcome) \(source, touchedResources) ->
            persistDurableInvalidationInCurrentTransaction source touchedResources
        pure (outcome, publication)

persistDurableInvalidationInCurrentTransaction :: (?modelContext :: ModelContext) => Text -> Set.Set SurfaceResourceValue -> IO DurablePublication
persistDurableInvalidationInCurrentTransaction source resources = do
    startedAtNs <- getMonotonicTimeNSec
    unless (validSource source) (error "invalid live invalidation source")
    encoded <- either (error . cs) pure (mapM encodeDurableResource (Set.toAscList resources))
    -- Deliberate focused raw-SQL boundary: QueryBuilder cannot express the
    -- commit-ordered advisory lock, RETURNING allocation, monotonic
    -- ON CONFLICT version guard, and transactional NOTIFY as one primitive.
    -- Serialize sequence allocation through commit. A PostgreSQL sequence
    -- alone is not commit ordered, while retained-event replay is.
    void (sqlQueryScalar "SELECT 1 FROM pg_advisory_xact_lock(?)" (Only durablePublicationLockKey) :: IO Int)
    eventIds :: [(UUID, Int)] <- sqlQuery "INSERT INTO live_invalidation_events (source) VALUES (?) RETURNING id, sequence_number" (Only source)
    (eventId, eventSequence) <- case eventIds of [value] -> pure value; _ -> error "live invalidation event insert did not return one id"
    forM_ encoded \resource -> do
        void $ sqlExec "INSERT INTO live_invalidation_event_resources (event_id, resource_key, resource_payload) VALUES (?, ?, ?::jsonb)" (eventId, resource.durableResourceKey, resource.durableResourcePayload)
        void $ sqlExec "INSERT INTO live_resource_versions (resource_key, resource_payload, latest_event_id, latest_event_sequence) VALUES (?, ?::jsonb, ?, ?) ON CONFLICT (resource_key) DO UPDATE SET resource_payload = EXCLUDED.resource_payload, latest_event_id = EXCLUDED.latest_event_id, latest_event_sequence = EXCLUDED.latest_event_sequence, updated_at = NOW() WHERE live_resource_versions.latest_event_sequence < EXCLUDED.latest_event_sequence" (resource.durableResourceKey, resource.durableResourcePayload, eventId, eventSequence)
    void (sqlQueryScalar "SELECT 1 FROM pg_notify('live_invalidation_events', ?)" (Only (tshow eventId)) :: IO Int)
    completedAtNs <- getMonotonicTimeNSec
    pure DurablePublication
        { durablePublicationEventId = eventId
        , durablePublicationEventSequence = eventSequence
        , durablePublicationResourceCount = length encoded
        , durablePublicationPayloadBytes = sum (map (fromIntegral . LazyByteString.length . Aeson.encode . (.durableResourcePayload)) encoded)
        , durablePublicationDurationMs = fromIntegral (completedAtNs - startedAtNs) / 1000000
        }

durablePublicationLockKey :: Int
durablePublicationLockKey = 1380994892

validSource :: Text -> Bool
validSource source = not (null (Text.strip source)) && Text.length source <= 120
