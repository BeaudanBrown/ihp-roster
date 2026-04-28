module Application.Helper.Xero
    ( XeroClient (..)
    , XeroClientError (..)
    , XeroConfig (..)
    , XeroEarningsRateRef (..)
    , XeroEmployeeRef (..)
    , XeroPayrollCalendarRef (..)
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
import Control.Applicative ((<|>))
import qualified "crypton" Crypto.Hash as Hash
import "crypton" Crypto.Cipher.AES (AES256)
import "crypton" Crypto.Cipher.Types (IV, cipherInit, ctrCombine, makeIV)
import "crypton" Crypto.Error (CryptoError, CryptoFailable (..))
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
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Text.Encoding.Error (lenientDecode)
import qualified Data.Vector as Vector
import Data.Time.Calendar (Day)
import Data.Time.Clock (utctDay)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Text.Read (readMaybe)
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
    { xeroEmployeeId        :: !Text
    , xeroEmployeeName      :: !Text
    , xeroEmployeeEmail     :: !(Maybe Text)
    , xeroEmployeeStatus    :: !(Maybe Text)
    , xeroEmployeeCalendarId :: !(Maybe Text)
    , xeroEmployeeRaw       :: !Aeson.Value
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
    { xeroEarningsRateId     :: !Text
    , xeroEarningsRateName   :: !Text
    , xeroEarningsRateType   :: !(Maybe Text)
    , xeroEarningsRateRateType :: !(Maybe Text)
    , xeroEarningsRateAccountCode :: !(Maybe Text)
    , xeroEarningsRateIsActive :: !Bool
    , xeroEarningsRateRaw    :: !Aeson.Value
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
    { xeroPayrollCalendarId      :: !Text
    , xeroPayrollCalendarName    :: !Text
    , xeroPayrollCalendarType    :: !(Maybe Text)
    , xeroPayrollCalendarStartDate :: !(Maybe Day)
    , xeroPayrollCalendarPaymentDate :: !(Maybe Day)
    , xeroPayrollCalendarRaw     :: !Aeson.Value
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
        , deleteXeroConnection = deleteXeroConnectionRequest
        , refreshXeroToken = refreshXeroTokenRequest
        , fetchPayrollEmployees = fetchPayrollEmployeesRequest
        , fetchEarningsRates = fetchEarningsRatesRequest
        , fetchPayrollCalendars = fetchPayrollCalendarsRequest
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
    fmap (fmap unXeroEmployeesResponse) $
        getXeroPayrollRequest "Xero payroll employees request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/Employees"

fetchEarningsRatesRequest :: Text -> Text -> IO (Either XeroClientError [XeroEarningsRateRef])
fetchEarningsRatesRequest accessToken tenantId =
    fmap (fmap unXeroPayItemsResponse) $
        getXeroPayrollRequest "Xero payroll pay items request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/PayItems"

fetchPayrollCalendarsRequest :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
fetchPayrollCalendarsRequest accessToken tenantId =
    fmap (fmap unXeroPayrollCalendarsResponse) $
        getXeroPayrollRequest "Xero payroll calendars request" accessToken tenantId "https://api.xero.com/payroll.xro/1.0/PayrollCalendars"

getXeroPayrollRequest :: Aeson.FromJSON value => Text -> Text -> Text -> String -> IO (Either XeroClientError value)
getXeroPayrollRequest label accessToken tenantId url =
    handleXeroHttpExceptions do
        request <- parseRequest url
        let requestWithHeaders =
                request
                    |> setRequestMethod "GET"
                    |> setRequestHeader "Authorization" ["Bearer " <> TextEncoding.encodeUtf8 accessToken]
                    |> setRequestHeader "Xero-Tenant-Id" [TextEncoding.encodeUtf8 tenantId]
                    |> setRequestHeader "Accept" ["application/json"]
        response <- httpLBS requestWithHeaders
        decodeXeroResponse label response

basicAuthorizationHeader :: XeroConfig -> ByteString
basicAuthorizationHeader config =
    "Basic " <> Base64.encode (TextEncoding.encodeUtf8 (config.clientId <> ":" <> config.clientSecret))

decodeXeroResponse :: Aeson.FromJSON value => Text -> Response LByteString.ByteString -> IO (Either XeroClientError value)
decodeXeroResponse label response = do
    let statusCode = getResponseStatusCode response
    if statusCode < 200 || statusCode >= 300
        then do
            let bodyExcerpt = Text.take 500 (TextEncoding.decodeUtf8With lenientDecode (LByteString.toStrict (getResponseBody response)))
            pure (Left (XeroHttpError (label <> " failed with status " <> tshow statusCode <> responseBodySuffix bodyExcerpt)))
        else case Aeson.eitherDecode (getResponseBody response) of
            Left err -> pure (Left (XeroDecodeError (cs err)))
            Right decoded -> pure (Right decoded)

responseBodySuffix :: Text -> Text
responseBodySuffix bodyExcerpt
    | Text.null (Text.strip bodyExcerpt) = ""
    | otherwise = ": " <> Text.strip bodyExcerpt

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
