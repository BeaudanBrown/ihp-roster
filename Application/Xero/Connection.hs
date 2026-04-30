module Application.Xero.Connection
    ( isXeroRefreshTokenExpiredError
    , markXeroConnectionError
    , markXeroConnectionReauthorizationRequired
    , persistXeroRefreshedTokens
    , refreshXeroConnectionAccess
    , refreshXeroConnectionAccessWithoutBroadcast
    , xeroClientErrorText
    ) where

import qualified Application.Helper.LiveUpdate as LiveUpdate
import Application.Helper.Xero
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

xeroClientErrorText :: XeroClientError -> Text
xeroClientErrorText (XeroHttpError message) = message
xeroClientErrorText (XeroDecodeError message) = "Could not decode Xero response: " <> message
xeroClientErrorText XeroNoTenantsError = "Xero returned no connected tenants."

isXeroRefreshTokenExpiredError :: XeroClientError -> Bool
isXeroRefreshTokenExpiredError errorValue =
    let message = Text.toLower (xeroClientErrorText errorValue)
     in "invalid_grant" `Text.isInfixOf` message
        || "refresh token has expired" `Text.isInfixOf` message
        || "token has been expired" `Text.isInfixOf` message
        || "expired or revoked" `Text.isInfixOf` message

refreshXeroConnectionAccess ::
    (?modelContext :: ModelContext) =>
    XeroConfig ->
    XeroConnection ->
    IO (Either Text (XeroConnection, Text))
refreshXeroConnectionAccess xeroConfig connection =
    refreshXeroConnectionAccessWithBroadcast True xeroConfig connection

refreshXeroConnectionAccessWithoutBroadcast ::
    (?modelContext :: ModelContext) =>
    XeroConfig ->
    XeroConnection ->
    IO (Either Text (XeroConnection, Text))
refreshXeroConnectionAccessWithoutBroadcast xeroConfig connection =
    refreshXeroConnectionAccessWithBroadcast False xeroConfig connection

refreshXeroConnectionAccessWithBroadcast ::
    (?modelContext :: ModelContext) =>
    Bool ->
    XeroConfig ->
    XeroConnection ->
    IO (Either Text (XeroConnection, Text))
refreshXeroConnectionAccessWithBroadcast shouldBroadcast xeroConfig connection =
    case decryptXeroToken xeroConfig.tokenEncryptionKey connection.encryptedRefreshToken of
        Left message -> do
            let friendly = "Could not decrypt the stored Xero refresh token. Reconnect Xero to continue."
            markXeroConnectionReauthorizationRequiredWithBroadcast shouldBroadcast connection (friendly <> " " <> message)
            pure (Left friendly)
        Right refreshToken -> do
            xeroClient <- currentXeroClient
            now <- getCurrentTime
            refreshResult <- refreshXeroToken xeroClient xeroConfig refreshToken
            case refreshResult of
                Right tokenResponse -> do
                    updated <- persistXeroRefreshedTokens now xeroConfig connection tokenResponse
                    pure (Right (updated, tokenResponse.accessToken))
                Left err
                    | isXeroRefreshTokenExpiredError err -> do
                        let friendly = "Xero needs to be reconnected because the refresh token expired or was revoked."
                        markXeroConnectionReauthorizationRequiredWithBroadcast shouldBroadcast connection (friendly <> " " <> xeroClientErrorText err)
                        pure (Left friendly)
                    | otherwise -> do
                        let message = "Xero token refresh failed: " <> xeroClientErrorText err
                        markXeroConnectionErrorWithBroadcast shouldBroadcast connection message
                        pure (Left message)

persistXeroRefreshedTokens ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    XeroConfig ->
    XeroConnection ->
    XeroTokenResponse ->
    IO XeroConnection
persistXeroRefreshedTokens now xeroConfig connection tokenResponse = do
    encryptedRefreshToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.refreshToken
    encryptedAccessToken <- encryptXeroToken xeroConfig.tokenEncryptionKey tokenResponse.accessToken
    connection
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #encryptedAccessToken (Just encryptedAccessToken)
        |> set #accessTokenExpiresAt (Just (addUTCTime (fromIntegral tokenResponse.expiresIn) now))
        |> set #lastRefreshedAt (Just now)
        |> set #connectionStatus "active"
        |> set #lastError Nothing
        |> updateRecord

markXeroConnectionReauthorizationRequired ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    IO ()
markXeroConnectionReauthorizationRequired connection message = do
    markXeroConnectionReauthorizationRequiredWithBroadcast True connection message

markXeroConnectionReauthorizationRequiredWithBroadcast ::
    (?modelContext :: ModelContext) =>
    Bool ->
    XeroConnection ->
    Text ->
    IO ()
markXeroConnectionReauthorizationRequiredWithBroadcast shouldBroadcast connection message = do
    _ <- connection
        |> set #connectionStatus "reauthorization_required"
        |> set #encryptedAccessToken Nothing
        |> set #lastError (Just message)
        |> updateRecord
    when shouldBroadcast (broadcastXeroConnectionUpdate connection)

markXeroConnectionError ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    IO ()
markXeroConnectionError connection message = do
    markXeroConnectionErrorWithBroadcast True connection message

markXeroConnectionErrorWithBroadcast ::
    (?modelContext :: ModelContext) =>
    Bool ->
    XeroConnection ->
    Text ->
    IO ()
markXeroConnectionErrorWithBroadcast shouldBroadcast connection message = do
    _ <- connection
        |> set #connectionStatus "error"
        |> set #lastError (Just message)
        |> updateRecord
    when shouldBroadcast (broadcastXeroConnectionUpdate connection)

broadcastXeroConnectionUpdate :: XeroConnection -> IO ()
broadcastXeroConnectionUpdate connection =
    LiveUpdate.broadcastLiveResyncWithoutContext LiveUpdate.AdminXeroScope { LiveUpdate.venueId = connection.venueId } Nothing
