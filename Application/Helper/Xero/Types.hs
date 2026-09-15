module Application.Helper.Xero.Types
    ( XeroClient (..)
    , XeroConnectionClient (..)
    , XeroPayrollClient (..)
    , XeroClientError (..)
    , XeroRetryAfter (..)
    , XeroConfig (..)
    , XeroAccountRef (..)
    , XeroEarningsRateCreate (..)
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
    , XeroTimesheetCreateProtocol (..)
    , XeroTimesheetDetailRef (..)
    , XeroTimesheetDraft (..)
    , XeroTimesheetDraftLine (..)
    , XeroTimesheetLineRef (..)
    , XeroTimesheetObjectResponse (..)
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
    , xeroConnectionClient
    , xeroPayrollClient
    )
where

import Application.Error.Parser (parserFailure)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import Data.Char (isDigit)
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
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
    parseJSON _ = parserFailure "Expected Xero employee object"

data XeroEarningsRateCreate = XeroEarningsRateCreate
    { xeroEarningsRateCreateName             :: !Text
    , xeroEarningsRateCreateTypeOfUnits      :: !Text
    , xeroEarningsRateCreateEarningsType     :: !Text
    , xeroEarningsRateCreateRateType         :: !Text
    , xeroEarningsRateCreateRatePerUnit      :: !(Maybe Scientific)
    , xeroEarningsRateCreateIsSubjectToTax   :: !Bool
    , xeroEarningsRateCreateIsSubjectToSuper :: !Bool
    , xeroEarningsRateCreateIsReportableAsW1 :: !Bool
    , xeroEarningsRateCreateIsQualifyingEarnings :: !Bool
    , xeroEarningsRateCreateAccountCode      :: !(Maybe Text)
    , xeroEarningsRateCreateExpenseAccountId :: !(Maybe Text)
    }
    deriving (Eq, Show)

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
    parseJSON _ = parserFailure "Expected Xero earnings rate object"

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
    parseJSON _ = parserFailure "Expected Xero account object"

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
    parseJSON _ = parserFailure "Expected Xero payroll calendar object"

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
    parseJSON _ = parserFailure "Expected Xero pay run object"

data XeroTimesheetLineRef = XeroTimesheetLineRef
    { xeroTimesheetLineId             :: !(Maybe Text)
    , xeroTimesheetLineDate           :: !Day
    , xeroTimesheetLineEarningsRateId :: !Text
    , xeroTimesheetLineTrackingItemId :: !(Maybe Text)
    , xeroTimesheetLineQuantity       :: !Scientific
    , xeroTimesheetLineRaw            :: !Aeson.Value
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTimesheetLineRef where
    parseJSON value@(Aeson.Object object) =
        XeroTimesheetLineRef
            <$> optionalText object ["TimesheetLineID", "timesheetLineID", "timesheetLineId"]
            <*> requiredDay object ["Date", "date"]
            <*> requiredText object ["EarningsRateID", "earningsRateID", "earningsRateId"]
            <*> optionalText object ["TrackingItemID", "trackingItemID", "trackingItemId"]
            <*> requiredScientific object ["NumberOfUnits", "numberOfUnits"]
            <*> pure value
    parseJSON _ = parserFailure "Expected Xero v2 timesheet line object"

data XeroTimesheetRef = XeroTimesheetRef
    { xeroTimesheetId         :: !(Maybe Text)
    , xeroTimesheetEmployeeId :: !Text
    , xeroTimesheetStartDate  :: !Day
    , xeroTimesheetEndDate    :: !Day
    , xeroTimesheetStatus     :: !(Maybe Text)
    , xeroTimesheetHours      :: !(Maybe Scientific)
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
            <*> optionalScientific object ["Hours", "hours", "TotalHours", "totalHours"]
            <*> pure value
    parseJSON _ = parserFailure "Expected Xero timesheet summary object"

data XeroTimesheetDetailRef = XeroTimesheetDetailRef
    { xeroTimesheetDetailSummary :: !XeroTimesheetRef
    , xeroTimesheetLines         :: ![XeroTimesheetLineRef]
    }
    deriving (Eq, Show)

instance Aeson.FromJSON XeroTimesheetDetailRef where
    parseJSON value@(Aeson.Object object) = do
        summary <- Aeson.parseJSON value
        lines <- requiredTimesheetLines summary.xeroTimesheetStartDate object
        pure XeroTimesheetDetailRef
            { xeroTimesheetDetailSummary = summary
            , xeroTimesheetLines = lines
            }
    parseJSON _ = parserFailure "Expected Xero timesheet detail object"

data XeroTimesheetCreateProtocol
    = XeroTimesheetCreateV1
    | XeroTimesheetCreateV2
    deriving (Eq, Show)

data XeroTimesheetDraftLine = XeroTimesheetDraftLine
    { xeroTimesheetDraftLineEarningsRateId :: !Text
    , xeroTimesheetDraftLineTrackingItemId :: !(Maybe Text)
    , xeroTimesheetDraftLineQuantities     :: ![Scientific]
    }
    deriving (Eq, Show)

data XeroTimesheetDraft = XeroTimesheetDraft
    { xeroTimesheetDraftPayrollCalendarId :: !(Maybe Text)
    , xeroTimesheetDraftEmployeeId        :: !Text
    , xeroTimesheetDraftStartDate         :: !Day
    , xeroTimesheetDraftEndDate           :: !Day
    , xeroTimesheetDraftLines             :: ![XeroTimesheetDraftLine]
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

data XeroConnectionClient = XeroConnectionClient
    { connectionExchangeCodeForToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    , connectionFetchConnectedTenants :: Text -> IO (Either XeroClientError [XeroTenant])
    , connectionDeleteXeroConnection :: Text -> Text -> IO (Either XeroClientError ())
    , connectionRefreshXeroToken :: XeroConfig -> Text -> IO (Either XeroClientError XeroTokenResponse)
    }

data XeroPayrollClient = XeroPayrollClient
    { payrollFetchEmployees :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
    , payrollFetchEarningsRates :: Text -> Text -> IO (Either XeroClientError [XeroEarningsRateRef])
    , payrollFetchEarningsRatesPage :: Text -> Text -> Int -> IO (Either XeroClientError [XeroEarningsRateRef])
    , payrollFetchCalendars :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
    , payrollFetchAccounts :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , payrollFetchSettingsAccounts :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , payrollFetchPayRuns :: Text -> Text -> XeroPayRunQuery -> IO (Either XeroClientError [XeroPayRunRef])
    , payrollCreateEarningsRate :: Text -> Text -> Text -> XeroEarningsRateCreate -> IO (Either XeroClientError [XeroEarningsRateRef])
    , payrollFetchTimesheetsForPeriod :: Text -> Text -> Maybe Text -> Day -> Day -> IO (Either XeroClientError [XeroTimesheetRef])
    , payrollFetchTimesheetDetail :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetDetailRef)
    , payrollCreateTimesheetDraftV1 :: Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    , payrollCreateTimesheetDraftV2 :: Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    , payrollReplaceTimesheetDraft :: Text -> Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    }

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
    , createEarningsRate :: Text -> Text -> Text -> XeroEarningsRateCreate -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchTimesheetsForPeriod :: Text -> Text -> Maybe Text -> Day -> Day -> IO (Either XeroClientError [XeroTimesheetRef])
    , fetchTimesheetDetail :: Text -> Text -> Text -> IO (Either XeroClientError XeroTimesheetDetailRef)
    , createTimesheetDraftV1 :: Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    , createTimesheetDraftV2 :: Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    , replaceTimesheetDraft :: Text -> Text -> Text -> Text -> XeroTimesheetDraft -> IO (Either XeroClientError [XeroTimesheetRef])
    }

xeroConnectionClient :: XeroClient -> XeroConnectionClient
xeroConnectionClient client =
    XeroConnectionClient
        { connectionExchangeCodeForToken = client.exchangeCodeForToken
        , connectionFetchConnectedTenants = client.fetchConnectedTenants
        , connectionDeleteXeroConnection = client.deleteXeroConnection
        , connectionRefreshXeroToken = client.refreshXeroToken
        }

xeroPayrollClient :: XeroClient -> XeroPayrollClient
xeroPayrollClient client =
    XeroPayrollClient
        { payrollFetchEmployees = client.fetchPayrollEmployees
        , payrollFetchEarningsRates = client.fetchEarningsRates
        , payrollFetchEarningsRatesPage = client.fetchEarningsRatesPage
        , payrollFetchCalendars = client.fetchPayrollCalendars
        , payrollFetchAccounts = client.fetchAccounts
        , payrollFetchSettingsAccounts = client.fetchPayrollSettingsAccounts
        , payrollFetchPayRuns = client.fetchPayRuns
        , payrollCreateEarningsRate = client.createEarningsRate
        , payrollFetchTimesheetsForPeriod = client.fetchTimesheetsForPeriod
        , payrollFetchTimesheetDetail = client.fetchTimesheetDetail
        , payrollCreateTimesheetDraftV1 = client.createTimesheetDraftV1
        , payrollCreateTimesheetDraftV2 = client.createTimesheetDraftV2
        , payrollReplaceTimesheetDraft = client.replaceTimesheetDraft
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
            Nothing    -> parserFailure "Missing Xero payroll settings"
        accounts <- Aeson.withObject "Xero payroll settings" (\settingsObject -> do
            accountsValue <- case firstPresent settingsObject ["Accounts", "accounts"] of
                Just value -> pure value
                Nothing    -> parserFailure "Missing Xero payroll settings accounts"
            Aeson.parseJSON accountsValue) settingsValue
        pure (XeroPayrollSettingsAccountsResponse accounts)

newtype XeroPayRunsResponse = XeroPayRunsResponse { unXeroPayRunsResponse :: [XeroPayRunRef] }

instance Aeson.FromJSON XeroPayRunsResponse where
    parseJSON = parseXeroListResponse XeroPayRunsResponse "PayRuns"

newtype XeroTimesheetsResponse = XeroTimesheetsResponse { unXeroTimesheetsResponse :: [XeroTimesheetRef] }

instance Aeson.FromJSON XeroTimesheetsResponse where
    parseJSON value@(Aeson.Object object) =
        case firstPresent object ["Timesheets", "timesheets"] of
            Just timesheetsValue -> XeroTimesheetsResponse <$> Aeson.parseJSON timesheetsValue
            Nothing             -> parseXeroListResponse XeroTimesheetsResponse "Timesheets" value
    parseJSON value = parseXeroListResponse XeroTimesheetsResponse "Timesheets" value

newtype XeroTimesheetObjectResponse = XeroTimesheetObjectResponse { unXeroTimesheetObjectResponse :: XeroTimesheetDetailRef }

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
                Nothing    -> parserFailure ("Missing Xero response list: " <> cs key)
        wrap <$> mapM Aeson.parseJSON (values :: [Aeson.Value])
    _ -> parserFailure "Expected Xero list response"

extractEarningsRates :: Aeson.Value -> AesonTypes.Parser [XeroEarningsRateRef]
extractEarningsRates = Aeson.withObject "Xero pay items" \object -> do
    values <-
        case firstPresent object ["EarningsRates", "earningsRates"] of
            Just value -> Aeson.parseJSON value
            Nothing    -> parserFailure "Missing Xero pay items earnings rates"
    mapM Aeson.parseJSON (values :: [Aeson.Value])

requiredText :: Aeson.Object -> [Text] -> AesonTypes.Parser Text
requiredText object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> parserFailure ("Missing required Xero field: " <> cs (Text.intercalate "/" keys))

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
        Nothing                   -> parserFailure ("Missing required Xero date field: " <> cs (Text.intercalate "/" keys))

optionalScientific :: Aeson.Object -> [Text] -> AesonTypes.Parser (Maybe Scientific)
optionalScientific object keys =
    case firstPresent object keys of
        Just Aeson.Null -> pure Nothing
        Just value      -> Aeson.parseJSON value
        Nothing         -> pure Nothing

requiredScientific :: Aeson.Object -> [Text] -> AesonTypes.Parser Scientific
requiredScientific object keys =
    case firstPresent object keys of
        Just value -> Aeson.parseJSON value
        Nothing    -> parserFailure ("Missing required Xero number field: " <> cs (Text.intercalate "/" keys))

requiredTimesheetLines :: Day -> Aeson.Object -> AesonTypes.Parser [XeroTimesheetLineRef]
requiredTimesheetLines periodStart object =
    case firstPresent object ["TimesheetLines", "timesheetLines"] of
        Just (Aeson.Array values) -> concat <$> mapM parseProtocolLine (Vector.toList values)
        Just _ -> parserFailure "Expected Xero timesheet detail lines array"
        Nothing -> parserFailure "Missing Xero timesheet detail lines"
  where
    parseProtocolLine value@(Aeson.Object lineObject) =
        case firstPresent lineObject ["NumberOfUnits", "numberOfUnits"] of
            Just (Aeson.Array quantities) -> do
                earningsRateId <- requiredText lineObject ["EarningsRateID", "earningsRateID", "earningsRateId"]
                trackingItemId <- optionalText lineObject ["TrackingItemID", "trackingItemID", "trackingItemId"]
                lineId <- optionalText lineObject ["TimesheetLineID", "timesheetLineID", "timesheetLineId"]
                units <- mapM Aeson.parseJSON (Vector.toList quantities)
                pure
                    [ XeroTimesheetLineRef
                        { xeroTimesheetLineId = lineId
                        , xeroTimesheetLineDate = addDays (fromIntegral offset) periodStart
                        , xeroTimesheetLineEarningsRateId = earningsRateId
                        , xeroTimesheetLineTrackingItemId = trackingItemId
                        , xeroTimesheetLineQuantity = quantity
                        , xeroTimesheetLineRaw = value
                        }
                    | (offset, quantity) <- zip [0 :: Int ..] units
                    ]
            _ -> (: []) <$> Aeson.parseJSON value
    parseProtocolLine _ = parserFailure "Expected Xero timesheet line object"

parseXeroDayText :: Text -> AesonTypes.Parser Day
parseXeroDayText value =
    case parseIsoDay value <|> parseIsoDateTimeDay value <|> parseMicrosoftJsonDate value of
        Just day -> pure day
        Nothing  -> parserFailure ("could not parse Xero date: " <> cs value)

parseIsoDay :: Text -> Maybe Day
parseIsoDay value =
    parseTimeM True defaultTimeLocale "%Y-%m-%d" (cs value)

parseIsoDateTimeDay :: Text -> Maybe Day
parseIsoDateTimeDay value =
    localDay <$> parseLocalDateTime "%Y-%m-%dT%H:%M:%S%Q"
        <|> localDay <$> parseLocalDateTime "%Y-%m-%dT%H:%M:%S%QZ"
        <|> (localDay . zonedTimeToLocalTime) <$> parseZonedDateTime "%Y-%m-%dT%H:%M:%S%Q%Ez"
  where
    rawValue = cs value
    parseLocalDateTime format = parseTimeM True defaultTimeLocale format rawValue :: Maybe LocalTime
    parseZonedDateTime format = parseTimeM True defaultTimeLocale format rawValue :: Maybe ZonedTime

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
        Nothing    -> parserFailure ("Missing required Xero boolean field: " <> cs (Text.intercalate "/" keys))

firstPresent :: Aeson.Object -> [Text] -> Maybe Aeson.Value
firstPresent object keys =
    asum (map (\key -> KeyMap.lookup (Key.fromText key) object) keys)
