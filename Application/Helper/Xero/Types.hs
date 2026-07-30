module Application.Helper.Xero.Types
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
    , XeroEmployeesResponse (..)
    , XeroEarningsRatesResponse (..)
    , XeroPayItemsResponse (..)
    , XeroPayrollCalendarsResponse (..)
    , XeroAccountsResponse (..)
    , firstPresent
    )
where

import Control.Applicative ((<|>))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import Data.Char (isDigit)
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime, utctDay)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import qualified Data.Time.Format as TimeFormat
import qualified Data.Vector as Vector
import IHP.Prelude
import Network.HTTP.Types.Header (HeaderName)
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
    { xeroEmployeeId     :: !Text
    , xeroEmployeeName   :: !Text
    , xeroEmployeeEmail  :: !(Maybe Text)
    , xeroEmployeeStatus :: !(Maybe Text)
    , xeroEmployeeRaw    :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroEmployeeRef where
    parseJSON value@(Aeson.Object object) =
        XeroEmployeeRef
            <$> requiredText object ["EmployeeID", "employeeID", "employeeId"]
            <*> employeeDisplayName object
            <*> optionalText object ["Email", "email"]
            <*> optionalText object ["Status", "status"]
            <*> pure value
    parseJSON _ = fail "Expected Xero employee object"

data XeroEarningsRateRef = XeroEarningsRateRef
    { xeroEarningsRateId          :: !Text
    , xeroEarningsRateName        :: !Text
    , xeroEarningsRateType        :: !(Maybe Text)
    , xeroEarningsRateRateType    :: !(Maybe Text)
    , xeroEarningsRateAccountCode :: !(Maybe Text)
    , xeroEarningsRateTypeOfUnits :: !(Maybe Text)
    , xeroEarningsRateRatePerUnit :: !(Maybe Scientific)
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
            <*> optionalText object ["TypeOfUnits", "typeOfUnits"]
            <*> optionalScientific object ["RatePerUnit", "ratePerUnit"]
            <*> activeFromObject object
            <*> pure value
    parseJSON _ = fail "Expected Xero earnings rate object"

data XeroAccountRef = XeroAccountRef
    { xeroAccountId     :: !Text
    , xeroAccountCode   :: !(Maybe Text)
    , xeroAccountName   :: !Text
    , xeroAccountType   :: !(Maybe Text)
    , xeroAccountStatus :: !(Maybe Text)
    , xeroAccountRaw    :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroAccountRef where
    parseJSON value@(Aeson.Object object) =
        XeroAccountRef
            <$> requiredText object ["AccountID", "accountID", "accountId"]
            <*> optionalText object ["Code", "code"]
            <*> requiredText object ["Name", "name"]
            <*> optionalText object ["Type", "type"]
            <*> optionalText object ["Status", "status"]
            <*> pure value
    parseJSON _ = fail "Expected Xero account object"

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

data XeroPayRunRef = XeroPayRunRef
    { xeroPayRunId          :: !Text
    , xeroPayRunCalendarId  :: !Text
    , xeroPayRunPeriodStart :: !Day
    , xeroPayRunPeriodEnd   :: !Day
    , xeroPayRunPaymentDate :: !(Maybe Day)
    , xeroPayRunStatus      :: !(Maybe Text)
    , xeroPayRunRaw         :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroPayRunRef where
    parseJSON value@(Aeson.Object object) =
        XeroPayRunRef
            <$> requiredText object ["PayRunID", "payRunID", "payRunId"]
            <*> requiredText object ["PayrollCalendarID", "payrollCalendarID", "payrollCalendarId"]
            <*> requiredDay object ["PayRunPeriodStartDate", "payRunPeriodStartDate", "PeriodStartDate", "periodStartDate"]
            <*> requiredDay object ["PayRunPeriodEndDate", "payRunPeriodEndDate", "PeriodEndDate", "periodEndDate"]
            <*> optionalDay object ["PaymentDate", "paymentDate"]
            <*> optionalText object ["PayRunStatus", "payRunStatus", "Status", "status"]
            <*> pure value
    parseJSON _ = fail "Expected Xero pay run object"

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

data XeroPayRunQuery = XeroPayRunQuery
    { xeroPayRunIfModifiedSince :: !(Maybe UTCTime)
    , xeroPayRunWhere           :: !(Maybe Text)
    , xeroPayRunOrder           :: !(Maybe Text)
    , xeroPayRunPage            :: !(Maybe Int)
    }
    deriving (Eq, Show)

data XeroRequestBody
    = XeroJsonBody Aeson.Value
    | XeroFormBody [(ByteString, ByteString)]
    deriving (Eq, Show)

data XeroHttpRequest = XeroHttpRequest
    { xeroRequestMethod  :: !ByteString
    , xeroRequestUrl     :: !Text
    , xeroRequestHeaders :: ![(HeaderName, ByteString)]
    , xeroRequestBody    :: !(Maybe XeroRequestBody)
    }
    deriving (Eq, Show)

data XeroRequestBaseUrls = XeroRequestBaseUrls
    { xeroIdentityTokenUrl  :: !Text
    , xeroConnectionsUrl    :: !Text
    , xeroPayrollBaseUrl    :: !Text
    , xeroPayrollV2BaseUrl  :: !Text
    , xeroAccountingBaseUrl :: !Text
    }
    deriving (Eq, Show)

data XeroRetryAfter
    = XeroRetryAfterDelay !Int
    | XeroRetryAfterAt !UTCTime
    deriving (Eq, Show)

data XeroClientError
    = XeroHttpError Text
    | XeroHttpResponseError
        { statusCode      :: !Int
        , retryAfter      :: !(Maybe XeroRetryAfter)
        , customerMessage :: !Text
        }
    | XeroSemanticError Text
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
    , fetchEarningsRatesPage :: Text -> Text -> Int -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchPayrollCalendars :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
    , fetchAccounts :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , fetchPayrollSettingsAccounts :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , fetchPayRuns :: Text -> Text -> XeroPayRunQuery -> IO (Either XeroClientError [XeroPayRunRef])
    , createPayItem :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchTimesheets :: Text -> Text -> XeroTimesheetQuery -> IO (Either XeroClientError [XeroTimesheetRef])
    , fetchTimesheet :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetRef)
    , createTimesheet :: Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
    , updateTimesheet :: Text -> Text -> Text -> Text -> Aeson.Value -> IO (Either XeroClientError [XeroTimesheetRef])
    }

newtype XeroEmployeesResponse = XeroEmployeesResponse { unXeroEmployeesResponse :: [XeroEmployeeRef] }

instance Aeson.FromJSON XeroEmployeesResponse where
    parseJSON = parseXeroListResponse XeroEmployeesResponse "Employees"

newtype XeroEarningsRatesResponse = XeroEarningsRatesResponse { unXeroEarningsRatesResponse :: [XeroEarningsRateRef] }

instance Aeson.FromJSON XeroEarningsRatesResponse where
    parseJSON value@(Aeson.Object object) =
        case firstPresent object ["EarningsRates", "earningsRates"] of
            Just ratesValue -> do
                rates <- Aeson.parseJSON ratesValue
                pure (XeroEarningsRatesResponse rates)
            Nothing -> do
                rate <- Aeson.parseJSON value
                pure (XeroEarningsRatesResponse [rate])
    parseJSON value = parseXeroListResponse XeroEarningsRatesResponse "EarningsRates" value

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

newtype XeroAccountsResponse = XeroAccountsResponse { unXeroAccountsResponse :: [XeroAccountRef] }

instance Aeson.FromJSON XeroAccountsResponse where
    parseJSON = parseXeroListResponse XeroAccountsResponse "Accounts"

newtype XeroPayrollSettingsAccountsResponse = XeroPayrollSettingsAccountsResponse { unXeroPayrollSettingsAccountsResponse :: [XeroAccountRef] }

instance Aeson.FromJSON XeroPayrollSettingsAccountsResponse where
    parseJSON = Aeson.withObject "XeroPayrollSettingsAccountsResponse" \object -> do
        settingsValue <- case firstPresent object ["Settings", "settings"] of
            Just value -> pure value
            Nothing    -> fail "Missing Xero payroll settings"
        accounts <- Aeson.withObject "Xero payroll settings" (\settingsObject -> do
            accountsValue <- case firstPresent settingsObject ["Accounts", "accounts"] of
                Just value -> pure value
                Nothing    -> fail "Missing Xero payroll settings accounts"
            Aeson.parseJSON accountsValue) settingsValue
        pure (XeroPayrollSettingsAccountsResponse accounts)

newtype XeroPayRunsResponse = XeroPayRunsResponse { unXeroPayRunsResponse :: [XeroPayRunRef] }

instance Aeson.FromJSON XeroPayRunsResponse where
    parseJSON = parseXeroListResponse XeroPayRunsResponse "PayRuns"

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
