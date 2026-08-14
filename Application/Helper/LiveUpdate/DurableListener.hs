module Application.Helper.LiveUpdate.DurableListener
    ( readDurableEventsAfter
    , startDurableInvalidationListener
    ) where

import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   decodeDurableResource)
import Application.Helper.LiveUpdate.DurableState
import Control.Concurrent (forkIO, threadDelay)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Data.UUID (UUID)
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Notification as Notification
import qualified Database.PostgreSQL.Simple.Transaction as Transaction
import IHP.Prelude
import System.Environment (getEnv)

startDurableInvalidationListener :: (Int -> [DurableResource] -> IO ()) -> IO ()
startDurableInvalidationListener dispatch = do
    databaseUrl <- getEnv "DATABASE_URL"
    _ <- forkIO (supervise databaseUrl 0)
    pure ()
  where
    supervise databaseUrl attempt = do
        outcome <- Exception.try (runConnection databaseUrl) :: IO (Either Exception.SomeException ())
        case outcome of
            Right () -> supervise databaseUrl 0
            Left _exception -> do
                let cappedAttempt = min attempt 6
                let delayMicros = min 10000000 (250000 * (2 ^ cappedAttempt))
                TextIO.putStrLn ("[live-invalidation-listener] healthy=false reconnect_attempt=" <> tshow (attempt + 1) <> " backoff_ms=" <> tshow (delayMicros `div` 1000) <> " connection_error=true")
                threadDelay delayMicros
                supervise databaseUrl (attempt + 1)

    runConnection databaseUrl = Exception.bracket (PG.connectPostgreSQL (cs databaseUrl)) PG.close \connection -> do
        _ <- PG.execute_ connection "SET application_name = 'bepis-live-invalidation-listener'"
        _ <- PG.execute_ connection "LISTEN live_invalidation_events"
        hydrated <- durableStateIsHydrated
        cursor <- currentDurableCursor
        if hydrated
            then replayAfter connection cursor
            else hydrateCurrentVersions connection
        TextIO.putStrLn "[live-invalidation-listener] healthy=true"
        forever do
            _ <- Notification.getNotification connection
            currentDurableCursor >>= replayAfter connection

    hydrateCurrentVersions connection = do
        (versions, cursor) <- Transaction.withTransactionMode
            (Transaction.TransactionMode Transaction.RepeatableRead Transaction.ReadOnly)
            connection do
                versions :: [(Text, Int)] <- PG.query_ connection "SELECT resource_key, latest_event_sequence FROM live_resource_versions"
                cursorRows :: [PG.Only (Maybe Int)] <- PG.query_ connection "SELECT MAX(sequence_number) FROM live_invalidation_events"
                let cursor = case cursorRows of [PG.Only value] -> fromMaybe 0 value; _ -> 0
                pure (versions, cursor)
        replaceDurableResourceVersions versions cursor
        TextIO.putStrLn ("[live-invalidation-listener] hydrated=true cursor=" <> tshow cursor <> " resources=" <> tshow (length versions))

    replayAfter connection cursor = do
        events <- readDurableEventsDetailedAfter connection cursor
        forM_ events \event ->
            do
                advanceDurableResourceVersions (map (\resource -> (resource.durableResourceKey, event.sequence)) event.resources) event.sequence
                advanced <- advanceDurableListenerCursor event.sequence
                when (advanced && not (null event.resources)) (dispatch event.sequence event.resources)
                now <- getCurrentTime
                TextIO.putStrLn ("[live-invalidation-listener] event_id=" <> tshow event.eventId <> " cursor=" <> tshow event.sequence <> " lag_events=" <> tshow (length events - 1) <> " event_age_ms=" <> tshow (round (diffUTCTime now event.createdAt * 1000) :: Int) <> " resources=" <> tshow (length event.resources) <> " decode_failures=" <> tshow event.decodeFailureCount)

data DurableReadEvent = DurableReadEvent
    { eventId   :: !UUID
    , sequence  :: !Int
    , createdAt :: !UTCTime
    , resources :: ![DurableResource]
    , decodeFailureCount :: !Int
    }

readDurableEventsAfter :: PG.Connection -> Int -> IO [(Int, [DurableResource])]
readDurableEventsAfter connection cursor = do
    events <- readDurableEventsDetailedAfter connection cursor
    pure [(event.sequence, event.resources) | event <- events]

readDurableEventsDetailedAfter :: PG.Connection -> Int -> IO [DurableReadEvent]
readDurableEventsDetailedAfter connection cursor = do
    events :: [(UUID, Int, UTCTime)] <- PG.query connection "SELECT id, sequence_number, created_at FROM live_invalidation_events WHERE sequence_number > ? ORDER BY sequence_number" (PG.Only cursor)
    forM events \(eventId, sequence, createdAt) -> do
        rows :: [(Text, Aeson.Value)] <- PG.query connection "SELECT resource_key, resource_payload FROM live_invalidation_event_resources WHERE event_id = ? ORDER BY resource_key" (PG.Only eventId)
        let decoded = partitionEithers (map (uncurry decodeDurableResource) rows)
        pure DurableReadEvent
            { eventId
            , sequence
            , createdAt
            , resources = snd decoded
            , decodeFailureCount = length (fst decoded)
            }
