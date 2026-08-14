module Application.Xero.Keepalive
    ( XeroKeepaliveSweepSummary (..)
    , enqueueDueXeroKeepaliveJobs
    , enqueueDueXeroMaintenanceJobsAt
    , performXeroConnectionKeepaliveJob
    , xeroConnectionKeepaliveDedupeKey
    , xeroConnectionKeepaliveJobKind
    ) where

import Application.Async.Queue
import Application.Helper.FrontendContract.Surface.Admin.Resource (xeroConnectionResource)
import Application.Helper.SurfaceResource
import Application.Helper.Xero
import Application.Xero.Connection
import Application.Xero.ReferenceSyncJob (acquireXeroReferenceSyncLease,
                                          releaseXeroReferenceSyncLease,
                                          requestXeroReferenceSyncJob)
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text.IO as TextIO
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import Web.SurfaceInvalidation (publishTouchedResourcesWithoutContext)

data XeroKeepaliveSweepSummary = XeroKeepaliveSweepSummary
    { dueConnectionCount              :: !Int
    , enqueuedJobCount                :: !Int
    , existingJobCount                :: !Int
    , referenceSyncDueConnectionCount :: !Int
    , referenceSyncEnqueuedJobCount   :: !Int
    , referenceSyncExistingJobCount   :: !Int
    }
    deriving (Eq, Show)

xeroConnectionKeepaliveJobKind :: Text
xeroConnectionKeepaliveJobKind = "xero_connection_keepalive"

xeroConnectionKeepaliveDedupeKey :: XeroConnection -> Text
xeroConnectionKeepaliveDedupeKey connection =
    "xero-connection-keepalive-" <> tshow connection.id

enqueueDueXeroKeepaliveJobs ::
    (?modelContext :: ModelContext) =>
    IO XeroKeepaliveSweepSummary
enqueueDueXeroKeepaliveJobs =
    getCurrentTime >>= enqueueDueXeroMaintenanceJobsAt

enqueueDueXeroMaintenanceJobsAt ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    IO XeroKeepaliveSweepSummary
enqueueDueXeroMaintenanceJobsAt now = do
    let keepaliveDueBefore = addUTCTime (negate (7 * 24 * 60 * 60)) now
    let referenceSyncDueBefore = addUTCTime (negate (6 * 24 * 60 * 60)) now
    activeConnections <-
        query @XeroConnection
            |> filterWhere (#connectionStatus, "active" :: Text)
            |> fetch
    let keepaliveDueConnections = filter (xeroConnectionDueForKeepalive keepaliveDueBefore) activeConnections
    let referenceSyncDueConnections = filter (xeroConnectionDueForReferenceSync referenceSyncDueBefore) activeConnections
    keepaliveResults <- forM keepaliveDueConnections enqueueXeroConnectionKeepaliveJob
    referenceSyncResults <- forM referenceSyncDueConnections (requestXeroReferenceSyncJob Nothing)
    pure XeroKeepaliveSweepSummary
        { dueConnectionCount = length keepaliveDueConnections
        , enqueuedJobCount = countEnqueuedJobs keepaliveResults
        , existingJobCount = countExistingJobs keepaliveResults
        , referenceSyncDueConnectionCount = length referenceSyncDueConnections
        , referenceSyncEnqueuedJobCount = countEnqueuedJobs referenceSyncResults
        , referenceSyncExistingJobCount = countExistingJobs referenceSyncResults
        }

xeroConnectionDueForKeepalive :: UTCTime -> XeroConnection -> Bool
xeroConnectionDueForKeepalive dueBefore connection =
    case connection.lastRefreshedAt of
        Nothing              -> True
        Just lastRefreshedAt -> lastRefreshedAt <= dueBefore

xeroConnectionDueForReferenceSync :: UTCTime -> XeroConnection -> Bool
xeroConnectionDueForReferenceSync dueBefore connection =
    case connection.lastSyncAt of
        Nothing         -> True
        Just lastSyncAt -> lastSyncAt <= dueBefore

countEnqueuedJobs :: [EnqueueAppJobResult] -> Int
countEnqueuedJobs results =
    length [ () | EnqueuedAppJob _ <- results ]

countExistingJobs :: [EnqueueAppJobResult] -> Int
countExistingJobs results =
    length [ () | ExistingActiveAppJob _ <- results ]

enqueueXeroConnectionKeepaliveJob ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO EnqueueAppJobResult
enqueueXeroConnectionKeepaliveJob connection =
    enqueueAppJob
        AppJobRequest
            { jobKind = xeroConnectionKeepaliveJobKind
            , payload =
                Aeson.object
                    [ "xeroConnectionId" Aeson..= tshow connection.id
                    , "tenantId" Aeson..= connection.tenantId
                    ]
            , payloadSchemaVersion = 1
            , requestedByUserId = Nothing
            , venueId = Just connection.venueId
            , relatedTable = Just "xero_connections"
            , relatedId = Just (unpackId connection.id)
            , dedupeKey = Just (xeroConnectionKeepaliveDedupeKey connection)
            , runAt = Nothing
            }

performXeroConnectionKeepaliveJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performXeroConnectionKeepaliveJob appJob =
    case appJob.relatedId of
        Nothing ->
            fail "Xero keepalive job is missing related xero connection id."
        Just connectionUuid -> do
            maybeConnection <- fetchOneOrNothing (Id connectionUuid :: Id XeroConnection)
            case maybeConnection of
                Nothing ->
                    completeKeepaliveJob appJob (Aeson.object ["skipped" Aeson..= ("missing_connection" :: Text)])
                Just connection
                    | connection.connectionStatus /= "active" ->
                        completeKeepaliveJob appJob (Aeson.object ["skipped" Aeson..= ("inactive_connection" :: Text)])
                    | otherwise -> do
                        now <- getCurrentTime
                        acquired <- acquireXeroReferenceSyncLease now appJob connection.tenantId
                        unless acquired (fail "Another Xero job is already refreshing credentials for this tenant.")
                        Exception.finally
                            (do
                                refreshedConnection <- fetch connection.id
                                if refreshedConnection.connectionStatus /= "active" || refreshedConnection.tenantId /= connection.tenantId
                                    then completeKeepaliveJob appJob (Aeson.object ["skipped" Aeson..= ("connection_changed" :: Text)])
                                    else performLeasedXeroConnectionKeepaliveJob appJob refreshedConnection
                            )
                            (releaseXeroReferenceSyncLease appJob connection.tenantId)

performLeasedXeroConnectionKeepaliveJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    XeroConnection ->
    IO ()
performLeasedXeroConnectionKeepaliveJob appJob connection =
    readXeroConfig >>= \case
        Left message -> fail (cs message)
        Right xeroConfig -> do
            refreshResult <- forceRefreshXeroConnectionAccess xeroConfig connection
            case refreshResult of
                Right (updatedConnection, _) -> do
                    _ <- invalidateXeroKeepaliveConnection updatedConnection "xero.connection.keepalive.refresh"
                    completeKeepaliveJob appJob
                        (Aeson.object
                            [ "xeroConnectionId" Aeson..= tshow updatedConnection.id
                            , "tenantId" Aeson..= updatedConnection.tenantId
                            , "refreshed" Aeson..= True
                            ]
                        )
                Left message -> do
                    latestConnection <- fetch connection.id
                    if latestConnection.connectionStatus == "reauthorization_required"
                        then do
                            _ <- invalidateXeroKeepaliveConnection latestConnection "xero.connection.keepalive.reauthorization_required"
                            completeKeepaliveJob appJob
                                ( Aeson.object
                                    [ "xeroConnectionId" Aeson..= tshow latestConnection.id
                                    , "tenantId" Aeson..= latestConnection.tenantId
                                    , "refreshed" Aeson..= False
                                    , "reauthorizationRequired" Aeson..= True
                                    , "message" Aeson..= message
                                    ]
                                )
                        else fail (cs message)

invalidateXeroKeepaliveConnection :: (?modelContext :: ModelContext) => XeroConnection -> Text -> IO (LiveMutationResult XeroConnection)
invalidateXeroKeepaliveConnection connection label =
    publishTouchedResourcesWithoutContext label $
        liveMutationResult connection [xeroConnectionResource connection.venueId]

completeKeepaliveJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Aeson.Value ->
    IO ()
completeKeepaliveJob appJob resultPayload =
    void
        ( appJob
            |> set #result resultPayload
            |> set #status JobStatusSucceeded
            |> updateRecord
        )
