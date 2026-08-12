module Application.Helper.LiveUpdate.DurablePublisher
    ( publishDurableInvalidation
    ) where

import Application.Helper.LiveUpdate.DurableCodec
import Control.Monad (void)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.UUID (UUID)
import Database.PostgreSQL.Simple (Only (..))
import IHP.ModelSupport (sqlExec, sqlQuery, withTransaction)
import IHP.Prelude

-- | Compatibility-stage publisher. Callers still commit their business write
-- first; this function atomically persists the complete outbox event, current
-- versions, and transactional wake-up before returning.
publishDurableInvalidation :: (?modelContext :: ModelContext) => Text -> Set.Set SurfaceResourceValue -> IO UUID
publishDurableInvalidation source resources = do
    unless (validSource source) (error "invalid live invalidation source")
    encoded <- either (error . cs) pure (mapM encodeDurableResource (Set.toAscList resources))
    withTransaction do
        eventIds :: [(UUID, Int)] <- sqlQuery "INSERT INTO live_invalidation_events (source) VALUES (?) RETURNING id, sequence_number" (Only source)
        (eventId, eventSequence) <- case eventIds of [value] -> pure value; _ -> error "live invalidation event insert did not return one id"
        forM_ encoded \resource -> do
            void $ sqlExec "INSERT INTO live_invalidation_event_resources (event_id, resource_key, resource_payload) VALUES (?, ?, ?::jsonb)" (eventId, resource.durableResourceKey, resource.durableResourcePayload)
            void $ sqlExec "INSERT INTO live_resource_versions (resource_key, resource_payload, latest_event_id, latest_event_sequence) VALUES (?, ?::jsonb, ?, ?) ON CONFLICT (resource_key) DO UPDATE SET resource_payload = EXCLUDED.resource_payload, latest_event_id = EXCLUDED.latest_event_id, latest_event_sequence = EXCLUDED.latest_event_sequence, updated_at = NOW() WHERE live_resource_versions.latest_event_sequence < EXCLUDED.latest_event_sequence" (resource.durableResourceKey, resource.durableResourcePayload, eventId, eventSequence)
        void $ sqlExec "SELECT pg_notify('live_invalidation_events', ?)" (Only (tshow eventId))
        pure eventId

validSource :: Text -> Bool
validSource source = not (null (Text.strip source)) && Text.length source <= 120
