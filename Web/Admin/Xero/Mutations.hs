module Web.Admin.Xero.Mutations
    ( assignXeroRemoteConnectionIdMutation
    , completeLocalXeroDisconnectMutation
    , completeXeroConnectionMutation
    , completeXeroPayItemSyncMutation
    , completeXeroReferenceSyncMutation
    , consumeXeroOAuthStateMutation
    , createRunningXeroPayItemSyncRunMutation
    , failXeroPayItemSyncMutation
    , failXeroConnectionAttemptMutation
    , failXeroReferenceSyncMutation
    , markXeroConnectionErrorMutation
    , startXeroConnectionMutation
    , startXeroReferenceSyncMutation
    , xeroConnectionTouchedResources
    , xeroPayItemsTouchedResources
    , xeroReferenceSyncTouchedResources
    ) where

import Application.Helper.LiveResource
import Application.Helper.Xero
import Application.Xero.Admin.ReferenceData
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

startXeroConnectionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConfig -> UTCTime -> Text -> IO (LiveMutationResult XeroOauthState)
startXeroConnectionMutation xeroConfig now stateToken = do
    oauthState <-
        newRecord @XeroOauthState
            |> set #venueId (unpackId currentVenueId)
            |> set #userId (unpackId currentUser.id)
            |> set #stateToken stateToken
            |> set #requestedScopes requiredXeroScopesText
            |> set #redirectUri xeroConfig.redirectUri
            |> set #expiresAt (addUTCTime (15 * 60) now)
            |> createRecord
    void $
        recordCurrentUserAuditEvent
            "xero_connection_started"
            "xero_oauth_states"
            (unpackId oauthState.id)
            ( Aeson.object
                [ "scopes" Aeson..= requiredXeroScopes
                , "redirectUri" Aeson..= xeroConfig.redirectUri
                ]
            )
    invalidateTouchedResources "xero.connection.start" $
        liveMutationResult oauthState (xeroConnectionTouchedResources currentVenueId)

consumeXeroOAuthStateMutation :: (?modelContext :: ModelContext) => XeroOauthState -> UTCTime -> IO XeroOauthState
consumeXeroOAuthStateMutation oauthState now =
    oauthState
        |> set #consumedAt (Just now)
        |> updateRecord

completeLocalXeroDisconnectMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> Text -> UTCTime -> IO (LiveMutationResult XeroConnection)
completeLocalXeroDisconnectMutation connection remoteConnectionId now = do
    updated <- withTransaction do
        updated <-
            connection
                |> set #connectionStatus "disconnected"
                |> set #disconnectedByUserId (Just (unpackId currentUser.id))
                |> set #disconnectedAt (Just now)
                |> set #encryptedAccessToken Nothing
                |> set #xeroConnectionRemoteId (Just remoteConnectionId)
                |> set #lastError Nothing
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_connection_disconnected"
                "xero_connections"
                (unpackId updated.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= updated.tenantId
                    , "tenantName" Aeson..= updated.tenantName
                    , "xeroConnectionId" Aeson..= remoteConnectionId
                    ]
                )
        pure updated
    invalidateTouchedResources "xero.connection.disconnect" $
        liveMutationResult updated (xeroConnectionTouchedResources (Id updated.venueId))

assignXeroRemoteConnectionIdMutation :: (?modelContext :: ModelContext) => XeroConnection -> Text -> IO XeroConnection
assignXeroRemoteConnectionIdMutation connection remoteConnectionId =
    connection
        |> set #xeroConnectionRemoteId (Just remoteConnectionId)
        |> updateRecord

markXeroConnectionErrorMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> Text -> IO (LiveMutationResult XeroConnection)
markXeroConnectionErrorMutation connection message = do
    updated <-
        connection
            |> set #connectionStatus "error"
            |> set #lastError (Just message)
            |> updateRecord
    invalidateTouchedResources "xero.connection.error" $
        liveMutationResult updated (xeroConnectionTouchedResources (Id updated.venueId))

completeXeroConnectionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UTCTime -> Id User -> XeroConfig -> XeroOauthState -> XeroTokenResponse -> XeroTenant -> IO (LiveMutationResult XeroConnection)
completeXeroConnectionMutation now actorUserId xeroConfig oauthState tokenResponse tenant = do
    encryptedRefreshToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.refreshToken
    encryptedAccessToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.accessToken
    let accessTokenExpiresAt = addUTCTime (fromIntegral tokenResponse.expiresIn) now
    connection <- withTransaction do
        existingSameTenant <-
            query @XeroConnection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#tenantId, tenant.tenantId)
                |> orderByDesc #connectedAt
                |> fetchOneOrNothing
        activeConnections <-
            query @XeroConnection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#connectionStatus, "active" :: Text)
                |> fetch
        forM_ activeConnections \connection ->
            when (Just connection.id /= ((.id) <$> existingSameTenant)) do
                connection
                    |> set #connectionStatus "disconnected"
                    |> set #disconnectedByUserId (Just (unpackId actorUserId))
                    |> set #disconnectedAt (Just now)
                    |> set #lastError (Just "Superseded by reconnect")
                    |> updateRecord
                    |> void
        updatedState <- consumeXeroOAuthStateMutation oauthState now
        let fillConnection record =
                record
                    |> set #venueId (unpackId currentVenueId)
                    |> set #tenantId tenant.tenantId
                    |> set #tenantName tenant.tenantName
                    |> set #xeroConnectionRemoteId (Just tenant.xeroConnectionId)
                    |> set #connectionStatus ("active" :: Text)
                    |> set #scopes (fromMaybe updatedState.requestedScopes tokenResponse.scope)
                    |> set #encryptedRefreshToken encryptedRefreshToken
                    |> set #encryptedAccessToken (Just encryptedAccessToken)
                    |> set #accessTokenExpiresAt (Just accessTokenExpiresAt)
                    |> set #lastRefreshedAt (Just now)
                    |> set #lastError Nothing
                    |> set #connectedByUserId (Just (unpackId actorUserId))
                    |> set #connectedAt now
                    |> set #disconnectedByUserId Nothing
                    |> set #disconnectedAt Nothing
        connection <-
            case existingSameTenant of
                Just existing -> fillConnection existing |> updateRecord
                Nothing -> fillConnection (newRecord @XeroConnection) |> createRecord
        void $
            recordCurrentUserAuditEvent
                "xero_connection_completed"
                "xero_connections"
                (unpackId connection.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "tenantName" Aeson..= connection.tenantName
                    , "xeroConnectionId" Aeson..= connection.xeroConnectionRemoteId
                    , "scopes" Aeson..= connection.scopes
                    , "stateId" Aeson..= unpackId updatedState.id
                    ]
                )
        pure connection
    invalidateTouchedResources "xero.connection.complete" $
        liveMutationResult connection (xeroConnectionTouchedResources currentVenueId)

failXeroConnectionAttemptMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Maybe XeroOauthState -> IO (LiveMutationResult ())
failXeroConnectionAttemptMutation message maybeState = do
    void $
        recordCurrentUserAuditEvent
            "xero_connection_failed"
            "xero_connections"
            (maybe (unpackId currentVenueId) (unpackId . (.id)) maybeState)
            ( Aeson.object
                [ "failure" Aeson..= message
                , "stateId" Aeson..= fmap (unpackId . (.id)) maybeState
                ]
            )
    invalidateTouchedResources "xero.connection.fail" $
        liveMutationResult () (xeroConnectionTouchedResources currentVenueId)

createRunningXeroPayItemSyncRunMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> IO (LiveMutationResult XeroSyncRun)
createRunningXeroPayItemSyncRunMutation connection now = do
    syncRun <- newRecord @XeroSyncRun
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("running" :: Text)
        |> set #syncKind ("pay_item_create" :: Text)
        |> set #startedAt now
        |> createRecord
    invalidateTouchedResources "xero.pay_items.sync.start" (liveMutationResult syncRun (xeroPayItemsTouchedResources (Id connection.venueId)))

completeXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> IO (LiveMutationResult XeroSyncRun)
completeXeroPayItemSyncMutation syncRun verifiedCount = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("succeeded" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #finishedAt (Just now)
        |> updateRecord
    invalidateTouchedResources "xero.pay_items.sync.complete" (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

failXeroPayItemSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> Int -> Text -> IO (LiveMutationResult XeroSyncRun)
failXeroPayItemSyncMutation syncRun verifiedCount message = do
    now <- getCurrentTime
    updated <- syncRun
        |> set #syncStatus ("failed" :: Text)
        |> set #earningsRatesCount verifiedCount
        |> set #errorMessage (Just message)
        |> set #finishedAt (Just now)
        |> updateRecord
    invalidateTouchedResources "xero.pay_items.sync.fail" (liveMutationResult updated (xeroPayItemsTouchedResources currentVenueId))

startXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> IO (LiveMutationResult XeroSyncRun)
startXeroReferenceSyncMutation connection now = do
    syncRun <-
        newRecord @XeroSyncRun
            |> set #venueId connection.venueId
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #syncStatus ("running" :: Text)
            |> set #syncKind ("payroll_reference_data" :: Text)
            |> set #startedAt now
            |> createRecord
    invalidateTouchedResources "xero.reference_sync.start" $
        liveMutationResult syncRun (xeroReferenceSyncTouchedResources (Id connection.venueId))

completeXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> XeroConnection -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> IO (LiveMutationResult XeroSyncRun)
completeXeroReferenceSyncMutation syncRun connection employees earningsRates payrollCalendars = do
    now <- getCurrentTime
    updated <- withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection connection earningsRates
        reconcileXeroPayrollCalendarSelection connection payrollCalendars
        updatedSyncRun <-
            syncRun
                |> set #syncStatus ("succeeded" :: Text)
                |> set #employeesCount (length employees)
                |> set #earningsRatesCount (length earningsRates)
                |> set #payrollCalendarsCount (length payrollCalendars)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            connection
                |> set #lastSyncAt (Just now)
                |> set #lastError Nothing
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_succeeded"
                "xero_sync_runs"
                (unpackId syncRun.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "employeesCount" Aeson..= length employees
                    , "earningsRatesCount" Aeson..= length earningsRates
                    , "payrollCalendarsCount" Aeson..= length payrollCalendars
                    ]
                )
        pure updatedSyncRun
    invalidateTouchedResources "xero.reference_sync.complete" $
        liveMutationResult updated (xeroReferenceSyncTouchedResources currentVenueId)

failXeroReferenceSyncMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroSyncRun -> XeroConnection -> Text -> IO (LiveMutationResult XeroSyncRun)
failXeroReferenceSyncMutation syncRun connection message = do
    now <- getCurrentTime
    updated <- withTransaction do
        latestConnection <- fetch connection.id
        updatedSyncRun <-
            syncRun
                |> set #syncStatus ("failed" :: Text)
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            latestConnection
                |> set #lastError (Just message)
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_failed"
                "xero_sync_runs"
                (unpackId syncRun.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "failure" Aeson..= message
                    ]
                )
        pure updatedSyncRun
    invalidateTouchedResources "xero.reference_sync.fail" $
        liveMutationResult updated (xeroReferenceSyncTouchedResources currentVenueId)

xeroConnectionTouchedResources :: Id Venue -> [LiveResource]
xeroConnectionTouchedResources venueId =
    [XeroConnectionResource (unpackId venueId)]

xeroPayItemsTouchedResources :: Id Venue -> [LiveResource]
xeroPayItemsTouchedResources venueId =
    [XeroPayItemsResource (unpackId venueId)]

xeroReferenceSyncTouchedResources :: Id Venue -> [LiveResource]
xeroReferenceSyncTouchedResources venueId =
    [ XeroConnectionResource (unpackId venueId)
    , XeroMappingsResource (unpackId venueId)
    ]
