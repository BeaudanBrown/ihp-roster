module Application.Xero.Admin.Connection
    ( disconnectXeroConnectionAction
    , startXeroConnectionAction
    , xeroOAuthCallbackAction
    ) where

import Application.Helper.Xero
import Application.Xero.Admin.ReadModel
import Application.Xero.Admin.Responses
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Controller.Prelude

startXeroConnectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
startXeroConnectionAction =
    requireCurrentVenueOwnerForXero do
        readXeroConfig >>= \case
            Left message -> do
                setErrorMessage message
                redirectTo XeroAction
            Right xeroConfig -> do
                now <- getCurrentTime
                stateToken <- generateXeroStateToken
                oauthState <- newRecord @XeroOauthState
                    |> set #venueId (unpackId currentVenueId)
                    |> set #userId (unpackId currentUser.id)
                    |> set #stateToken stateToken
                    |> set #requestedScopes requiredXeroScopesText
                    |> set #redirectUri xeroConfig.redirectUri
                    |> set #expiresAt (addUTCTime (15 * 60) now)
                    |> createRecord
                void $ recordCurrentUserAuditEvent
                    "xero_connection_started"
                    "xero_oauth_states"
                    (unpackId oauthState.id)
                    (Aeson.object
                        [ "scopes" Aeson..= requiredXeroScopes
                        , "redirectUri" Aeson..= xeroConfig.redirectUri
                        ]
                    )
                redirectToUrl (buildXeroAuthorizationUrl xeroConfig stateToken)

xeroOAuthCallbackAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
xeroOAuthCallbackAction =
    requireCurrentVenueOwnerForXero do
        now <- getCurrentTime
        let maybeStateToken = paramOrNothing @Text "state"
        let maybeXeroError = paramOrNothing @Text "error"
        let maybeCode = paramOrNothing @Text "code"
        validatedState <- validateXeroOAuthState now currentUser.id maybeStateToken
        case validatedState of
            Left message -> failXeroConnectionAttempt message Nothing
            Right oauthState ->
                case maybeXeroError of
                    Just xeroError -> do
                        markXeroOAuthStateConsumed oauthState now
                        failXeroConnectionAttempt ("Xero authorization failed: " <> xeroError) (Just oauthState)
                    Nothing ->
                        case maybeCode of
                            Nothing -> failXeroConnectionAttempt "Xero did not return an authorization code." (Just oauthState)
                            Just code -> completeXeroOAuthCallback now currentUser.id oauthState code

disconnectXeroConnectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
disconnectXeroConnectionAction =
    requireCurrentVenueOwnerForXero do
        maybeConnection <- fetchCurrentVenueXeroConnection
        case maybeConnection of
            Nothing -> do
                setErrorMessage "Xero is not connected for this venue."
                redirectTo XeroAction
            Just connection ->
                disconnectXeroConnection connection

disconnectXeroConnection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO ()
disconnectXeroConnection connection = do
    readXeroConfig >>= \case
        Left message -> do
            setErrorMessage message
            redirectTo XeroAction
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccess xeroConfig connection
            case refreshResult of
                Left message -> do
                    setErrorMessage message
                    redirectTo XeroAction
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    remoteIdResult <- resolveXeroRemoteConnectionId xeroClient refreshedConnection accessToken
                    case remoteIdResult of
                        Left message -> do
                            markXeroConnectionError refreshedConnection message
                            setErrorMessage message
                            redirectTo XeroAction
                        Right remoteConnectionId -> do
                            deleteResult <- deleteXeroConnection xeroClient accessToken remoteConnectionId
                            case deleteResult of
                                Left err -> do
                                    let message = "Xero disconnect failed: " <> xeroClientErrorText err
                                    markXeroConnectionError refreshedConnection message
                                    setErrorMessage message
                                    redirectTo XeroAction
                                Right () -> completeLocalXeroDisconnect refreshedConnection remoteConnectionId

completeLocalXeroDisconnect ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    IO ()
completeLocalXeroDisconnect connection remoteConnectionId = do
    now <- getCurrentTime
    updatedConnection <- withTransaction do
        updated <- connection
            |> set #connectionStatus "disconnected"
            |> set #disconnectedByUserId (Just (unpackId currentUser.id))
            |> set #disconnectedAt (Just now)
            |> set #encryptedAccessToken Nothing
            |> set #xeroConnectionRemoteId (Just remoteConnectionId)
            |> set #lastError Nothing
            |> updateRecord
        void $ recordCurrentUserAuditEvent
            "xero_connection_disconnected"
            "xero_connections"
            (unpackId updated.id)
            (Aeson.object
                [ "tenantId" Aeson..= updated.tenantId
                , "tenantName" Aeson..= updated.tenantName
                , "xeroConnectionId" Aeson..= remoteConnectionId
                ]
            )
        pure updated
    broadcastAdminXeroInvalidation currentVenueId
    setSuccessMessage ("Disconnected Xero tenant " <> fromMaybe updatedConnection.tenantId updatedConnection.tenantName <> ".")
    redirectTo XeroAction

resolveXeroRemoteConnectionId ::
    (?modelContext :: ModelContext) =>
    XeroClient ->
    XeroConnection ->
    Text ->
    IO (Either Text Text)
resolveXeroRemoteConnectionId xeroClient connection accessToken =
    case connection.xeroConnectionRemoteId of
        Just remoteConnectionId -> pure (Right remoteConnectionId)
        Nothing -> do
            tenantsResult <- fetchConnectedTenants xeroClient accessToken
            case tenantsResult of
                Left err -> pure (Left ("Could not look up Xero connections before disconnecting: " <> xeroClientErrorText err))
                Right tenants ->
                    case List.find (\tenant -> tenant.tenantId == connection.tenantId) tenants of
                        Nothing -> pure (Left "Could not find the linked Xero organisation in Xero. The connection may already be disconnected.")
                        Just tenant -> do
                            _ <- connection
                                |> set #xeroConnectionRemoteId (Just tenant.xeroConnectionId)
                                |> updateRecord
                            pure (Right tenant.xeroConnectionId)

validateXeroOAuthState ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UTCTime ->
    Id User ->
    Maybe Text ->
    IO (Either Text XeroOauthState)
validateXeroOAuthState _ _ Nothing =
    pure (Left "Xero did not return OAuth state. Start the connection again.")
validateXeroOAuthState now actorUserId (Just stateToken) = do
    maybeState <-
        query @XeroOauthState
            |> filterWhere (#stateToken, stateToken)
            |> fetchOneOrNothing
    pure case maybeState of
        Nothing -> Left "Xero OAuth state is invalid. Start the connection again."
        Just oauthState
            | oauthState.venueId /= unpackId currentVenueId ->
                Left "Xero OAuth state does not match the current venue. Start the connection again."
            | oauthState.userId /= unpackId actorUserId ->
                Left "Xero OAuth state does not match the current user. Start the connection again."
            | isJust oauthState.consumedAt ->
                Left "Xero OAuth state has already been used. Start the connection again."
            | oauthState.expiresAt <= now ->
                Left "Xero OAuth state has expired. Start the connection again."
            | otherwise -> Right oauthState

completeXeroOAuthCallback ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    UTCTime ->
    Id User ->
    XeroOauthState ->
    Text ->
    IO ()
completeXeroOAuthCallback now actorUserId oauthState code =
    readXeroConfig >>= \case
        Left message -> failXeroConnectionAttempt message (Just oauthState)
        Right xeroConfig -> do
            xeroClient <- currentXeroClient
            tokenResult <- exchangeCodeForToken xeroClient xeroConfig code
            case tokenResult of
                Left err -> do
                    markXeroOAuthStateConsumed oauthState now
                    failXeroConnectionAttempt ("Xero token exchange failed: " <> xeroClientErrorText err) (Just oauthState)
                Right tokenResponse -> do
                    tenantsResult <- fetchConnectedTenants xeroClient tokenResponse.accessToken
                    case tenantsResult of
                        Left err -> do
                            markXeroOAuthStateConsumed oauthState now
                            failXeroConnectionAttempt ("Xero tenant lookup failed: " <> xeroClientErrorText err) (Just oauthState)
                        Right [] -> do
                            markXeroOAuthStateConsumed oauthState now
                            failXeroConnectionAttempt "Xero returned no connected tenants." (Just oauthState)
                        Right tenants -> do
                            tenant <- chooseXeroTenantForOAuth tenants
                            connection <- persistCompletedXeroConnection now actorUserId xeroConfig oauthState tokenResponse tenant
                            setSuccessMessage ("Connected Xero tenant " <> fromMaybe connection.tenantId connection.tenantName <> ".")
                            redirectTo XeroAction

persistCompletedXeroConnection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    UTCTime ->
    Id User ->
    XeroConfig ->
    XeroOauthState ->
    XeroTokenResponse ->
    XeroTenant ->
    IO XeroConnection
persistCompletedXeroConnection now actorUserId xeroConfig oauthState tokenResponse tenant = do
    encryptedRefreshToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.refreshToken
    encryptedAccessToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.accessToken
    let accessTokenExpiresAt = addUTCTime (fromIntegral tokenResponse.expiresIn) now
    withTransaction do
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
        updatedState <- oauthState
            |> set #consumedAt (Just now)
            |> updateRecord
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
                Nothing       -> fillConnection (newRecord @XeroConnection) |> createRecord
        void $ recordCurrentUserAuditEvent
            "xero_connection_completed"
            "xero_connections"
            (unpackId connection.id)
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "tenantName" Aeson..= connection.tenantName
                , "xeroConnectionId" Aeson..= connection.xeroConnectionRemoteId
                , "scopes" Aeson..= connection.scopes
                , "stateId" Aeson..= unpackId updatedState.id
                ]
            )
        pure connection

chooseXeroTenantForOAuth ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [XeroTenant] ->
    IO XeroTenant
chooseXeroTenantForOAuth tenants = do
    existingConnection <- fetchCurrentVenueXeroConnection
    pure case (existingConnection >>= \connection -> List.find (\tenant -> tenant.tenantId == connection.tenantId) tenants, tenants) of
        (Just tenant, _) -> tenant
        (Nothing, tenant : _) -> tenant
        (Nothing, []) -> error "chooseXeroTenantForOAuth called without tenants"

markXeroOAuthStateConsumed ::
    (?modelContext :: ModelContext) =>
    XeroOauthState ->
    UTCTime ->
    IO XeroOauthState
markXeroOAuthStateConsumed oauthState now =
    oauthState
        |> set #consumedAt (Just now)
        |> updateRecord

failXeroConnectionAttempt ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Maybe XeroOauthState ->
    IO ()
failXeroConnectionAttempt message maybeState = do
    void $ recordCurrentUserAuditEvent
        "xero_connection_failed"
        "xero_connections"
        (maybe (unpackId currentVenueId) (unpackId . (.id)) maybeState)
        (Aeson.object
            [ "failure" Aeson..= message
            , "stateId" Aeson..= fmap (unpackId . (.id)) maybeState
            ]
        )
    setErrorMessage message
    redirectTo XeroAction
