module Application.Xero.Keepalive
    ( XeroKeepaliveSweepSummary (..)
    , enqueueDueXeroKeepaliveJobs
    , performXeroConnectionKeepaliveJob
    , xeroConnectionKeepaliveDedupeKey
    , xeroConnectionKeepaliveJobKind
    ) where

import Application.Async.Queue
import Application.Helper.SurfaceResource
import Application.Helper.Xero
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text.IO as TextIO
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import Web.SurfaceInvalidation (invalidateTouchedResourcesWithoutContext)

data XeroKeepaliveSweepSummary = XeroKeepaliveSweepSummary
    { dueConnectionCount :: !Int
    , enqueuedJobCount   :: !Int
    , existingJobCount   :: !Int
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
enqueueDueXeroKeepaliveJobs = do
    now <- getCurrentTime
    let dueBefore = addUTCTime (negate (7 * 24 * 60 * 60)) now
    activeConnections <-
        query @XeroConnection
            |> filterWhere (#connectionStatus, "active" :: Text)
            |> fetch
    let dueConnections = filter (xeroConnectionDueForKeepalive dueBefore) activeConnections
    results <- forM dueConnections enqueueXeroConnectionKeepaliveJob
    let enqueuedCount = length [ () | EnqueuedAppJob _ <- results ]
    let existingCount = length [ () | ExistingActiveAppJob _ <- results ]
    pure XeroKeepaliveSweepSummary
        { dueConnectionCount = length dueConnections
        , enqueuedJobCount = enqueuedCount
        , existingJobCount = existingCount
        }

xeroConnectionDueForKeepalive :: UTCTime -> XeroConnection -> Bool
xeroConnectionDueForKeepalive dueBefore connection =
    case connection.lastRefreshedAt of
        Nothing              -> True
        Just lastRefreshedAt -> lastRefreshedAt <= dueBefore

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
                    | otherwise ->
                        readXeroConfig >>= \case
                            Left message -> fail (cs message)
                            Right xeroConfig -> do
                                refreshResult <- refreshXeroConnectionAccess xeroConfig connection
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

invalidateXeroKeepaliveConnection :: XeroConnection -> Text -> IO (LiveMutationResult XeroConnection)
invalidateXeroKeepaliveConnection connection label =
    invalidateTouchedResourcesWithoutContext label $
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
