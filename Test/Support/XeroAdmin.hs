module Test.Support.XeroAdmin where

import Application.Helper.Xero
import Config
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.IORef as IORef
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import Test.Support
import qualified Test.XeroMock as XeroMock
import qualified Test.XeroTimesheetPreviewSpec as Preview

testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "test-client-id"
        , clientSecret = "test-client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "test-token-encryption-key"
        }

withAdminStrictXeroMock :: (XeroRequestBaseUrls -> IO a) -> IO a
withAdminStrictXeroMock action = do
    (identitySpec, payrollSpec) <- XeroMock.loadXeroOpenApiSpecs
    XeroMock.withStrictXeroMock identitySpec payrollSpec action

successfulXeroClient :: XeroTokenResponse -> [XeroTenant] -> XeroClient
successfulXeroClient tokenResponse tenants =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right tenants)
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right [])
        , fetchEarningsRates = \_ _ -> pure (Right [])
        , fetchEarningsRatesPage = \_ _ _ -> pure (Right [])
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        , fetchAccounts = \_ _ -> pure (Right [])
        , fetchPayrollSettingsAccounts = \_ _ -> pure (Right [])
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheetsForPeriod = \_ _ _ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }

referenceSyncXeroClientForFixture :: (?modelContext :: ModelContext) => XeroTokenResponse -> XeroConnection -> IO XeroClient
referenceSyncXeroClientForFixture tokenResponse connection = do
    employees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    earningsRates <-
        query @XeroEarningsRate
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    payrollCalendars <-
        query @XeroPayrollCalendar
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    pure $
        referenceSyncXeroClient
            tokenResponse
            (map xeroEmployeeRefFromRecord employees)
            (map xeroEarningsRateRefFromRecord earningsRates)
            (map xeroPayrollCalendarRefFromRecord payrollCalendars)

xeroEmployeeRefFromRecord :: XeroEmployee -> XeroEmployeeRef
xeroEmployeeRefFromRecord employee =
    XeroEmployeeRef employee.xeroEmployeeId employee.displayName employee.email employee.status employee.rawPayload

xeroEarningsRateRefFromRecord :: XeroEarningsRate -> XeroEarningsRateRef
xeroEarningsRateRefFromRecord earningsRate =
    XeroEarningsRateRef earningsRate.xeroEarningsRateId earningsRate.name earningsRate.earningsType earningsRate.rateType earningsRate.accountCode Nothing Nothing earningsRate.isActive earningsRate.rawPayload

xeroPayrollCalendarRefFromRecord :: XeroPayrollCalendar -> XeroPayrollCalendarRef
xeroPayrollCalendarRefFromRecord payrollCalendar =
    XeroPayrollCalendarRef payrollCalendar.xeroPayrollCalendarId payrollCalendar.name payrollCalendar.calendarType payrollCalendar.startDate payrollCalendar.paymentDate payrollCalendar.rawPayload

referenceSyncXeroClient :: XeroTokenResponse -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> XeroClient
referenceSyncXeroClient tokenResponse employees earningsRates payrollCalendars =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right tokenResponse)
        , fetchConnectedTenants = \_ -> pure (Right [])
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure (Right tokenResponse)
        , fetchPayrollEmployees = \_ _ -> pure (Right employees)
        , fetchEarningsRates = \_ _ -> pure (Right earningsRates)
        , fetchEarningsRatesPage = \_ _ page -> pure (Right (if page == 1 then earningsRates else []))
        , fetchPayrollCalendars = \_ _ -> pure (Right payrollCalendars)
        , fetchAccounts = \_ _ -> pure (Right (accountRefsFromEarningsRates earningsRates))
        , fetchPayrollSettingsAccounts = \_ _ -> pure (Right (wagesExpenseAccountRefsFromEarningsRates earningsRates))
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheetsForPeriod = \_ _ _ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unused"))
        , createTimesheet = \_ _ _ _ -> pure (Right [])
        , updateTimesheet = \_ _ _ _ _ -> pure (Right [])
        }

accountRefsFromEarningsRates :: [XeroEarningsRateRef] -> [XeroAccountRef]
accountRefsFromEarningsRates earningsRates =
    earningsRates
        |> map (.xeroEarningsRateAccountCode)
        |> catMaybes
        |> map Text.strip
        |> filter (not . Text.null)
        |> List.nub
        |> map (\accountCode -> XeroAccountRef ("account-" <> accountCode) (Just accountCode) "Wages and Salaries" (Just "EXPENSE") (Just "ACTIVE") (Aeson.object ["Code" Aeson..= accountCode]))

wagesExpenseAccountRefsFromEarningsRates :: [XeroEarningsRateRef] -> [XeroAccountRef]
wagesExpenseAccountRefsFromEarningsRates earningsRates =
    case accountRefsFromEarningsRates earningsRates of
        account : _ -> [account { xeroAccountType = Just "WAGESEXPENSE" }]
        []          -> []

payItemCreateXeroClient :: XeroTokenResponse -> IORef.IORef [(Text, Aeson.Value)] -> XeroClient
payItemCreateXeroClient tokenResponse requestsRef =
    payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef Nothing

payItemCreateXeroClientWithVerifiedLimit :: XeroTokenResponse -> IORef.IORef [(Text, Aeson.Value)] -> Maybe Int -> XeroClient
payItemCreateXeroClientWithVerifiedLimit tokenResponse requestsRef maybeVerifiedLimit =
    (referenceSyncXeroClient tokenResponse [] [] [])
        { fetchEarningsRates = \_ _ -> do
            requests <- IORef.readIORef requestsRef
            let createdRates = concatMap (xeroPayItemRequestEarningsRateRefs . snd) requests
            pure (Right (maybe createdRates (`take` createdRates) maybeVerifiedLimit))
        , createPayItem = \_ _ idempotencyKey body -> do
            IORef.modifyIORef' requestsRef (<> [(idempotencyKey, body)])
            pure (Right [])
        }


xeroPayItemRequestEarningsRateRefs :: Aeson.Value -> [XeroEarningsRateRef]
xeroPayItemRequestEarningsRateRefs body =
    maybe [] (: []) (AesonTypes.parseMaybe earningsRateRefFromValue body)

earningsRateRefFromValue :: Aeson.Value -> AesonTypes.Parser XeroEarningsRateRef
earningsRateRefFromValue value@(Aeson.Object earningsRate) = do
    name <- earningsRate Aeson..: "Name"
    accountCode <- earningsRate Aeson..:? "AccountCode"
    expenseAccountId <- earningsRate Aeson..:? "ExpenseAccountID"
    let resolvedAccountCode = case accountCode of
            Just code -> Just code
            Nothing -> xeroTestAccountCodeFromExpenseAccountId expenseAccountId
    pure $
        XeroEarningsRateRef
            ("created-" <> name)
            name
            (Just "ORDINARYTIMEEARNINGS")
            (Just "RATEPERUNIT")
            resolvedAccountCode
            (Just "Hours")
            (Just 30)
            True
            value
earningsRateRefFromValue _ = fail "Expected earnings rate"





xeroTestAccountCodeFromExpenseAccountId :: Maybe Text -> Maybe Text
xeroTestAccountCodeFromExpenseAccountId (Just "account-477") = Just "477"
xeroTestAccountCodeFromExpenseAccountId _                    = Nothing


failingRefreshXeroClient :: Text -> XeroClient
failingRefreshXeroClient message =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchConnectedTenants = \_ -> pure (Left (XeroHttpError message))
        , deleteXeroConnection = \_ _ -> pure (Left (XeroHttpError message))
        , refreshXeroToken = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollEmployees = \_ _ -> pure (Left (XeroHttpError message))
        , fetchEarningsRates = \_ _ -> pure (Left (XeroHttpError message))
        , fetchEarningsRatesPage = \_ _ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollCalendars = \_ _ -> pure (Left (XeroHttpError message))
        , fetchAccounts = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayrollSettingsAccounts = \_ _ -> pure (Left (XeroHttpError message))
        , fetchPayRuns = \_ _ _ -> pure (Left (XeroHttpError message))
        , createPayItem = \_ _ _ _ -> pure (Left (XeroHttpError message))
        , fetchTimesheets = \_ _ _ -> pure (Left (XeroHttpError message))
        , fetchTimesheetsForPeriod = \_ _ _ _ _ -> pure (Left (XeroHttpError message))
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError message))
        , createTimesheet = \_ _ _ _ -> pure (Left (XeroHttpError message))
        , updateTimesheet = \_ _ _ _ _ -> pure (Left (XeroHttpError message))
        }

createTestXeroOauthState ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    Text ->
    NominalDiffTime ->
    Maybe UTCTime ->
    IO XeroOauthState
createTestXeroOauthState venue user stateToken lifetime maybeConsumedAt = do
    now <- getCurrentTime
    newRecord @XeroOauthState
        |> set #venueId (unpackId venue.id)
        |> set #userId (unpackId user.id)
        |> set #stateToken stateToken
        |> set #requestedScopes requiredXeroScopesText
        |> set #redirectUri testXeroConfig.redirectUri
        |> set #expiresAt (addUTCTime lifetime now)
        |> set #consumedAt maybeConsumedAt
        |> createRecord

createActiveXeroConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    IO XeroConnection
createActiveXeroConnection venue user =
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId "tenant-existing"
        |> set #tenantName (Just "Existing Demo Company")
        |> set #xeroConnectionRemoteId (Just "connection-existing")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken "encrypted-refresh-token"
        |> set #encryptedAccessToken (Just "encrypted-access-token")
        |> set #connectedByUserId (Just (unpackId user.id))
        |> createRecord

createSyncableXeroConnection ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    IO XeroConnection
createSyncableXeroConnection venue user = do
    encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "existing-refresh-token"
    encryptedAccessToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "existing-access-token"
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId "tenant-existing"
        |> set #tenantName (Just "Existing Demo Company")
        |> set #xeroConnectionRemoteId (Just "connection-existing")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> set #encryptedAccessToken (Just encryptedAccessToken)
        |> set #connectedByUserId (Just (unpackId user.id))
        |> createRecord


ensureXeroAccountRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Text ->
    IO XeroAccount
ensureXeroAccountRecord connection accountCode name = do
    now <- getCurrentTime
    existing <-
        query @XeroAccount
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroAccountId, "account-" <> accountCode)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroAccountId ("account-" <> accountCode)
                |> set #code (Just accountCode)
                |> set #name name
                |> set #accountType (Just "EXPENSE")
                |> set #status (Just "ACTIVE")
                |> set #rawPayload (Aeson.object ["Code" Aeson..= accountCode, "Name" Aeson..= name])
                |> set #syncedAt now
    case existing of
        Just account -> fillRecord account |> updateRecord
        Nothing      -> fillRecord (newRecord @XeroAccount) |> createRecord

createXeroEarningsRateRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Text ->
    IO XeroEarningsRate
createXeroEarningsRateRecord connection name earningsRateId = do
    now <- getCurrentTime
    _ <- ensureXeroAccountRecord connection "477" "Wages and Salaries"
    newRecord @XeroEarningsRate
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEarningsRateId earningsRateId
        |> set #name name
        |> set #earningsType (Just "REGULAR")
        |> set #rateType (Just "RATEPERUNIT")
        |> set #accountCode (Just "477")
        |> set #isActive True
        |> set #rawPayload (Aeson.object ["EarningsRateID" Aeson..= earningsRateId])
        |> set #syncedAt now
        |> createRecord



fixturePeriodKey fixture =
    cs ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd :: Text)

markOtherFixtureStaffNotPaid ::
    (?modelContext :: ModelContext) =>
    Preview.PreviewFixture ->
    IO ()
markOtherFixtureStaffNotPaid fixture = do
    staff <- query @Staff |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetch
    forM_ (filter (\candidate -> candidate.id `notElem` [fixture.staffA.id, fixture.staffB.id]) staff) \staffMember -> do
        existing <- query @XeroStaffMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> filterWhere (#staffId, unpackId staffMember.id) |> fetchOneOrNothing
        case existing of
            Just mapping ->
                mapping
                    |> set #mappingStatus NotApplicable
                    |> set #xeroEmployeeId Nothing
                    |> set #xeroEmployeeName Nothing
                    |> set #xeroEmployeeEmail Nothing
                    |> set #updatedByUserId (Just (unpackId fixture.owner.id))
                    |> updateRecord
                    >>= const (pure ())
            Nothing ->
                newRecord @XeroStaffMapping
                    |> set #venueId (unpackId fixture.venue.id)
                    |> set #xeroConnectionId (unpackId fixture.connection.id)
                    |> set #staffId (unpackId staffMember.id)
                    |> set #mappingStatus NotApplicable
                    |> set #updatedByUserId (Just (unpackId fixture.owner.id))
                    |> createRecord
                    >>= const (pure ())

createSubmissionRunForFixture ::
    (?modelContext :: ModelContext) =>
    Preview.PreviewFixture ->
    XeroSubmissionRunStatusEnum ->
    IO XeroSubmissionRun
createSubmissionRunForFixture fixture status =
    newRecord @XeroSubmissionRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #submittedByUserId (unpackId fixture.owner.id)
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #selectedPayrollCalendarId (Just ("calendar-preview" :: Text))
        |> set #selectedPayrollCalendarName (Just ("Preview Calendar" :: Text))
        |> set #selectedPeriodKey (Just ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd :: Text))
        |> set #status status
        |> createRecord

createPreparationRunForFixture ::
    (?modelContext :: ModelContext) =>
    Preview.PreviewFixture ->
    XeroTimesheetPreparationRunStatusEnum ->
    IO XeroTimesheetPreparationRun
createPreparationRunForFixture fixture status =
    newRecord @XeroTimesheetPreparationRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #createdByUserId (unpackId fixture.owner.id)
        |> set #selectedPayrollCalendarId (Just ("calendar-preview" :: Text))
        |> set #selectedPayrollCalendarName (Just ("Preview Calendar" :: Text))
        |> set #selectedPeriodKey (Just ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd :: Text))
        |> set #payPeriodStart (Just fixture.periodStart)
        |> set #payPeriodEnd (Just fixture.periodEnd)
        |> set #status status
        |> createRecord

createXeroPayRunForFixture ::
    (?modelContext :: ModelContext) =>
    Preview.PreviewFixture ->
    Text ->
    IO XeroPayRun
createXeroPayRunForFixture fixture status = do
    now <- getCurrentTime
    newRecord @XeroPayRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #xeroPayRunId ("pay-run-" <> Text.toLower status)
        |> set #xeroPayrollCalendarId ("calendar-preview" :: Text)
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #payRunStatus (Just status)
        |> set #rawPayload (Aeson.object ["PayRunID" Aeson..= ("pay-run-" <> Text.toLower status)])
        |> set #syncedAt now
        |> createRecord

createXeroPayrollCalendarRecord ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Text ->
    Text ->
    IO XeroPayrollCalendar
createXeroPayrollCalendarRecord connection name payrollCalendarId = do
    now <- getCurrentTime
    newRecord @XeroPayrollCalendar
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroPayrollCalendarId payrollCalendarId
        |> set #name name
        |> set #calendarType (Just "WEEKLY")
        |> set #startDate (Just (fromGregorian 2026 4 27))
        |> set #paymentDate (Just (fromGregorian 2026 5 1))
        |> set #rawPayload (Aeson.object ["PayrollCalendarID" Aeson..= payrollCalendarId])
        |> set #syncedAt now
        |> createRecord

resetXeroStaffMappingForPreparation ::
    (?modelContext :: ModelContext) =>
    Staff ->
    IO ()
resetXeroStaffMappingForPreparation staff = do
    mappings <- query @XeroStaffMapping |> filterWhere (#staffId, unpackId staff.id) |> fetch
    forM_ mappings \mapping ->
        mapping
            |> set #mappingStatus NotApplicable
            |> set #xeroEmployeeId Nothing
            |> set #xeroEmployeeName Nothing
            |> set #xeroEmployeeEmail Nothing
            |> set #updatedByUserId Nothing
            |> updateRecord
            >>= const (pure ())
