module Web.Controller.Admin.Xero.Connection
    ( disconnectXeroConnectionAction
    , redirectToXeroAuthorization
    , redirectToXeroAuthorizationForReferenceSync
    , startXeroConnectionAction
    , xeroOAuthCallbackAction
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.Xero
import Application.Xero.Admin.ReadModel
import Application.Xero.Connection
import qualified Data.List as List
import Web.Admin.Xero.Mutations (assignXeroRemoteConnectionIdMutation,
                                 completeLocalXeroDisconnectMutation,
                                 completeXeroConnectionMutation,
                                 consumeXeroOAuthStateMutation,
                                 failXeroConnectionAttemptMutation,
                                 markXeroConnectionErrorMutation,
                                 startXeroConnectionMutation)
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude

startXeroConnectionAction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
startXeroConnectionAction =
    requireCurrentVenueOwnerForXero do
        redirectToXeroAuthorization

redirectToXeroAuthorization :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
redirectToXeroAuthorization =
    redirectToXeroAuthorizationWithStateToken identityXeroStateToken

redirectToXeroAuthorizationForReferenceSync :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
redirectToXeroAuthorizationForReferenceSync =
    redirectToXeroAuthorization

redirectToXeroAuthorizationWithStateToken :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => (Text -> Text) -> IO ()
redirectToXeroAuthorizationWithStateToken stateTokenTransform =
    readXeroConfig >>= \case
        Left message -> do
            setErrorMessage message
            redirectTo XeroAction
        Right xeroConfig -> do
            now <- getCurrentTime
            stateToken <- stateTokenTransform <$> generateXeroStateToken
            _ <- startXeroConnectionMutation xeroConfig now stateToken
            redirectToXeroAuthorizationUrl (buildXeroAuthorizationUrl xeroConfig stateToken)

identityXeroStateToken :: Text -> Text
identityXeroStateToken stateToken =
    stateToken

redirectToXeroAuthorizationUrl :: (?context :: ControllerContext, ?request :: Request) => Text -> IO ()
redirectToXeroAuthorizationUrl authorizationUrl =
    if isHtmxRequest
        then do
            setHeader ("HX-Redirect", cs authorizationUrl)
            renderPlain ""
        else redirectToUrl authorizationUrl

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
                        _ <- consumeXeroOAuthStateMutation oauthState now
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
        Left _message ->
            completeLocalXeroDisconnect connection connection.xeroConnectionRemoteId "skipped_not_configured"
        Right xeroConfig -> do
            refreshResult <- refreshXeroConnectionAccessWithoutBroadcast xeroConfig connection
            case refreshResult of
                Left message -> do
                    latestConnection <- fetch connection.id
                    if latestConnection.connectionStatus == "reauthorization_required"
                        then completeLocalXeroDisconnect latestConnection latestConnection.xeroConnectionRemoteId "skipped_token_invalid"
                        else do
                            setErrorMessage message
                            redirectTo XeroAction
                Right (refreshedConnection, accessToken) -> do
                    xeroClient <- currentXeroClient
                    remoteIdResult <- resolveXeroRemoteConnectionId xeroClient refreshedConnection accessToken
                    case remoteIdResult of
                        Left message -> do
                            _ <- markXeroConnectionErrorMutation refreshedConnection message
                            completeLocalXeroDisconnect refreshedConnection refreshedConnection.xeroConnectionRemoteId "skipped_remote_id_missing"
                        Right remoteConnectionId -> do
                            deleteResult <- deleteXeroConnection xeroClient accessToken remoteConnectionId
                            case deleteResult of
                                Left err -> do
                                    let message = "Xero disconnect failed: " <> xeroClientErrorText err
                                    _ <- markXeroConnectionErrorMutation refreshedConnection message
                                    completeLocalXeroDisconnect refreshedConnection (Just remoteConnectionId) "failed"
                                Right () -> completeLocalXeroDisconnect refreshedConnection (Just remoteConnectionId) "succeeded"

completeLocalXeroDisconnect ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Maybe Text ->
    Text ->
    IO ()
completeLocalXeroDisconnect connection maybeRemoteConnectionId remoteDisconnectStatus = do
    now <- getCurrentTime
    updatedConnection <- liveMutationValue <$> completeLocalXeroDisconnectMutation connection maybeRemoteConnectionId remoteDisconnectStatus now
    setSuccessMessage (localDisconnectMessage updatedConnection remoteDisconnectStatus)
    redirectTo XeroAction

localDisconnectMessage :: XeroConnection -> Text -> Text
localDisconnectMessage connection remoteDisconnectStatus =
    let tenantLabel = fromMaybe connection.tenantId connection.tenantName
     in case remoteDisconnectStatus of
            "succeeded" -> "Disconnected Xero tenant " <> tenantLabel <> "."
            "skipped_token_invalid" -> "Disconnected Xero tenant " <> tenantLabel <> " locally. Xero token was already expired or invalid, so the remote Xero disconnect could not be called."
            "skipped_remote_id_missing" -> "Disconnected Xero tenant " <> tenantLabel <> " locally. The Xero connection identifier was unavailable, so the remote Xero disconnect could not be called."
            "skipped_not_configured" -> "Disconnected Xero tenant " <> tenantLabel <> " locally. Xero is not configured, so the remote Xero disconnect could not be called."
            "failed" -> "Disconnected Xero tenant " <> tenantLabel <> " locally. Xero-side revocation was not confirmed."
            _ -> "Disconnected Xero tenant " <> tenantLabel <> " locally."

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
                            _ <- assignXeroRemoteConnectionIdMutation connection tenant.xeroConnectionId
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
                    _ <- consumeXeroOAuthStateMutation oauthState now
                    failXeroConnectionAttempt ("Xero token exchange failed: " <> xeroClientErrorText err) (Just oauthState)
                Right tokenResponse -> do
                    tenantsResult <- fetchConnectedTenants xeroClient tokenResponse.accessToken
                    case tenantsResult of
                        Left err -> do
                            _ <- consumeXeroOAuthStateMutation oauthState now
                            failXeroConnectionAttempt ("Xero tenant lookup failed: " <> xeroClientErrorText err) (Just oauthState)
                        Right [] -> do
                            _ <- consumeXeroOAuthStateMutation oauthState now
                            failXeroConnectionAttempt "Xero returned no connected tenants." (Just oauthState)
                        Right tenants -> do
                            tenantResult <- chooseXeroTenantForOAuth tenants
                            case tenantResult of
                                Left message -> do
                                    _ <- consumeXeroOAuthStateMutation oauthState now
                                    failXeroConnectionAttempt message (Just oauthState)
                                Right tenant -> do
                                    connection <- liveMutationValue <$> completeXeroConnectionMutation now actorUserId xeroConfig oauthState tokenResponse tenant
                                    setSuccessMessage ("Connected Xero tenant " <> fromMaybe connection.tenantId connection.tenantName <> ".")
                                    redirectAfterCompletedXeroConnection oauthState

redirectAfterCompletedXeroConnection ::
    (?context :: ControllerContext, ?request :: Request) =>
    XeroOauthState ->
    IO ()
redirectAfterCompletedXeroConnection _oauthState =
    redirectTo XeroAction

chooseXeroTenantForOAuth ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [XeroTenant] ->
    IO (Either Text XeroTenant)
chooseXeroTenantForOAuth tenants = do
    existingConnection <- fetchCurrentVenueXeroConnection
    pure case existingConnection of
        Just connection ->
            case List.find (\tenant -> tenant.tenantId == connection.tenantId) tenants of
                Just tenant -> Right tenant
                Nothing -> Left ("Reconnect must authorize " <> fromMaybe connection.tenantId connection.tenantName <> ". Xero returned a different organisation; switch Xero account or disconnect locally first.")
        Nothing ->
            case tenants of
                tenant : _ -> Right tenant
                []         -> Left "Xero returned no connected tenants."

failXeroConnectionAttempt ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    Maybe XeroOauthState ->
    IO ()
failXeroConnectionAttempt message maybeState = do
    _ <- failXeroConnectionAttemptMutation message maybeState
    setErrorMessage message
    redirectTo XeroAction
