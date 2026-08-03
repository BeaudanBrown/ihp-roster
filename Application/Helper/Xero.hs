module Application.Helper.Xero
    ( XeroClient (..)
    , XeroClientError (..)
    , XeroRetryAfter (..)
    , XeroConfig (..)
    , XeroAccountRef (..)
    , XeroEarningsRateRef (..)
    , XeroHttpRequest (..)
    , XeroEmployeeRef (..)
    , XeroPayRunQuery (..)
    , XeroPayRunRef (..)
    , XeroPayrollSettingsAccountsResponse (..)
    , XeroPayRunsResponse (..)
    , XeroPayrollCalendarRef (..)
    , XeroRequestBody (..)
    , XeroRequestBaseUrls (..)
    , XeroTimesheetLineRef (..)
    , XeroTimesheetObjectResponse (..)
    , XeroTimesheetQuery (..)
    , XeroTimesheetRef (..)
    , XeroTimesheetsResponse (..)
    , XeroTenant (..)
    , XeroTokenResponse (..)
    , buildXeroAuthorizationUrl
    , buildCreatePayItemRequest
    , buildCreateTimesheetRequest
    , buildDeleteXeroConnectionRequest
    , buildExchangeCodeForTokenRequest
    , buildFetchConnectedTenantsRequest
    , buildFetchAccountsRequest
    , buildFetchEarningsRatesRequest
    , fetchEarningsRatesPageRequest
    , buildFetchPayRunsRequest
    , buildFetchPayrollCalendarsRequest
    , buildFetchPayrollSettingsAccountsRequest
    , buildFetchPayrollEmployeesRequest
    , buildFetchTimesheetRequest
    , buildFetchTimesheetsRequest
    , buildRefreshXeroTokenRequest
    , buildUpdateTimesheetRequest
    , currentXeroClient
    , decryptXeroToken
    , encryptXeroToken
    , generateXeroStateToken
    , readXeroConfig
    , requiredXeroScopes
    , requiredXeroScopesText
    , xeroPayItemsPageSize
    , withXeroClientForTest
    , withXeroConfigForTest
    , withXeroRequestBaseUrlsForTest
    , xeroPayRunsUrl
    , xeroTimesheetsUrl
    )
where

import Application.Helper.Xero.Types
import Control.Applicative ((<|>))
import qualified Control.Exception as Exception
import Control.Monad (guard)
import "crypton" Crypto.Cipher.AES (AES256)
import "crypton" Crypto.Cipher.Types (IV, cipherInit, ctrCombine, makeIV)
import "crypton" Crypto.Error (CryptoError, CryptoFailable (..))
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Random (getRandomBytes)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Bifunctor as Bifunctor
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LByteString
import Data.Char (isDigit)
import qualified Data.IORef as IORef
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime, utctDay)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import qualified Data.Time.Format as TimeFormat
import qualified Data.Vector as Vector
import IHP.Prelude
import Network.HTTP.Simple
import Network.HTTP.Types.Header (HeaderName, hRetryAfter)
import qualified Network.HTTP.Types.URI as URI
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import Text.Read (readMaybe)

requiredXeroScopes :: [Text]
requiredXeroScopes =
    [ "offline_access"
    , "payroll.employees.read"
    , "payroll.payruns.read"
    , "payroll.settings"
    , "payroll.timesheets"
    , "accounting.settings.read"
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
                    Left err    -> Left (showCryptoError err)
                    Right value -> Right value
            iv <- maybe (Left "Invalid Xero token IV") Right (makeIV ivBytes :: Maybe (IV AES256))
            case TextEncoding.decodeUtf8' (ctrCombine cipher iv ciphertext) of
                Left _      -> Left "Invalid UTF-8 in decrypted Xero token"
                Right value -> Right value
        _ -> Left "Unsupported encrypted Xero token format"

decodeBase64Text :: Text -> Either Text ByteString
decodeBase64Text value =
    case Base64.decode (TextEncoding.encodeUtf8 value) of
        Left err    -> Left (cs err)
        Right bytes -> Right bytes

aesCipherFromSecret :: Text -> IO AES256
aesCipherFromSecret secret =
    case cipherFromSecret secret of
        Left err     -> Exception.throwIO (userError (cs (showCryptoError err)))
        Right cipher -> pure cipher

cipherFromSecret :: Text -> Either CryptoError AES256
cipherFromSecret secret =
    case cipherInit (xeroEncryptionKeyBytes secret) of
        CryptoFailed err    -> Left err
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
        , deleteXeroConnection = deleteXeroConnectionRequest
        , refreshXeroToken = refreshXeroTokenRequest
        , fetchPayrollEmployees = fetchPayrollEmployeesRequest
        , fetchEarningsRates = fetchEarningsRatesRequest
        , fetchEarningsRatesPage = fetchEarningsRatesPageRequest
        , fetchPayrollCalendars = fetchPayrollCalendarsRequest
        , fetchAccounts = fetchAccountsRequest
        , fetchPayrollSettingsAccounts = fetchPayrollSettingsAccountsRequest
        , fetchPayRuns = fetchPayRunsRequest
        , createPayItem = createPayItemRequest
        , fetchTimesheets = fetchTimesheetsRequest
        , fetchTimesheet = fetchTimesheetRequest
        , createTimesheet = createTimesheetRequest
        , updateTimesheet = updateTimesheetRequest
        }

xeroClientRef :: IORef.IORef XeroClient
xeroClientRef = unsafePerformIO (IORef.newIORef defaultXeroClient)
{-# NOINLINE xeroClientRef #-}

xeroConfigOverrideRef :: IORef.IORef (Maybe (Either Text XeroConfig))
xeroConfigOverrideRef = unsafePerformIO (IORef.newIORef Nothing)
{-# NOINLINE xeroConfigOverrideRef #-}

xeroRequestBaseUrlsOverrideRef :: IORef.IORef (Maybe XeroRequestBaseUrls)
xeroRequestBaseUrlsOverrideRef = unsafePerformIO (IORef.newIORef Nothing)
{-# NOINLINE xeroRequestBaseUrlsOverrideRef #-}

currentXeroClient :: IO XeroClient
currentXeroClient = IORef.readIORef xeroClientRef

defaultXeroRequestBaseUrls :: XeroRequestBaseUrls
defaultXeroRequestBaseUrls =
    XeroRequestBaseUrls
        { xeroIdentityTokenUrl = "https://identity.xero.com/connect/token"
        , xeroConnectionsUrl = "https://api.xero.com/connections"
        , xeroPayrollBaseUrl = "https://api.xero.com/payroll.xro/1.0"
        , xeroPayrollV2BaseUrl = "https://api.xero.com/payroll.xro/2.0"
        , xeroAccountingBaseUrl = "https://api.xero.com/api.xro/2.0"
        }

currentXeroRequestBaseUrls :: IO XeroRequestBaseUrls
currentXeroRequestBaseUrls =
    fromMaybe defaultXeroRequestBaseUrls <$> IORef.readIORef xeroRequestBaseUrlsOverrideRef

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

withXeroRequestBaseUrlsForTest :: XeroRequestBaseUrls -> IO a -> IO a
withXeroRequestBaseUrlsForTest urls action =
    Exception.bracket
        (IORef.atomicModifyIORef' xeroRequestBaseUrlsOverrideRef \old -> (Just urls, old))
        (IORef.writeIORef xeroRequestBaseUrlsOverrideRef)
        (const action)

exchangeCodeForTokenRequest :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
exchangeCodeForTokenRequest config code = do
    urls <- currentXeroRequestBaseUrls
    sendXeroJsonRequest "Xero token request" (buildExchangeCodeForTokenRequestWith urls config code)

refreshXeroTokenRequest :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
refreshXeroTokenRequest config refreshToken = do
    urls <- currentXeroRequestBaseUrls
    sendXeroJsonRequest "Xero token request" (buildRefreshXeroTokenRequestWith urls config refreshToken)

fetchConnectedTenantsRequest :: Text -> IO (Either XeroClientError [XeroTenant])
fetchConnectedTenantsRequest accessToken = do
    urls <- currentXeroRequestBaseUrls
    sendXeroJsonRequest "Xero connections request" (buildFetchConnectedTenantsRequestWith urls accessToken)

deleteXeroConnectionRequest :: Text -> Text -> IO (Either XeroClientError ())
deleteXeroConnectionRequest accessToken connectionId = do
    urls <- currentXeroRequestBaseUrls
    sendXeroEmptyRequest "Xero disconnect request" (buildDeleteXeroConnectionRequestWith urls accessToken connectionId)

fetchPayrollEmployeesRequest :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
fetchPayrollEmployeesRequest accessToken tenantId = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroEmployeesResponse <$>
        sendXeroJsonRequest "Xero payroll employees request" (buildFetchPayrollEmployeesRequestWith urls accessToken tenantId)

fetchEarningsRatesRequest :: Text -> Text -> IO (Either XeroClientError [XeroEarningsRateRef])
fetchEarningsRatesRequest accessToken tenantId = do
    urls <- currentXeroRequestBaseUrls
    fetchAllEarningsRatePages urls accessToken tenantId 1 Set.empty []

fetchEarningsRatesPageRequest :: Text -> Text -> Int -> IO (Either XeroClientError [XeroEarningsRateRef])
fetchEarningsRatesPageRequest accessToken tenantId page = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroPayItemsResponse <$>
        sendXeroJsonRequest "Xero payroll pay items request" (buildFetchEarningsRatesPageRequestWith urls accessToken tenantId page)

xeroPayItemsPageSize :: Int
xeroPayItemsPageSize = 100

fetchAllEarningsRatePages :: XeroRequestBaseUrls -> Text -> Text -> Int -> Set.Set Text -> [XeroEarningsRateRef] -> IO (Either XeroClientError [XeroEarningsRateRef])
fetchAllEarningsRatePages urls accessToken tenantId page seenIds acc = do
    pageResult <-
        fmap unXeroPayItemsResponse <$>
            sendXeroJsonRequest "Xero payroll pay items request" (buildFetchEarningsRatesPageRequestWith urls accessToken tenantId page)
    case pageResult of
        Left err -> pure (Left err)
        Right pageRates ->
            let pageIds = Set.fromList (map (.xeroEarningsRateId) pageRates)
                repeatedFullPage = length pageRates >= xeroPayItemsPageSize && pageIds `Set.isSubsetOf` seenIds
                acc' = acc <> pageRates
             in if repeatedFullPage
                    then pure (Left (XeroHttpError "Xero payroll pay items pagination repeated a full page without new items."))
                    else if length pageRates < xeroPayItemsPageSize
                        then pure (Right acc')
                        else fetchAllEarningsRatePages urls accessToken tenantId (page + 1) (seenIds <> pageIds) acc'

fetchPayrollCalendarsRequest :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
fetchPayrollCalendarsRequest accessToken tenantId = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroPayrollCalendarsResponse <$>
        sendXeroJsonRequest "Xero payroll calendars request" (buildFetchPayrollCalendarsRequestWith urls accessToken tenantId)

fetchAccountsRequest :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
fetchAccountsRequest accessToken tenantId = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroAccountsResponse <$>
        sendXeroJsonRequest "Xero accounts request" (buildFetchAccountsRequestWith urls accessToken tenantId)

fetchPayrollSettingsAccountsRequest :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
fetchPayrollSettingsAccountsRequest accessToken tenantId = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroPayrollSettingsAccountsResponse <$>
        sendXeroJsonRequest "Xero payroll settings request" (buildFetchPayrollSettingsAccountsRequestWith urls accessToken tenantId)

fetchPayRunsRequest :: Text -> Text -> XeroPayRunQuery -> IO (Either XeroClientError [XeroPayRunRef])
fetchPayRunsRequest accessToken tenantId query = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroPayRunsResponse <$>
        sendXeroJsonRequest "Xero payroll pay runs request" (buildFetchPayRunsRequestWith urls accessToken tenantId query)

createPayItemRequest :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroEarningsRateRef])
createPayItemRequest accessToken tenantId idempotencyKey body = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroEarningsRatesResponse <$>
        sendXeroJsonRequest "Xero payroll earnings rate create request" (buildCreatePayItemRequestWith urls accessToken tenantId idempotencyKey body)

fetchTimesheetsRequest :: Text -> Text -> XeroTimesheetQuery -> IO (Either XeroClientError [XeroTimesheetRef])
fetchTimesheetsRequest accessToken tenantId query = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroTimesheetsResponse <$>
        sendXeroJsonRequest "Xero payroll timesheets request" (buildFetchTimesheetsRequestWith urls accessToken tenantId query)

fetchTimesheetRequest :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetRef)
fetchTimesheetRequest accessToken tenantId timesheetId = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroTimesheetObjectResponse <$>
        sendXeroJsonRequest "Xero payroll timesheet request" (buildFetchTimesheetRequestWith urls accessToken tenantId timesheetId)

createTimesheetRequest :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
createTimesheetRequest accessToken tenantId idempotencyKey body = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroTimesheetsResponse <$>
        sendXeroJsonRequest "Xero payroll timesheet create request" (buildCreateTimesheetRequestWith urls accessToken tenantId idempotencyKey body)

updateTimesheetRequest :: Text -> Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
updateTimesheetRequest accessToken tenantId idempotencyKey timesheetId body = do
    urls <- currentXeroRequestBaseUrls
    fmap unXeroTimesheetsResponse <$>
        sendXeroJsonRequest "Xero payroll timesheet update request" (buildUpdateTimesheetRequestWith urls accessToken tenantId idempotencyKey timesheetId body)

buildExchangeCodeForTokenRequest :: XeroConfig -> Text -> XeroHttpRequest
buildExchangeCodeForTokenRequest =
    buildExchangeCodeForTokenRequestWith defaultXeroRequestBaseUrls

buildExchangeCodeForTokenRequestWith :: XeroRequestBaseUrls -> XeroConfig -> Text -> XeroHttpRequest
buildExchangeCodeForTokenRequestWith urls config code =
    buildXeroTokenRequest
        urls
        config
        [ ("grant_type", "authorization_code")
        , ("code", TextEncoding.encodeUtf8 code)
        , ("redirect_uri", TextEncoding.encodeUtf8 config.redirectUri)
        ]

buildRefreshXeroTokenRequest :: XeroConfig -> Text -> XeroHttpRequest
buildRefreshXeroTokenRequest =
    buildRefreshXeroTokenRequestWith defaultXeroRequestBaseUrls

buildRefreshXeroTokenRequestWith :: XeroRequestBaseUrls -> XeroConfig -> Text -> XeroHttpRequest
buildRefreshXeroTokenRequestWith urls config refreshToken =
    buildXeroTokenRequest
        urls
        config
        [ ("grant_type", "refresh_token")
        , ("refresh_token", TextEncoding.encodeUtf8 refreshToken)
        ]

buildXeroTokenRequest :: XeroRequestBaseUrls -> XeroConfig -> [(ByteString, ByteString)] -> XeroHttpRequest
buildXeroTokenRequest urls config body =
    XeroHttpRequest
        { xeroRequestMethod = "POST"
        , xeroRequestUrl = urls.xeroIdentityTokenUrl
        , xeroRequestHeaders =
            [ ("Authorization", basicAuthorizationHeader config)
            , ("Accept", "application/json")
            , ("Content-Type", "application/x-www-form-urlencoded")
            ]
        , xeroRequestBody = Just (XeroFormBody body)
        }

buildFetchConnectedTenantsRequest :: Text -> XeroHttpRequest
buildFetchConnectedTenantsRequest =
    buildFetchConnectedTenantsRequestWith defaultXeroRequestBaseUrls

buildFetchConnectedTenantsRequestWith :: XeroRequestBaseUrls -> Text -> XeroHttpRequest
buildFetchConnectedTenantsRequestWith urls accessToken =
    XeroHttpRequest
        { xeroRequestMethod = "GET"
        , xeroRequestUrl = urls.xeroConnectionsUrl
        , xeroRequestHeaders = xeroJsonAuthHeaders accessToken
        , xeroRequestBody = Nothing
        }

buildDeleteXeroConnectionRequest :: Text -> Text -> XeroHttpRequest
buildDeleteXeroConnectionRequest =
    buildDeleteXeroConnectionRequestWith defaultXeroRequestBaseUrls

buildDeleteXeroConnectionRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildDeleteXeroConnectionRequestWith urls accessToken connectionId =
    XeroHttpRequest
        { xeroRequestMethod = "DELETE"
        , xeroRequestUrl = urls.xeroConnectionsUrl <> "/" <> connectionId
        , xeroRequestHeaders = xeroJsonAuthHeaders accessToken
        , xeroRequestBody = Nothing
        }

buildFetchPayrollEmployeesRequest :: Text -> Text -> XeroHttpRequest
buildFetchPayrollEmployeesRequest =
    buildFetchPayrollEmployeesRequestWith defaultXeroRequestBaseUrls

buildFetchPayrollEmployeesRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildFetchPayrollEmployeesRequestWith urls accessToken tenantId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroPayrollBaseUrl <> "/Employees") []

buildFetchEarningsRatesRequest :: Text -> Text -> XeroHttpRequest
buildFetchEarningsRatesRequest =
    buildFetchEarningsRatesRequestWith defaultXeroRequestBaseUrls

buildFetchEarningsRatesRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildFetchEarningsRatesRequestWith urls accessToken tenantId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroPayrollBaseUrl <> "/PayItems") []

buildFetchEarningsRatesPageRequestWith :: XeroRequestBaseUrls -> Text -> Text -> Int -> XeroHttpRequest
buildFetchEarningsRatesPageRequestWith urls accessToken tenantId page =
    buildXeroPayrollGetRequest accessToken tenantId payItemsPageUrl []
    where
        payItemsPageUrl =
            urls.xeroPayrollBaseUrl
                <> "/PayItems"
                <> TextEncoding.decodeUtf8 (URI.renderQuery True [("page", Just (TextEncoding.encodeUtf8 (tshow page)))])

buildFetchPayrollCalendarsRequest :: Text -> Text -> XeroHttpRequest
buildFetchPayrollCalendarsRequest =
    buildFetchPayrollCalendarsRequestWith defaultXeroRequestBaseUrls

buildFetchPayrollCalendarsRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildFetchPayrollCalendarsRequestWith urls accessToken tenantId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroPayrollBaseUrl <> "/PayrollCalendars") []

buildFetchAccountsRequest :: Text -> Text -> XeroHttpRequest
buildFetchAccountsRequest =
    buildFetchAccountsRequestWith defaultXeroRequestBaseUrls

buildFetchAccountsRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildFetchAccountsRequestWith urls accessToken tenantId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroAccountingBaseUrl <> "/Accounts") []

buildFetchPayrollSettingsAccountsRequest :: Text -> Text -> XeroHttpRequest
buildFetchPayrollSettingsAccountsRequest =
    buildFetchPayrollSettingsAccountsRequestWith defaultXeroRequestBaseUrls

buildFetchPayrollSettingsAccountsRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroHttpRequest
buildFetchPayrollSettingsAccountsRequestWith urls accessToken tenantId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroPayrollBaseUrl <> "/Settings") []

buildFetchPayRunsRequest :: Text -> Text -> XeroPayRunQuery -> XeroHttpRequest
buildFetchPayRunsRequest =
    buildFetchPayRunsRequestWith defaultXeroRequestBaseUrls

buildFetchPayRunsRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroPayRunQuery -> XeroHttpRequest
buildFetchPayRunsRequestWith urls accessToken tenantId query =
    buildXeroPayrollGetRequest accessToken tenantId (xeroPayRunsUrlWith urls query) (payRunQueryHeaders query)

buildCreatePayItemRequest :: Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildCreatePayItemRequest =
    buildCreatePayItemRequestWith defaultXeroRequestBaseUrls

buildCreatePayItemRequestWith :: XeroRequestBaseUrls -> Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildCreatePayItemRequestWith urls accessToken tenantId idempotencyKey =
    buildXeroPayrollPostRequest accessToken tenantId idempotencyKey (urls.xeroPayrollV2BaseUrl <> "/earningsRates")

buildFetchTimesheetsRequest :: Text -> Text -> XeroTimesheetQuery -> XeroHttpRequest
buildFetchTimesheetsRequest =
    buildFetchTimesheetsRequestWith defaultXeroRequestBaseUrls

buildFetchTimesheetsRequestWith :: XeroRequestBaseUrls -> Text -> Text -> XeroTimesheetQuery -> XeroHttpRequest
buildFetchTimesheetsRequestWith urls accessToken tenantId query =
    buildXeroPayrollGetRequest accessToken tenantId (xeroTimesheetsUrlWith urls query) (timesheetQueryHeaders query)

buildFetchTimesheetRequest :: Text -> Text -> Text -> XeroHttpRequest
buildFetchTimesheetRequest =
    buildFetchTimesheetRequestWith defaultXeroRequestBaseUrls

buildFetchTimesheetRequestWith :: XeroRequestBaseUrls -> Text -> Text -> Text -> XeroHttpRequest
buildFetchTimesheetRequestWith urls accessToken tenantId timesheetId =
    buildXeroPayrollGetRequest accessToken tenantId (urls.xeroPayrollBaseUrl <> "/Timesheets/" <> timesheetId) []

buildCreateTimesheetRequest :: Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildCreateTimesheetRequest =
    buildCreateTimesheetRequestWith defaultXeroRequestBaseUrls

buildCreateTimesheetRequestWith :: XeroRequestBaseUrls -> Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildCreateTimesheetRequestWith urls accessToken tenantId idempotencyKey =
    buildXeroPayrollPostRequest accessToken tenantId idempotencyKey (urls.xeroPayrollBaseUrl <> "/Timesheets")

buildUpdateTimesheetRequest :: Text -> Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildUpdateTimesheetRequest =
    buildUpdateTimesheetRequestWith defaultXeroRequestBaseUrls

buildUpdateTimesheetRequestWith :: XeroRequestBaseUrls -> Text -> Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildUpdateTimesheetRequestWith urls accessToken tenantId idempotencyKey timesheetId =
    buildXeroPayrollPostRequest accessToken tenantId idempotencyKey (urls.xeroPayrollBaseUrl <> "/Timesheets/" <> timesheetId)

buildXeroPayrollGetRequest :: Text -> Text -> Text -> [(HeaderName, ByteString)] -> XeroHttpRequest
buildXeroPayrollGetRequest accessToken tenantId url extraHeaders =
    XeroHttpRequest
        { xeroRequestMethod = "GET"
        , xeroRequestUrl = url
        , xeroRequestHeaders = xeroPayrollHeaders accessToken tenantId <> extraHeaders
        , xeroRequestBody = Nothing
        }

buildXeroPayrollPostRequest :: Text -> Text -> Text -> Text -> Aeson.Value -> XeroHttpRequest
buildXeroPayrollPostRequest accessToken tenantId idempotencyKey url body =
    XeroHttpRequest
        { xeroRequestMethod = "POST"
        , xeroRequestUrl = url
        , xeroRequestHeaders =
            xeroPayrollHeaders accessToken tenantId
                <> [ ("Idempotency-Key", TextEncoding.encodeUtf8 idempotencyKey)
                   , ("Content-Type", "application/json")
                   ]
        , xeroRequestBody = Just (XeroJsonBody body)
        }

xeroJsonAuthHeaders :: Text -> [(HeaderName, ByteString)]
xeroJsonAuthHeaders accessToken =
    [ ("Authorization", "Bearer " <> TextEncoding.encodeUtf8 accessToken)
    , ("Accept", "application/json")
    ]

xeroPayrollHeaders :: Text -> Text -> [(HeaderName, ByteString)]
xeroPayrollHeaders accessToken tenantId =
    xeroJsonAuthHeaders accessToken
        <> [("Xero-Tenant-Id", TextEncoding.encodeUtf8 tenantId)]

sendXeroJsonRequest :: Aeson.FromJSON value => Text -> XeroHttpRequest -> IO (Either XeroClientError value)
sendXeroJsonRequest label xeroRequest =
    handleXeroHttpExceptions do
        requestWithHeaders <- toHttpRequest xeroRequest
        response <- httpLBS requestWithHeaders
        decodeXeroResponse label response

sendXeroEmptyRequest :: Text -> XeroHttpRequest -> IO (Either XeroClientError ())
sendXeroEmptyRequest label xeroRequest =
    handleXeroHttpExceptions do
        requestWithHeaders <- toHttpRequest xeroRequest
        response <- httpLBS requestWithHeaders
        decodeXeroEmptyResponse label response

toHttpRequest :: XeroHttpRequest -> IO Request
toHttpRequest xeroRequest = do
    request <- parseRequest (cs xeroRequest.xeroRequestUrl)
    let requestWithHeaders =
            request
                |> setRequestMethod xeroRequest.xeroRequestMethod
                |> applyRequestHeaders xeroRequest.xeroRequestHeaders
    pure case xeroRequest.xeroRequestBody of
        Nothing -> requestWithHeaders
        Just (XeroJsonBody body) -> setRequestBodyJSON body requestWithHeaders
        Just (XeroFormBody body) -> setRequestBodyURLEncoded body requestWithHeaders

applyRequestHeaders :: [(HeaderName, ByteString)] -> Request -> Request
applyRequestHeaders headers request =
    foldl' (\current (name, value) -> setRequestHeader name [value] current) request headers

xeroTimesheetsUrl :: XeroTimesheetQuery -> String
xeroTimesheetsUrl query =
    cs (xeroTimesheetsUrlWith defaultXeroRequestBaseUrls query)

xeroTimesheetsUrlWith :: XeroRequestBaseUrls -> XeroTimesheetQuery -> Text
xeroTimesheetsUrlWith urls query =
    urls.xeroPayrollBaseUrl <> "/Timesheets" <> renderedQuery
    where
        params =
            catMaybes
                [ ("where",) . TextEncoding.encodeUtf8 <$> query.xeroTimesheetWhere
                , ("order",) . TextEncoding.encodeUtf8 <$> query.xeroTimesheetOrder
                , ("page",) . TextEncoding.encodeUtf8 . tshow <$> query.xeroTimesheetPage
                ]
        renderedQuery = TextEncoding.decodeUtf8 (URI.renderQuery True (map (Bifunctor.second Just) params))

timesheetQueryHeaders :: XeroTimesheetQuery -> [(HeaderName, ByteString)]
timesheetQueryHeaders query =
    maybe [] (\time -> [("If-Modified-Since", cs (TimeFormat.formatTime defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" time))]) query.xeroTimesheetIfModifiedSince

xeroPayRunsUrl :: XeroPayRunQuery -> String
xeroPayRunsUrl query =
    cs (xeroPayRunsUrlWith defaultXeroRequestBaseUrls query)

xeroPayRunsUrlWith :: XeroRequestBaseUrls -> XeroPayRunQuery -> Text
xeroPayRunsUrlWith urls query =
    urls.xeroPayrollBaseUrl <> "/PayRuns" <> renderedQuery
    where
        params =
            catMaybes
                [ ("where",) . TextEncoding.encodeUtf8 <$> query.xeroPayRunWhere
                , ("order",) . TextEncoding.encodeUtf8 <$> query.xeroPayRunOrder
                , ("page",) . TextEncoding.encodeUtf8 . tshow <$> query.xeroPayRunPage
                ]
        renderedQuery = TextEncoding.decodeUtf8 (URI.renderQuery True (map (Bifunctor.second Just) params))

payRunQueryHeaders :: XeroPayRunQuery -> [(HeaderName, ByteString)]
payRunQueryHeaders query =
    maybe [] (\time -> [("If-Modified-Since", cs (TimeFormat.formatTime defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" time))]) query.xeroPayRunIfModifiedSince

basicAuthorizationHeader :: XeroConfig -> ByteString
basicAuthorizationHeader config =
    "Basic " <> Base64.encode (TextEncoding.encodeUtf8 (config.clientId <> ":" <> config.clientSecret))

decodeXeroResponse :: Aeson.FromJSON value => Text -> Response LByteString.ByteString -> IO (Either XeroClientError value)
decodeXeroResponse label response = do
    let statusCode = getResponseStatusCode response
    let responseBody = getResponseBody response
    if statusCode < 200 || statusCode >= 300
        then pure (Left (xeroHttpResponseError label response))
        else case xeroSemanticErrorFromBody label responseBody of
            Just err -> pure (Left err)
            Nothing  -> decodeBody responseBody
    where
        decodeBody responseBody =
            case Aeson.eitherDecode responseBody of
                Left err      -> pure (Left (XeroDecodeError (cs err)))
                Right decoded -> pure (Right decoded)

xeroHttpResponseError :: Text -> Response LByteString.ByteString -> XeroClientError
xeroHttpResponseError label response =
    XeroHttpResponseError
        { statusCode = status
        , retryAfter = listToMaybe (getResponseHeader hRetryAfter response) >>= parseXeroRetryAfter
        , customerMessage = label <> " failed with status " <> tshow status <> xeroProviderMessageSuffix (getResponseBody response)
        }
    where
        status = getResponseStatusCode response

parseXeroRetryAfter :: ByteString -> Maybe XeroRetryAfter
parseXeroRetryAfter rawValue =
    let value = Text.strip (TextEncoding.decodeUtf8With lenientDecode rawValue)
     in case readMaybe (Text.unpack value) of
            Just seconds | seconds >= (0 :: Int) -> Just (XeroRetryAfterDelay seconds)
            _ -> XeroRetryAfterAt <$> parseTimeM True defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" (Text.unpack value)

xeroProviderMessageSuffix :: LByteString.ByteString -> Text
xeroProviderMessageSuffix responseBody =
    case Aeson.decode responseBody of
        Just (Aeson.Object object) ->
            let maybeErrorType = nonEmptyText =<< firstPresent object ["Type", "type"]
                maybeMessage = nonEmptyText =<< firstPresent object ["Message", "message", "Detail", "detail", "Title", "title"]
                details = catMaybes [maybeErrorType, maybeMessage]
             in if null details then "" else ": " <> Text.intercalate ": " details
        _ -> ""
    where
        nonEmptyText (Aeson.String value)
            | not (Text.null (Text.strip value)) = Just (Text.strip value)
        nonEmptyText _ = Nothing

xeroSemanticErrorFromBody :: Text -> LByteString.ByteString -> Maybe XeroClientError
xeroSemanticErrorFromBody label responseBody = do
    Aeson.Object object <- Aeson.decode responseBody
    Aeson.String errorType <- firstPresent object ["Type", "type"]
    guard (not (Text.null (Text.strip errorType)))
    let maybeMessage =
            case firstPresent object ["Message", "message", "Detail", "detail", "Title", "title"] of
                Just (Aeson.String message) -> Just message
                _                           -> Nothing
    pure $
        XeroSemanticError $
            label
                <> " returned Xero "
                <> errorType
                <> maybe "" (": " <>) maybeMessage

decodeXeroEmptyResponse :: Text -> Response LByteString.ByteString -> IO (Either XeroClientError ())
decodeXeroEmptyResponse label response = do
    let statusCode = getResponseStatusCode response
    if statusCode < 200 || statusCode >= 300
        then pure (Left (xeroHttpResponseError label response))
        else pure (Right ())

handleXeroHttpExceptions :: IO (Either XeroClientError value) -> IO (Either XeroClientError value)
handleXeroHttpExceptions action = do
    result <- Exception.try action
    pure case result of
        Left (err :: Exception.SomeException) -> Left (XeroHttpError (cs (show err)))
        Right value -> value

