module Web.Admin.Xero.Mutations
    ( assignXeroRemoteConnectionIdMutation
    , completeLocalXeroDisconnectMutation
    , completeXeroConnectionMutation
    , consumeXeroOAuthStateMutation
    , failXeroConnectionAttemptMutation
    , importXeroEarningsRatesMutation
    , markXeroConnectionErrorMutation
    , startXeroConnectionMutation
    , applyXeroTimesheetPreparationStaffDecisionMutation
    , approveXeroTimesheetPreparationPayItemsMutation
    , approveXeroTimesheetPreparationStaffStepMutation
    , previewXeroTimesheetPreparationMutation
    , refreshXeroTimesheetPreparationMutation
    , runXeroTimesheetPreparationMutation
    , selectXeroTimesheetPreparationPeriodMutation
    , syncXeroReferenceDataMutation
    , submitXeroTimesheetPreparationMutation
    , xeroConnectionTouchedResources
    , xeroPayItemsTouchedResources
    , xeroReferenceSyncTouchedResources
    , xeroTimesheetsTouchedResources
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.SurfaceResource
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import qualified Application.Xero.Admin.ImportedPayItems as ImportedPayItems
import Application.Xero.Admin.ReferenceData
import Application.Xero.ReferenceSyncJob (enqueueXeroReferenceSyncJob)
import Application.Xero.ReferenceSyncRequest
import qualified Application.Xero.Timesheets.Prepare as XeroPrepare
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

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
            XeroConnectionStartedAudit
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

completeLocalXeroDisconnectMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> Maybe Text -> Text -> UTCTime -> IO (LiveMutationResult XeroConnection)
completeLocalXeroDisconnectMutation connection maybeRemoteConnectionId remoteDisconnectStatus now = do
    let retainedRemoteConnectionId = case maybeRemoteConnectionId of
            Just remoteConnectionId -> Just remoteConnectionId
            Nothing                 -> connection.xeroConnectionRemoteId
    updated <- withTransaction do
        updated <-
            connection
                |> set #connectionStatus "disconnected"
                |> set #disconnectedByUserId (Just (unpackId currentUser.id))
                |> set #disconnectedAt (Just now)
                |> set #encryptedAccessToken Nothing
                |> set #xeroConnectionRemoteId retainedRemoteConnectionId
                |> set #lastError Nothing
                |> updateRecord
        staleConnections <-
            query @XeroConnection
                |> filterWhere (#venueId, updated.venueId)
                |> filterWhereIn (#connectionStatus, ["active" :: Text, "reauthorization_required", "error"])
                |> filterWhereNot (#id, updated.id)
                |> fetch
        forM_ staleConnections \staleConnection ->
            staleConnection
                |> set #connectionStatus "disconnected"
                |> set #disconnectedByUserId (Just (unpackId currentUser.id))
                |> set #disconnectedAt (Just now)
                |> set #encryptedAccessToken Nothing
                |> set #lastError (Just "Superseded by local disconnect")
                |> updateRecord
                |> void
        void $
            recordCurrentUserAuditEvent
                XeroConnectionDisconnectedAudit
                "xero_connections"
                (unpackId updated.id)
                ( Aeson.object
                    [ "tenantId" Aeson..= updated.tenantId
                    , "tenantName" Aeson..= updated.tenantName
                    , "xeroConnectionId" Aeson..= retainedRemoteConnectionId
                    , "remoteDisconnect" Aeson..= remoteDisconnectStatus
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
        currentConnections <-
            query @XeroConnection
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhereIn (#connectionStatus, ["active" :: Text, "reauthorization_required", "error"])
                |> fetch
        forM_ currentConnections \connection ->
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
        void $ enqueueXeroReferenceSyncJob (Just actorUserId) connection
        void $
            recordCurrentUserAuditEvent
                XeroConnectionCompletedAudit
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
            XeroConnectionFailedAudit
            "xero_connections"
            (maybe (unpackId currentVenueId) (unpackId . (.id)) maybeState)
            ( Aeson.object
                [ "failure" Aeson..= message
                , "stateId" Aeson..= fmap (unpackId . (.id)) maybeState
                ]
            )
    invalidateTouchedResources "xero.connection.fail" $
        liveMutationResult () (xeroConnectionTouchedResources currentVenueId)

importXeroEarningsRatesMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> [Text] -> IO (LiveMutationResult [XeroImportedPayItem])
importXeroEarningsRatesMutation connection now fetchedRates selectedRateIds = do
    imported <- withTransaction do
        forM_ fetchedRates (upsertXeroEarningsRate connection now)
        ImportedPayItems.importXeroEarningsRates connection now fetchedRates selectedRateIds
    invalidateTouchedResources "xero.pay_items.import" (liveMutationResult imported (xeroPayItemsTouchedResources currentVenueId))

syncXeroReferenceDataMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => XeroConnection -> IO (LiveMutationResult (Either Text XeroReferenceDataSyncResult))
syncXeroReferenceDataMutation connection = do
    result <- runXeroReferenceDataSyncRequest (Just currentUser.id) connection
    invalidateTouchedResources "xero.reference_sync" $
        liveMutationResult result (xeroReferenceSyncTouchedResources currentVenueId)

-- Xero timesheet service modules own their internal writes; this wrapper owns passive invalidation.
recordXeroTimesheetsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> a -> IO (LiveMutationResult a)
recordXeroTimesheetsMutation label value =
    invalidateTouchedResources label $
        liveMutationResult value xeroTimesheetsTouchedResources

runXeroTimesheetPreparationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
runXeroTimesheetPreparationMutation =
    XeroPrepare.startXeroTimesheetPreparation >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.start"

refreshXeroTimesheetPreparationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
refreshXeroTimesheetPreparationMutation runId =
    XeroPrepare.refreshXeroTimesheetPreparation runId >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.refresh"

selectXeroTimesheetPreparationPeriodMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> Text -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
selectXeroTimesheetPreparationPeriodMutation runId selectedPeriodKey =
    XeroPrepare.selectXeroTimesheetPreparationPeriod runId selectedPeriodKey >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.period_select"

applyXeroTimesheetPreparationStaffDecisionMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> Id Staff -> XeroPrepare.XeroPreparationStaffDecision -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
applyXeroTimesheetPreparationStaffDecisionMutation runId staffId decision =
    XeroPrepare.applyXeroPreparationStaffDecision runId staffId decision >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.staff_decision"

approveXeroTimesheetPreparationPayItemsMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> Maybe Text -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
approveXeroTimesheetPreparationPayItemsMutation runId maybeAccountCode =
    XeroPrepare.approveXeroPreparationPayItemDecisions runId maybeAccountCode >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.pay_items_approve"

approveXeroTimesheetPreparationStaffStepMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
approveXeroTimesheetPreparationStaffStepMutation runId =
    XeroPrepare.approveXeroPreparationStaffStep runId >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.staff_approve"

previewXeroTimesheetPreparationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
previewXeroTimesheetPreparationMutation runId =
    XeroPrepare.previewXeroTimesheetPreparation runId >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.preview"

submitXeroTimesheetPreparationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id XeroTimesheetPreparationRun -> Maybe Text -> IO (LiveMutationResult (Either Text XeroTimesheetPreparationView))
submitXeroTimesheetPreparationMutation runId maybeAccountCode =
    XeroPrepare.submitXeroTimesheetPreparation runId maybeAccountCode >>= recordXeroTimesheetsMutation "xero.timesheets.preparation.submit"

xeroConnectionTouchedResources :: Id Venue -> [SurfaceResourceValue]
xeroConnectionTouchedResources venueId =
    [xeroConnectionResource (unpackId venueId)]

xeroPayItemsTouchedResources :: Id Venue -> [SurfaceResourceValue]
xeroPayItemsTouchedResources venueId =
    [adminShiftTypesResource (unpackId venueId)]

-- Guided preparation is dialog-local and no registered live fragment depends
-- on a Xero-timesheet resource. Keep this empty instead of emitting the retired
-- undeclared sentinel, which never selected an actor or passive target.
xeroTimesheetsTouchedResources :: [SurfaceResourceValue]
xeroTimesheetsTouchedResources = []

xeroReferenceSyncTouchedResources :: Id Venue -> [SurfaceResourceValue]
xeroReferenceSyncTouchedResources venueId =
    [xeroConnectionResource (unpackId venueId)]
