module Application.Script.LiveInvalidationOutboxPrune where

import Application.Helper.LiveUpdate.OutboxPruning
import Application.Script.Prelude
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (UTCTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import IHP.Prelude
import IHP.ScriptSupport (Script)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

run :: Script
run = do
    retentionDays <- liftIO (positiveEnvironmentInteger "LIVE_INVALIDATION_OUTBOX_RETENTION_DAYS" 7)
    configuredBatchSize <- liftIO (positiveEnvironmentInteger "LIVE_INVALIDATION_OUTBOX_BATCH_SIZE" 1000)
    let config = LiveInvalidationOutboxPruneConfig
            (retentionDays * 24 * 60 * 60)
            configuredBatchSize
            defaultLiveInvalidationOutboxPruneConfig.maximumRetries
    summary <- pruneExpiredLiveInvalidationOutbox config
    liftIO $ TextIO.putStrLn $ Text.unwords
        [ "live_invalidation_outbox_prune"
        , "deleted_count=" <> tshow summary.deletedEventCount
        , "completed_batches=" <> tshow summary.completedBatchCount
        , "remaining_expired_count=" <> tshow summary.remainingExpiredEventCount
        , "oldest_event=" <> maybe "none" renderTimestamp summary.oldestEventCreatedAt
        , "event_count=" <> tshow summary.eventCount
        , "event_resource_count=" <> tshow summary.eventResourceCount
        , "resource_version_count=" <> tshow summary.resourceVersionCount
        , "event_table_bytes=" <> tshow summary.eventTableSizeBytes
        , "event_resource_table_bytes=" <> tshow summary.eventResourceTableSizeBytes
        , "resource_version_table_bytes=" <> tshow summary.resourceVersionTableSizeBytes
        ]

positiveEnvironmentInteger :: String -> Int -> IO Int
positiveEnvironmentInteger name fallback = do
    configured <- lookupEnv name
    case configured of
        Nothing -> pure fallback
        Just raw
            | Just value <- readMaybe raw
            , value > 0 -> pure value
            | otherwise -> fail (name <> " must be a positive integer")

renderTimestamp :: UTCTime -> Text
renderTimestamp = Text.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ"
