module Application.Xero.ReferenceSyncFence
    ( XeroReferenceSyncAttempt (..)
    , ReferenceSyncWrite (..)
    , lockXeroReferenceSyncAttempt
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (ProviderRuntimeInvariant), externalRuntimeInvariantFailure)
import Generated.Types
import Database.PostgreSQL.Simple (Only (..))
import IHP.Fetch (fetch)
import IHP.ModelSupport (sqlQuery, unpackId)
import IHP.Prelude

-- The run distinguishes attempts, including retries of the same durable job.
-- The real runtime clock is sampled after locks, not before a possible lock wait.
data XeroReferenceSyncAttempt = XeroReferenceSyncAttempt
    { referenceSyncAttemptJob :: !AppJob
    , referenceSyncAttemptRun :: !XeroSyncRun
    , referenceSyncAttemptTime :: IO UTCTime
    }

data ReferenceSyncWrite = ReferenceSyncCompletion | ReferenceSyncFailure

-- Must run inside the category/run mutation transaction. Holding the lease row
-- through publication serializes the write against lease takeover; the run and
-- connection locks fence supersession and reconnection independently.
lockXeroReferenceSyncAttempt ::
    (?modelContext :: ModelContext) =>
    ReferenceSyncWrite -> XeroReferenceSyncAttempt -> XeroConnection -> IO ()
lockXeroReferenceSyncAttempt write attempt connection = do
    leases :: [(Maybe UUID, UTCTime)] <- sqlQuery
        "SELECT app_job_id, lease_expires_at FROM xero_reference_sync_leases WHERE tenant_id = ? FOR UPDATE"
        (Only connection.tenantId)
    connectionIds :: [Only UUID] <- sqlQuery
        "SELECT id FROM xero_connections WHERE id = ? FOR UPDATE" (Only (unpackId connection.id))
    runIds :: [Only UUID] <- sqlQuery
        "SELECT id FROM xero_sync_runs WHERE id = ? AND xero_connection_id = ? AND sync_status = ? FOR UPDATE"
        (unpackId attempt.referenceSyncAttemptRun.id, unpackId connection.id, Running)
    now <- attempt.referenceSyncAttemptTime
    let ownsLease = case leases of
            [(Just owner, expiresAt)] -> owner == unpackId attempt.referenceSyncAttemptJob.id && expiresAt > now
            _ -> False
    unless (ownsLease && not (null connectionIds) && not (null runIds)) staleAttempt
    latest <- fetch connection.id
    let allowedStatus = case write of
            ReferenceSyncCompletion -> latest.connectionStatus == "active"
            ReferenceSyncFailure -> latest.connectionStatus `elem` ["active", "reauthorization_required"]
    unless (allowedStatus && latest.tenantId == connection.tenantId && latest.encryptedRefreshToken == connection.encryptedRefreshToken) staleAttempt
  where
    staleAttempt = externalRuntimeInvariantFailure ProviderRuntimeInvariant "Xero reference sync attempt no longer owns publication."
