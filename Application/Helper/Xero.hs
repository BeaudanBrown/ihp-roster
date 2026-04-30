module Application.Helper.Xero
    ( XeroClient (..)
    , XeroClientError (..)
    , XeroConfig (..)
    , XeroEarningsRateRef (..)
    , XeroEmployeeRef (..)
    , XeroPayrollCalendarRef (..)
    , XeroTimesheetLineRef (..)
    , XeroTimesheetObjectResponse (..)
    , XeroTimesheetQuery (..)
    , XeroTimesheetRef (..)
    , XeroTimesheetsResponse (..)
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
    , xeroTimesheetsUrl
    )
where

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
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LByteString
import Data.Char (isDigit)
import qualified Data.IORef as IORef
import Data.Scientific (Scientific)
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
import Network.HTTP.Types.Header (HeaderName)
import qualified Network.HTTP.Types.URI as URI
import System.Environment (lookupEnv)
import System.IO.Unsafe (unsafePerformIO)
import Text.Read (readMaybe)

data XeroConfig = XeroConfig
    { clientId           :: !Text
    , clientSecret       :: !Text
    , redirectUri        :: !Text
    , tokenEncryptionKey :: !Text
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
    { xeroConnectionId :: !Text
    , tenantId         :: !Text
    , tenantName       :: !(Maybe Text)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTenant where
    parseJSON = Aeson.withObject "XeroTenant" \object ->
        XeroTenant
            <$> object Aeson..: "id"
            <*> object Aeson..: "tenantId"
            <*> object Aeson..:? "tenantName"

data XeroEmployeeRef = XeroEmployeeRef
    { xeroEmployeeId         :: !Text
    , xeroEmployeeName       :: !Text
    , xeroEmployeeEmail      :: !(Maybe Text)
    , xeroEmployeeStatus     :: !(Maybe Text)
    , xeroEmployeeCalendarId :: !(Maybe Text)
    , xeroEmployeeRaw        :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroEmployeeRef where
    parseJSON value@(Aeson.Object object) =
        XeroEmployeeRef
            <$> requiredText object ["EmployeeID", "employeeID", "employeeId"]
            <*> employeeDisplayName object
            <*> optionalText object ["Email", "email"]
            <*> optionalText object ["Status", "status"]
            <*> optionalText object ["PayrollCalendarID", "payrollCalendarID", "payrollCalendarId"]
            <*> pure value
    parseJSON _ = fail "Expected Xero employee object"

data XeroEarningsRateRef = XeroEarningsRateRef
    { xeroEarningsRateId          :: !Text
    , xeroEarningsRateName        :: !Text
    , xeroEarningsRateType        :: !(Maybe Text)
    , xeroEarningsRateRateType    :: !(Maybe Text)
    , xeroEarningsRateAccountCode :: !(Maybe Text)
    , xeroEarningsRateIsActive    :: !Bool
    , xeroEarningsRateRaw         :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroEarningsRateRef where
    parseJSON value@(Aeson.Object object) =
        XeroEarningsRateRef
            <$> requiredText object ["EarningsRateID", "earningsRateID", "earningsRateId"]
            <*> requiredText object ["Name", "name"]
            <*> optionalText object ["EarningsType", "earningsType"]
            <*> optionalText object ["RateType", "rateType"]
            <*> optionalText object ["AccountCode", "accountCode"]
            <*> activeFromObject object
            <*> pure value
    parseJSON _ = fail "Expected Xero earnings rate object"

data XeroPayrollCalendarRef = XeroPayrollCalendarRef
    { xeroPayrollCalendarId          :: !Text
    , xeroPayrollCalendarName        :: !Text
    , xeroPayrollCalendarType        :: !(Maybe Text)
    , xeroPayrollCalendarStartDate   :: !(Maybe Day)
    , xeroPayrollCalendarPaymentDate :: !(Maybe Day)
    , xeroPayrollCalendarRaw         :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroPayrollCalendarRef where
    parseJSON value@(Aeson.Object object) =
        XeroPayrollCalendarRef
            <$> requiredText object ["PayrollCalendarID", "payrollCalendarID", "payrollCalendarId"]
            <*> requiredText object ["Name", "name"]
            <*> optionalText object ["CalendarType", "calendarType"]
            <*> optionalDay object ["StartDate", "startDate"]
            <*> optionalDay object ["PaymentDate", "paymentDate"]
            <*> pure value
    parseJSON _ = fail "Expected Xero payroll calendar object"

data XeroTimesheetLineRef = XeroTimesheetLineRef
    { xeroTimesheetLineEarningsRateId :: !(Maybe Text)
    , xeroTimesheetLineTrackingItemId :: !(Maybe Text)
    , xeroTimesheetLineUnits          :: ![Scientific]
    , xeroTimesheetLineRaw            :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTimesheetLineRef where
    parseJSON value@(Aeson.Object object) =
        XeroTimesheetLineRef
            <$> optionalText object ["EarningsRateID", "earningsRateID", "earningsRateId"]
            <*> optionalText object ["TrackingItemID", "trackingItemID", "trackingItemId"]
            <*> optionalScientificList object ["NumberOfUnits", "numberOfUnits"]
            <*> pure value
    parseJSON _ = fail "Expected Xero timesheet line object"

data XeroTimesheetRef = XeroTimesheetRef
    { xeroTimesheetId         :: !(Maybe Text)
    , xeroTimesheetEmployeeId :: !Text
    , xeroTimesheetStartDate  :: !Day
    , xeroTimesheetEndDate    :: !Day
    , xeroTimesheetStatus     :: !(Maybe Text)
    , xeroTimesheetHours      :: !(Maybe Scientific)
    , xeroTimesheetLines      :: ![XeroTimesheetLineRef]
    , xeroTimesheetRaw        :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTimesheetRef where
    parseJSON value@(Aeson.Object object) =
        XeroTimesheetRef
            <$> optionalText object ["TimesheetID", "timesheetID", "timesheetId"]
            <*> requiredText object ["EmployeeID", "employeeID", "employeeId"]
            <*> requiredDay object ["StartDate", "startDate"]
            <*> requiredDay object ["EndDate", "endDate"]
            <*> optionalText object ["Status", "status"]
            <*> optionalScientific object ["Hours", "hours"]
            <*> optionalTimesheetLines object
            <*> pure value
    parseJSON _ = fail "Expected Xero timesheet object"

data XeroTimesheetQuery = XeroTimesheetQuery
    { xeroTimesheetIfModifiedSince :: !(Maybe UTCTime)
    , xeroTimesheetWhere           :: !(Maybe Text)
    , xeroTimesheetOrder           :: !(Maybe Text)
    , xeroTimesheetPage            :: !(Maybe Int)
    }
    deriving (Eq, Show)

data XeroClientError
    = XeroHttpError Text
    | XeroDecodeError Text
    | XeroNoTenantsError
    deriving (Eq, Show)

data XeroClient = XeroClient
    { exchangeCodeForToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    , fetchConnectedTenants :: Text -> IO (Either XeroClientError [XeroTenant])
    , deleteXeroConnection :: Text -> Text -> IO (Either XeroClientError ())
    , refreshXeroToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    , fetchPayrollEmployees :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
    , fetchEarningsRates :: Text -> Text -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchPayrollCalendars :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
    , createPayItem :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchTimesheets :: Text -> Text -> XeroTimesheetQuery -> IO (Either XeroClientError [XeroTimesheetRef])
    , fetchTimesheet :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetRef)
    , createTimesheet :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
    , updateTimesheet :: Text -> Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
    }

requiredXeroScopes :: [Text]
requiredXeroScopes =
    [ "offline_access"
    , "payroll.employees.read"
    , "payroll.settings"
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
        , fetchPayrollCalendars = fetchPayrollCalendarsRequest
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

deleteXeroConnectionRequest :: Text -> Text -> IO (Either XeroClientError ())
deleteXeroConnectionRequest accessToken connectionId =
    handleXeroHttpExceptions do
        request <- parseRequest ("https://api.xero.com/connections/" <> cs connectionId)
        let requestWithHeaders =
                request
                    |> setRequestMethod "DELETE"
                    |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                    |> setRequestHeader "Accept" ["application/json"]
        response <- httpLBS requestWithHeaders
        decodeXeroEmptyResponse "Xero disconnect request" response

fetchPayrollEmployeesRequest :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
fetchPayrollEmployeesRequest accessToken tenantId =
    fmap unXeroEmployeesResponse <$>
        getXeroPayrollRequest "Xero payroll employees request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/Employees"

fetchEarningsRatesRequest :: Text -> Text -> IO (Either XeroClientError [XeroEarningsRateRef])
fetchEarningsRatesRequest accessToken tenantId =
    fmap unXeroPayItemsResponse <$>
        getXeroPayrollRequest "Xero payroll pay items request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/PayItems"

fetchPayrollCalendarsRequest :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
fetchPayrollCalendarsRequest accessToken tenantId =
    fmap unXeroPayrollCalendarsResponse <$>
        getXeroPayrollRequest "Xero payroll calendars request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/PayrollCalendars"

createPayItemRequest :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroEarningsRateRef])
createPayItemRequest accessToken tenantId idempotencyKey body =
    fmap unXeroPayItemsResponse <$>
        postXeroPayrollRequest "Xero payroll pay item create request" accessToken tenantId idempotencyKey "https://api.xero.com/payroll.xro/1.0/PayItems" body

fetchTimesheetsRequest :: Text -> Text -> XeroTimesheetQuery -> IO (Either XeroClientError [XeroTimesheetRef])
fetchTimesheetsRequest accessToken tenantId query =
    fmap unXeroTimesheetsResponse <$>
        getXeroPayrollRequestWithHeaders
            "Xero payroll timesheets request"
            accessToken
            tenantId
            (xeroTimesheetsUrl query)
            (timesheetQueryHeaders query)

fetchTimesheetRequest :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetRef)
fetchTimesheetRequest accessToken tenantId timesheetId =
    fmap unXeroTimesheetObjectResponse <$>
        getXeroPayrollRequest
            "Xero payroll timesheet request"
            accessToken
            tenantId
            ("https://api.xero.com/payroll.xro/1.0/Timesheets/" <> cs timesheetId)

createTimesheetRequest :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
createTimesheetRequest accessToken tenantId idempotencyKey body =
    fmap unXeroTimesheetsResponse <$>
        postXeroPayrollRequest
            "Xero payroll timesheet create request"
            accessToken
            tenantId
            idempotencyKey
            "https://api.xero.com/payroll.xro/1.0/Timesheets"
            body

updateTimesheetRequest :: Text -> Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
updateTimesheetRequest accessToken tenantId idempotencyKey timesheetId body =
    fmap unXeroTimesheetsResponse <$>
        postXeroPayrollRequest
            "Xero payroll timesheet update request"
            accessToken
            tenantId
            idempotencyKey
            ("https://api.xero.com/payroll.xro/1.0/Timesheets/" <> cs timesheetId)
            body

getXeroPayrollRequest :: Aeson.FromJSON value => Text -> Text -> Text -> String -> IO (Either XeroClientError value)
getXeroPayrollRequest label accessToken tenantId url =
    getXeroPayrollRequestWithHeaders label accessToken tenantId url []

getXeroPayrollRequestWithHeaders :: Aeson.FromJSON value => Text -> Text -> Text -> String -> [(HeaderName, ByteString)] -> IO (Either XeroClientError value)
getXeroPayrollRequestWithHeaders label accessToken tenantId url extraHeaders =
    handleXeroHttpExceptions do
        request <- parseRequest url
        let requestWithHeaders =
                request
                    |> setRequestMethod "GET"
                    |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                    |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 tenantId]
                    |> setRequestHeader "Accept" ["application/json"]
                    |> applyRequestHeaders extraHeaders
        response <- httpLBS requestWithHeaders
        decodeXeroResponse label response

postXeroPayrollRequest :: Aeson.FromJSON value => Text -> Text -> Text -> Text -> String -> Aeson.Value -> IO (Either XeroClientError value)
postXeroPayrollRequest label accessToken tenantId idempotencyKey url body =
    handleXeroHttpExceptions do
        request <- parseRequest url
        let requestWithHeaders =
                request
                    |> setRequestMethod "POST"
                    |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                    |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 tenantId]
                    |> setRequestHeader "Idempotency-Key" [TextEncoding.encodeUtf8 idempotencyKey]
                    |> setRequestHeader "Accept" ["application/json"]
                    |> setRequestHeader "Content-Type" ["application/json"]
                    |> setRequestBodyJSON body
        response <- httpLBS requestWithHeaders
        decodeXeroResponse label response

applyRequestHeaders :: [(HeaderName, ByteString)] -> Request -> Request
applyRequestHeaders headers request =
    foldl' (\current (name, value) -> setRequestHeader name [value] current) request headers

xeroTimesheetsUrl :: XeroTimesheetQuery -> String
xeroTimesheetsUrl query =
    cs ("https://api.xero.com/payroll.xro/1.0/Timesheets" <> renderedQuery)
    where
        params =
            catMaybes
                [ ("where",) . TextEncoding.encodeUtf8 <$> query.xeroTimesheetWhere
                , ("order",) . TextEncoding.encodeUtf8 <$> query.xeroTimesheetOrder
                , ("page",) . TextEncoding.encodeUtf8 . tshow <$> query.xeroTimesheetPage
                ]
        renderedQuery = TextEncoding.decodeUtf8 (URI.renderQuery True (map (\(key, value) -> (key, Just value)) params))

timesheetQueryHeaders :: XeroTimesheetQuery -> [(HeaderName, ByteString)]
timesheetQueryHeaders query =
    maybe [] (\time -> [("If-Modified-Since", cs (TimeFormat.formatTime defaultTimeLocale "%a, %d %b %Y %H:%M:%S GMT" time))]) query.xeroTimesheetIfModifiedSince

basicAuthorizationHeader :: XeroConfig -> ByteString
basicAuthorizationHeader config =
    "Basic " <> Base64.encode (TextEncoding.encodeUtf8 (config.clientId <> ":" <> config.clientSecret))

decodeXeroResponse :: Aeson.FromJSON value => Text -> Response LByteString.ByteString -> IO (Either XeroClientError value)
decodeXeroResponse label response = do
    let statusCode = getResponseStatusCode response
    let responseBody = getResponseBody response
    let bodyExcerpt = Text.take 500 (TextEncoding.decodeUtf8With lenientDecode (LByteString.toStrict responseBody))
    if statusCode < 200 || statusCode >= 300
        then
            pure (Left (XeroHttpError (label <> " failed with status " <> tshow statusCode <> responseBodySuffix bodyExcerpt)))
        else case xeroSemanticErrorFromBody label responseBody bodyExcerpt of
            Just err -> pure (Left err)
            Nothing -> decodeBody responseBody
    where
        decodeBody responseBody =
            case Aeson.eitherDecode responseBody of
                Left err      -> pure (Left (XeroDecodeError (cs err)))
                Right decoded -> pure (Right decoded)

responseBodySuffix :: Text -> Text
responseBodySuffix bodyExcerpt
    | Text.null (Text.strip bodyExcerpt) = ""
    | otherwise = ": " <> Text.strip bodyExcerpt

xeroSemanticErrorFromBody :: Text -> LByteString.ByteString -> Text -> Maybe XeroClientError
xeroSemanticErrorFromBody label responseBody bodyExcerpt = do
    Aeson.Object object <- Aeson.decode responseBody
    Aeson.String errorType <- firstPresent object ["Type", "type"]
    guard (not (Text.null (Text.strip errorType)))
    let maybeMessage =
            case firstPresent object ["Message", "message", "Detail", "detail", "Title", "title"] of
                Just (Aeson.String message) -> Just message
                _ -> Nothing
    pure $
        XeroHttpError $
            label
                <> " returned Xero "
                <> errorType
                <> maybe "" (": " <>) maybeMessage
                <> responseBodySuffix bodyExcerpt

decodeXeroEmptyResponse :: Text -> Response LByteString.ByteString -> IO (Either XeroClientError ())
decodeXeroEmptyResponse label response = do
    let statusCode = getResponseStatusCode response
    if statusCode < 200 || statusCode >= 300
        then do
            let bodyExcerpt = Text.take 500 (TextEncoding.decodeUtf8With lenientDecode (LByteString.toStrict (getResponseBody response)))
            pure (Left (XeroHttpError (label <> " failed with status " <> tshow statusCode <> responseBodySuffix bodyExcerpt)))
        else pure (Right ())

handleXeroHttpExceptions :: IO (Either XeroClientError value) -> IO (Either XeroClientError value)
handleXeroHttpExceptions action = do
    result <- Exception.try action
    pure case result of
        Left (err :: Exception.SomeException) -> Left (XeroHttpError (cs (show err)))
        Right value -> value

newtype XeroEmployeesResponse = XeroEmployeesResponse { unXeroEmployeesResponse :: [XeroEmployeeRef] }

instance Aeson.FromJSON XeroEmployeesResponse where
    parseJSON = parseXeroListResponse XeroEmployeesResponse "Employees"

newtype XeroEarningsRatesResponse = XeroEarningsRatesResponse { unXeroEarningsRatesResponse :: [XeroEarningsRateRef] }

instance Aeson.FromJSON XeroEarningsRatesResponse where
    parseJSON = parseXeroListResponse XeroEarningsRatesResponse "EarningsRates"

newtype XeroPayItemsResponse = XeroPayItemsResponse { unXeroPayItemsResponse :: [XeroEarningsRateRef] }

instance Aeson.FromJSON XeroPayItemsResponse where
    parseJSON = Aeson.withObject "XeroPayItemsResponse" \object -> do
        payItemsValue <- case firstPresent object ["PayItems", "payItems"] of
            Just value -> pure value
            Nothing    -> pure (Aeson.Object object)
        earningsRates <- extractEarningsRates payItemsValue
        pure (XeroPayItemsResponse earningsRates)

newtype XeroPayrollCalendarsResponse = XeroPayrollCalendarsResponse { unXeroPayrollCalendarsResponse :: [XeroPayrollCalendarRef] }

instance Aeson.FromJSON XeroPayrollCalendarsResponse where
    parseJSON = parseXeroListResponse XeroPayrollCalendarsResponse "PayrollCalendars"

newtype XeroTimesheetsResponse = XeroTimesheetsResponse { unXeroTimesheetsResponse :: [XeroTimesheetRef] }

instance Aeson.FromJSON XeroTimesheetsResponse where
    parseJSON = parseXeroListResponse XeroTimesheetsResponse "Timesheets"

newtype XeroTimesheetObjectResponse = XeroTimesheetObjectResponse { unXeroTimesheetObjectResponse :: XeroTimesheetRef }

instance Aeson.FromJSON XeroTimesheetObjectResponse where
    parseJSON value@(Aeson.Object object) =
        case firstPresent object ["Timesheet", "timesheet"] of
            Just timesheetValue -> XeroTimesheetObjectResponse <$> Aeson.parseJSON timesheetValue
            Nothing             -> XeroTimesheetObjectResponse <$> Aeson.parseJSON value
    parseJSON value = XeroTimesheetObjectResponse <$> Aeson.parseJSON value

parseXeroListResponse :: Aeson.FromJSON value => ([value] -> wrapped) -> Text -> Aeson.Value -> AesonTypes.Parser wrapped
parseXeroListResponse wrap key = \case
    Aeson.Array values -> wrap <$> mapM Aeson.parseJSON (Vector.toList values)
    Aeson.Object object -> do
        values <-
            case KeyMap.lookup (Key.fromText key) object of
                Just value -> Aeson.parseJSON value
                Nothing    -> fail ("Missing Xero response list: " <> cs key)
        wrap <$> mapM Aeson.parseJSON (values :: [Aeson.Value])
    _ -> fail "Expected Xero list response"

extractEarningsRates :: Aeson.Value -> AesonTypes.Parser [XeroEarningsRateRef]
extractEarningsRates = Aeson.withObject "Xero pay items" \object -> do
    values <-
        case firstPresent object ["EarningsRates", "earningsRates"] of
            Just value -> Aeson.parseJSON value
            Nothing    -> fail "Missing Xero pay items earnings rates"
    mapM Aeson.parseJSON (values :: [Aeson.Value])

requiredText :: Aeson.Object -> [Text] -> AesonTypes.Parser Text
requiredText object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> fail ("Missing required Xero field: " <> cs (Text.intercalate "/" keys))

optionalText :: Aeson.Object -> [Text] -> AesonTypes.Parser (Maybe Text)
optionalText object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> pure Nothing

optionalDay :: Aeson.Object -> [Text] -> AesonTypes.Parser (Maybe Day)
optionalDay object keys =
    case firstPresent object keys of
        Just Aeson.Null -> pure Nothing
        Just (Aeson.String value)
            | Text.null (Text.strip value) -> pure Nothing
            | otherwise -> Just <$> parseXeroDayText value
        Just value -> Aeson.parseJSON value
        Nothing -> pure Nothing

requiredDay :: Aeson.Object -> [Text] -> AesonTypes.Parser Day
requiredDay object keys =
    case firstPresent object keys of
        Just (Aeson.String value) -> parseXeroDayText value
        Just value                -> Aeson.parseJSON value
        Nothing                   -> fail ("Missing required Xero date field: " <> cs (Text.intercalate "/" keys))

optionalScientific :: Aeson.Object -> [Text] -> AesonTypes.Parser (Maybe Scientific)
optionalScientific object keys =
    case firstPresent object keys of
        Just Aeson.Null -> pure Nothing
        Just value      -> Aeson.parseJSON value
        Nothing         -> pure Nothing

optionalScientificList :: Aeson.Object -> [Text] -> AesonTypes.Parser [Scientific]
optionalScientificList object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> pure []

optionalTimesheetLines :: Aeson.Object -> AesonTypes.Parser [XeroTimesheetLineRef]
optionalTimesheetLines object =
    case firstPresent object ["TimesheetLines", "timesheetLines"] of
        Just value -> Aeson.parseJSON value
        Nothing    -> pure []

parseXeroDayText :: Text -> AesonTypes.Parser Day
parseXeroDayText value =
    case parseIsoDay value <|> parseMicrosoftJsonDate value of
        Just day -> pure day
        Nothing  -> fail ("could not parse Xero date: " <> cs value)

parseIsoDay :: Text -> Maybe Day
parseIsoDay value =
    parseTimeM True defaultTimeLocale "%Y-%m-%d" (cs value)

parseMicrosoftJsonDate :: Text -> Maybe Day
parseMicrosoftJsonDate value = do
    body <- Text.stripPrefix "/Date(" value
    let millisecondsText = Text.takeWhile (\char -> isDigit char || char == '-') body
    milliseconds <- readMaybe (cs millisecondsText) :: Maybe Integer
    pure (utctDay (posixSecondsToUTCTime (fromIntegral milliseconds / 1000)))

employeeDisplayName :: Aeson.Object -> AesonTypes.Parser Text
employeeDisplayName object =
    optionalText object ["Name", "name", "DisplayName", "displayName"] >>= \case
        Just name | not (Text.null (Text.strip name)) -> pure name
        _ -> do
            firstName <- optionalText object ["FirstName", "firstName"]
            lastName <- optionalText object ["LastName", "lastName"]
            let name = Text.strip (Text.unwords (catMaybes [firstName, lastName]))
            if Text.null name
                then requiredText object ["EmployeeID", "employeeID", "employeeId"]
                else pure name

activeFromObject :: Aeson.Object -> AesonTypes.Parser Bool
activeFromObject object =
    ((not <$> requiredBool object ["IsArchived", "isArchived"]) <|> requiredBool object ["IsActive", "isActive"] <|> requiredBool object ["CurrentRecord", "currentRecord"]) <|> pure True

requiredBool :: Aeson.Object -> [Text] -> AesonTypes.Parser Bool
requiredBool object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> fail ("Missing required Xero boolean field: " <> cs (Text.intercalate "/" keys))

firstPresent :: Aeson.Object -> [Text] -> Maybe Aeson.Value
firstPresent object keys =
    asum (map (\key -> KeyMap.lookup (Key.fromText key) object) keys)
