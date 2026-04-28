module Application.Helper.Xero
    ( XeroClient (..)
    , XeroClientError (..)
    , XeroConfig (..)
    , XeroTenant (..)
    , XeroTokenResponse (..)
    , buildXeroAuthorizationUrl
    , currentXeroClient
    , decryptXeroToken
    , encryptXeroToken
    , generateXeroStateToken
    , readXeroConfig
    , requiredXeroScopes
    , requiredXeroScopesText
    , withXeroClientForTest
    , withXeroConfigForTest
    )
where

import qualified Control.Exception as Exception
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Cipher.AES (AES256)
import "crypton" Crypto.Cipher.Types (IV, cipherInit, ctrCombine, makeIV)
import "crypton" Crypto.Error (CryptoError, CryptoFailable (..))
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.Aeson as Aeson
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.IORef as IORef
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Network.HTTP.Types.URI as URI
import Network.HTTP.Simple
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import IHP.Prelude

data XeroConfig = XeroConfig
    { clientId            :: !Text
    , clientSecret        :: !Text
    , redirectUri         :: !Text
    , tokenEncryptionKey  :: !Text
    }
    deriving (Eq, Show)

data XeroTokenResponse = XeroTokenResponse
    { accessToken  :: !Text
    , refreshToken :: !Text
    , expiresIn    :: !Int
    , scope        :: !(Maybe Text)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTokenResponse where
    parseJSON = Aeson.withObject "XeroTokenResponse" \object ->
        XeroTokenResponse
            <$> object Aeson..: "access_token"
            <*> object Aeson..: "refresh_token"
            <*> object Aeson..: "expires_in"
            <*> object Aeson..:? "scope"

data XeroTenant = XeroTenant
    { tenantId   :: !Text
    , tenantName :: !(Maybe Text)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTenant where
    parseJSON = Aeson.withObject "XeroTenant" \object ->
        XeroTenant
            <$> object Aeson..: "tenantId"
            <*> object Aeson..:? "tenantName"

data XeroClientError
    = XeroHttpError Text
    | XeroDecodeError Text
    | XeroNoTenantsError
    deriving (Eq, Show)

data XeroClient = XeroClient
    { exchangeCodeForToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    , fetchConnectedTenants :: Text -> IO (Either XeroClientError [XeroTenant])
    , refreshXeroToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    }

requiredXeroScopes :: [Text]
requiredXeroScopes =
    [ "offline_access"
    , "payroll.employees.read"
    , "payroll.settings.read"
    , "payroll.timesheets"
    ]

requiredXeroScopesText :: Text
requiredXeroScopesText = Text.intercalate " " requiredXeroScopes

readXeroConfig :: IO (Either Text XeroConfig)
readXeroConfig = do
    configOverride <- IORef.readIORef xeroConfigOverrideRef
    case configOverride of
        Just result -> pure result
        Nothing -> do
            maybeClientId <- lookupEnvText "XERO_CLIENT_ID"
            maybeClientSecret <- lookupEnvText "XERO_CLIENT_SECRET"
            maybeRedirectUri <- lookupEnvText "XERO_REDIRECT_URI"
            maybeEncryptionKey <- lookupEnvText "XERO_TOKEN_ENCRYPTION_KEY"
            pure case (maybeClientId, maybeClientSecret, maybeRedirectUri, maybeEncryptionKey) of
                (Just clientId, Just clientSecret, Just redirectUri, Just tokenEncryptionKey) ->
                    Right XeroConfig { .. }
                _ ->
                    Left "Xero is not configured. Set XERO_CLIENT_ID, XERO_CLIENT_SECRET, XERO_REDIRECT_URI, and XERO_TOKEN_ENCRYPTION_KEY before using this integration."

lookupEnvText :: String -> IO (Maybe Text)
lookupEnvText name = fmap cs <$> lookupEnv name

buildXeroAuthorizationUrl :: XeroConfig -> Text -> Text
buildXeroAuthorizationUrl config stateToken =
    "https://login.xero.com/identity/connect/authorize"
        <> TextEncoding.decodeUtf8
            ( URI.renderQuery
                True
                [ ("response_type", Just "code")
                , ("client_id", Just (TextEncoding.encodeUtf8 config.clientId))
                , ("redirect_uri", Just (TextEncoding.encodeUtf8 config.redirectUri))
                , ("scope", Just (TextEncoding.encodeUtf8 requiredXeroScopesText))
                , ("state", Just (TextEncoding.encodeUtf8 stateToken))
                ]
            )

generateXeroStateToken :: IO Text
generateXeroStateToken = do
    randomBytes <- getRandomBytes 32 :: IO ByteString
    pure (TextEncoding.decodeUtf8 (Base64.encode randomBytes))

encryptXeroToken :: Text -> Text -> IO Text
encryptXeroToken secret plaintext = do
    ivBytes <- getRandomBytes 16 :: IO ByteString
    cipher <- aesCipherFromSecret secret
    iv <- ivFromBytes ivBytes
    let ciphertext = ctrCombine cipher iv (TextEncoding.encodeUtf8 plaintext)
    pure $
        Text.intercalate
            ":"
            [ "v1"
            , TextEncoding.decodeUtf8 (Base64.encode ivBytes)
            , TextEncoding.decodeUtf8 (Base64.encode ciphertext)
            ]

decryptXeroToken :: Text -> Text -> Either Text Text
decryptXeroToken secret encrypted =
    case Text.splitOn ":" encrypted of
        ["v1", encodedIv, encodedCiphertext] -> do
            ivBytes <- decodeBase64Text encodedIv
            ciphertext <- decodeBase64Text encodedCiphertext
            cipher <-
                case cipherFromSecret secret of
                    Left err -> Left (showCryptoError err)
                    Right value -> Right value
            iv <- maybe (Left "Invalid Xero token IV") Right (makeIV ivBytes :: Maybe (IV AES256))
            case TextEncoding.decodeUtf8' (ctrCombine cipher iv ciphertext) of
                Left _ -> Left "Invalid UTF-8 in decrypted Xero token"
                Right value -> Right value
        _ -> Left "Unsupported encrypted Xero token format"

decodeBase64Text :: Text -> Either Text ByteString
decodeBase64Text value =
    case Base64.decode (TextEncoding.encodeUtf8 value) of
        Left err -> Left (cs err)
        Right bytes -> Right bytes

aesCipherFromSecret :: Text -> IO AES256
aesCipherFromSecret secret =
    case cipherFromSecret secret of
        Left err     -> Exception.throwIO (userError (cs (showCryptoError err)))
        Right cipher -> pure cipher

cipherFromSecret :: Text -> Either CryptoError AES256
cipherFromSecret secret =
    case cipherInit (xeroEncryptionKeyBytes secret) of
        CryptoFailed err -> Left err
        CryptoPassed cipher -> Right cipher

ivFromBytes :: ByteString -> IO (IV AES256)
ivFromBytes bytes =
    case makeIV bytes of
        Just iv -> pure iv
        Nothing -> Exception.throwIO (userError "Failed to build Xero token IV")

xeroEncryptionKeyBytes :: Text -> ByteString
xeroEncryptionKeyBytes secret =
    ByteArray.convert (Hash.hash (TextEncoding.encodeUtf8 secret) :: Hash.Digest Hash.SHA256)

showCryptoError :: CryptoError -> Text
showCryptoError = cs . show

defaultXeroClient :: XeroClient
defaultXeroClient =
    XeroClient
        { exchangeCodeForToken = exchangeCodeForTokenRequest
        , fetchConnectedTenants = fetchConnectedTenantsRequest
        , refreshXeroToken = refreshXeroTokenRequest
        }

xeroClientRef :: IORef.IORef XeroClient
xeroClientRef = unsafePerformIO (IORef.newIORef defaultXeroClient)
{-# NOINLINE xeroClientRef #-}

xeroConfigOverrideRef :: IORef.IORef (Maybe (Either Text XeroConfig))
xeroConfigOverrideRef = unsafePerformIO (IORef.newIORef Nothing)
{-# NOINLINE xeroConfigOverrideRef #-}

currentXeroClient :: IO XeroClient
currentXeroClient = IORef.readIORef xeroClientRef

withXeroClientForTest :: XeroClient -> IO a -> IO a
withXeroClientForTest client action =
    Exception.bracket
        (IORef.atomicModifyIORef' xeroClientRef \old -> (client, old))
        (IORef.writeIORef xeroClientRef)
        (const action)

withXeroConfigForTest :: Either Text XeroConfig -> IO a -> IO a
withXeroConfigForTest configResult action =
    Exception.bracket
        (IORef.atomicModifyIORef' xeroConfigOverrideRef \old -> (Just configResult, old))
        (IORef.writeIORef xeroConfigOverrideRef)
        (const action)

exchangeCodeForTokenRequest :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
exchangeCodeForTokenRequest config code =
    postXeroTokenRequest
        config
        [ ("grant_type", "authorization_code")
        , ("code", TextEncoding.encodeUtf8 code)
        , ("redirect_uri", TextEncoding.encodeUtf8 config.redirectUri)
        ]

refreshXeroTokenRequest :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
refreshXeroTokenRequest config refreshToken =
    postXeroTokenRequest
        config
        [ ("grant_type", "refresh_token")
        , ("refresh_token", TextEncoding.encodeUtf8 refreshToken)
        ]

postXeroTokenRequest :: XeroConfig -> [(ByteString, ByteString)] -> IO (Either XeroClientError XeroTokenResponse)
postXeroTokenRequest config body =
    handleXeroHttpExceptions do
        request <- parseRequest "https://identity.xero.com/connect/token"
        let requestWithBody =
                request
                    |> setRequestMethod "POST"
                    |> setRequestHeader "Authorization" [basicAuthorizationHeader config]
                    |> setRequestHeader "Accept" ["application/json"]
                    |> setRequestBodyURLEncoded body
        response <- httpLBS requestWithBody
        decodeXeroResponse "Xero token request" response

fetchConnectedTenantsRequest :: Text -> IO (Either XeroClientError [XeroTenant])
fetchConnectedTenantsRequest accessToken =
    handleXeroHttpExceptions do
        request <- parseRequest "https://api.xero.com/connections"
        let requestWithHeaders =
                request
                    |> setRequestMethod "GET"
                    |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                    |> setRequestHeader "Accept" ["application/json"]
        response <- httpLBS requestWithHeaders
        decodeXeroResponse "Xero connections request" response

basicAuthorizationHeader :: XeroConfig -> ByteString
basicAuthorizationHeader config =
    "Basic " <> Base64.encode (TextEncoding.encodeUtf8 (config.clientId <> ":" <> config.clientSecret))

decodeXeroResponse :: Aeson.FromJSON value => Text -> Response LByteString.ByteString -> IO (Either XeroClientError value)
decodeXeroResponse label response = do
    let statusCode = getResponseStatusCode response
    if statusCode < 200 || statusCode >= 300
        then pure (Left (XeroHttpError (label <> " failed with status " <> tshow statusCode)))
        else case Aeson.eitherDecode (getResponseBody response) of
            Left err -> pure (Left (XeroDecodeError (cs err)))
            Right decoded -> pure (Right decoded)

handleXeroHttpExceptions :: IO (Either XeroClientError value) -> IO (Either XeroClientError value)
handleXeroHttpExceptions action = do
    result <- Exception.try action
    pure case result of
        Left (err :: Exception.SomeException) -> Left (XeroHttpError (cs (show err)))
        Right value -> value
