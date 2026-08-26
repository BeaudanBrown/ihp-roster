module Application.Helper.LiveUpdate.OutboxPruning
    ( LiveInvalidationOutboxPruneConfig (..)
    , LiveInvalidationOutboxPruneSummary (..)
    , defaultLiveInvalidationOutboxPruneConfig
    , pruneExpiredLiveInvalidationOutbox
    , pruneExpiredLiveInvalidationOutboxAt
    ) where

import Application.Error.ExternalRuntime (throwExternalRuntime)
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Control.Concurrent (threadDelay)
import qualified Control.Exception as Exception
import Data.Int (Int64)
import qualified Data.Text.IO as TextIO
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import qualified Database.PostgreSQL.Simple as PG
import IHP.ModelSupport (sqlQueryScalar, withTransaction)
import IHP.ModelSupport.Types (ModelContext)
import IHP.Prelude

-- | Operational bounds for one pruning invocation. Retention and batch size are
-- deployment options; timeout/retry bounds stay app-owned and conservative.
data LiveInvalidationOutboxPruneConfig = LiveInvalidationOutboxPruneConfig
    { retentionSeconds :: !Int
    , batchSize        :: !Int
    , maximumRetries   :: !Int
    }
    deriving (Eq, Show)

data LiveInvalidationOutboxPruneSummary = LiveInvalidationOutboxPruneSummary
    { deletedEventCount             :: !Int
    , completedBatchCount           :: !Int
    , remainingExpiredEventCount    :: !Int
    , oldestEventCreatedAt          :: !(Maybe UTCTime)
    , eventCount                    :: !Int
    , eventResourceCount            :: !Int
    , resourceVersionCount          :: !Int
    , eventTableSizeBytes           :: !Int64
    , eventResourceTableSizeBytes   :: !Int64
    , resourceVersionTableSizeBytes :: !Int64
    }
    deriving (Eq, Show)

defaultLiveInvalidationOutboxPruneConfig :: LiveInvalidationOutboxPruneConfig
defaultLiveInvalidationOutboxPruneConfig =
    LiveInvalidationOutboxPruneConfig
        { retentionSeconds = 7 * 24 * 60 * 60
        , batchSize = 1000
        , maximumRetries = 3
        }

pruneExpiredLiveInvalidationOutbox :: (?modelContext :: ModelContext) => LiveInvalidationOutboxPruneConfig -> IO LiveInvalidationOutboxPruneSummary
pruneExpiredLiveInvalidationOutbox config =
    getCurrentTime >>= \now -> pruneExpiredLiveInvalidationOutboxAt now config

pruneExpiredLiveInvalidationOutboxAt :: (?modelContext :: ModelContext) => UTCTime -> LiveInvalidationOutboxPruneConfig -> IO LiveInvalidationOutboxPruneSummary
pruneExpiredLiveInvalidationOutboxAt now config = do
    validateConfig config
    pruneBatches 0 0
  where
    cutoff = addUTCTime (negate (fromIntegral config.retentionSeconds)) now

    pruneBatches deletedTotal batchCount = do
        deleted <- pruneBatchWithRetry config cutoff 0
        if deleted == 0
            then collectSummary cutoff deletedTotal batchCount
            else pruneBatches (deletedTotal + deleted) (batchCount + 1)

validateConfig :: LiveInvalidationOutboxPruneConfig -> IO ()
validateConfig config = do
    when (config.retentionSeconds < 7 * 24 * 60 * 60) (externalRuntimeInvariantFailure PersistedRuntimeInvariant "Live invalidation outbox retention cannot be shorter than seven days")
    when (config.batchSize <= 0) (externalRuntimeInvariantFailure PersistedRuntimeInvariant "Live invalidation outbox batch size must be positive")
    when (config.batchSize > 1000) (externalRuntimeInvariantFailure PersistedRuntimeInvariant "Live invalidation outbox batch size cannot exceed 1000")
    when (config.maximumRetries < 0) (externalRuntimeInvariantFailure PersistedRuntimeInvariant "Live invalidation outbox retry count cannot be negative")

pruneBatchWithRetry :: (?modelContext :: ModelContext) => LiveInvalidationOutboxPruneConfig -> UTCTime -> Int -> IO Int
pruneBatchWithRetry config cutoff retryAttempt =
    pruneBatch config cutoff `Exception.catch` \exception ->
        if retryAttempt < config.maximumRetries && retryablePruneFailure exception
            then do
                TextIO.putStrLn ("live_invalidation_outbox_prune batch_retry=true attempt=" <> tshow (retryAttempt + 1))
                threadDelay (100000 * (retryAttempt + 1))
                pruneBatchWithRetry config cutoff (retryAttempt + 1)
            else throwExternalRuntime exception

pruneBatch :: (?modelContext :: ModelContext) => LiveInvalidationOutboxPruneConfig -> UTCTime -> IO Int
pruneBatch config cutoff =
    withTransaction do
        -- Deliberate focused raw-SQL boundary: QueryBuilder cannot express
        -- transaction-local timeouts plus ordered SKIP LOCKED deletion. The
        -- created_at/id order matches idx_live_invalidation_events_created_at.
        _lockTimeout :: Text <- sqlQueryScalar "SELECT set_config('lock_timeout', '1s', true)" ()
        _statementTimeout :: Text <- sqlQueryScalar "SELECT set_config('statement_timeout', '15s', true)" ()
        sqlQueryScalar
            "WITH expired AS (\
            \ SELECT id FROM live_invalidation_events\
            \ WHERE created_at < ?\
            \ ORDER BY created_at, id\
            \ LIMIT ?\
            \ FOR UPDATE SKIP LOCKED\
            \), deleted AS (\
            \ DELETE FROM live_invalidation_events event\
            \ USING expired\
            \ WHERE event.id = expired.id\
            \ RETURNING event.id\
            \) SELECT COUNT(*)::INT FROM deleted"
            (cutoff, config.batchSize)

retryablePruneFailure :: PG.SqlError -> Bool
retryablePruneFailure exception =
    PG.sqlState exception `elem` ["55P03", "57014", "40001", "40P01"]

collectSummary :: (?modelContext :: ModelContext) => UTCTime -> Int -> Int -> IO LiveInvalidationOutboxPruneSummary
collectSummary cutoff deletedEventCount completedBatchCount = do
    remainingExpiredEventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events WHERE created_at < ?" (PG.Only cutoff)
    oldestEventCreatedAt :: Maybe UTCTime <- sqlQueryScalar "SELECT MIN(created_at) FROM live_invalidation_events" ()
    eventCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_events" ()
    eventResourceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_invalidation_event_resources" ()
    resourceVersionCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::INT FROM live_resource_versions" ()
    eventTableSizeBytes :: Int64 <- sqlQueryScalar "SELECT pg_total_relation_size('live_invalidation_events')::BIGINT" ()
    eventResourceTableSizeBytes :: Int64 <- sqlQueryScalar "SELECT pg_total_relation_size('live_invalidation_event_resources')::BIGINT" ()
    resourceVersionTableSizeBytes :: Int64 <- sqlQueryScalar "SELECT pg_total_relation_size('live_resource_versions')::BIGINT" ()
    pure LiveInvalidationOutboxPruneSummary { .. }
