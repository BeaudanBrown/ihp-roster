-- Test-only provider boundary shared by the browser server and real job worker.
-- No method can fall back to the network. Request construction/HTTP contracts
-- remain owned by XeroContractSpec; these fixtures exercise browser workflows.
module Test.E2EXero (withE2EXero, seedXeroFixture) where

import Application.Error.Parser (parserFailure)
import Application.Fixture.Error
import Application.Helper.Xero
import Application.Xero.Timesheets.Prepare.Helpers (xeroPayRunRefJson)
import Application.Xero.ReferenceSyncJob (XeroReferenceSyncRuntime (..), withXeroReferenceSyncRuntimeForTest)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Either (fromRight)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import qualified IHP.Prelude as Prelude
import qualified System.Environment as Env
import System.Directory (renameFile)
import System.IO.Error (tryIOError)
import System.Exit (die)
import Test.Support (createTestPasskeyRecord)
import Test.Support.XeroAdmin
import qualified Test.Support.XeroTimesheet as Preview

withE2EXero :: IO a -> IO a
withE2EXero action = do
    path <- Env.getEnv "E2E_XERO_FIXTURE"
    let readFixture :: Aeson.FromJSON value => Text -> Aeson.Key -> IO (Either XeroClientError value)
        readFixture tenant key = do
            loaded <- tryIOError (Aeson.eitherDecodeFileStrict path)
            let contents = fromRight (Left "Missing E2E fixture") loaded
            pure $ case contents >>= AesonTypes.parseEither (Aeson.withObject "E2E Xero fixture" (\object -> do
                expectedTenant <- object Aeson..: "tenantId"
                unless (tenant == expectedTenant) (parserFailure "Unexpected E2E Xero tenant")
                object Aeson..: key)) of
                    Left _ -> Left (XeroHttpError "Missing or invalid E2E Xero fixture")
                    Right value -> Right value
        scopedPeriod :: Text -> Maybe Text -> Day -> Day -> IO (Either XeroClientError [XeroTimesheetRef])
        scopedPeriod tenant calendar start end = do
            drafts <- readFixture tenant "payRuns" :: IO (Either XeroClientError [XeroPayRunRef])
            pure $ case drafts of
                Right (draft : _) | calendar == Just draft.xeroPayRunCalendarId
                    && start == draft.xeroPayRunPeriodStart && end == draft.xeroPayRunPeriodEnd -> Right []
                _ -> Left (XeroHttpError "Unexpected E2E Xero timesheet period")
        client = (failingRefreshXeroClient "Unexpected E2E Xero operation")
            { refreshXeroToken = \_ token -> pure $
                if token == "refresh-token"
                    then Right (XeroTokenResponse "access-token" "refresh-token" 1800 (Just requiredXeroScopesText))
                    else Left (XeroHttpError "Unexpected E2E Xero credential")
            , fetchPayrollEmployees = \_ tenant -> readFixture tenant "employees"
            , fetchEarningsRates = \_ tenant -> readFixture tenant "earningsRates"
            , fetchEarningsRatesPage = \_ tenant page ->
                fmap (fmap (if page == 1 then Prelude.id else const [])) (readFixture tenant "earningsRates")
            , fetchPayrollCalendars = \_ tenant -> readFixture tenant "payrollCalendars"
            , fetchAccounts = \_ tenant -> fmap (fmap accountRefsFromEarningsRates) (readFixture tenant "earningsRates")
            , fetchPayrollSettingsAccounts = \_ tenant -> fmap (fmap wagesExpenseAccountRefsFromEarningsRates) (readFixture tenant "earningsRates")
            , fetchPayRuns = \_ tenant query ->
                fmap (fmap (if fromMaybe 1 query.xeroPayRunPage == 1 then Prelude.id else const [])) (readFixture tenant "payRuns")
            , fetchTimesheetsForPeriod = const scopedPeriod
            , createTimesheet = \_ tenant _ body -> case Aeson.fromJSON body of
                Aeson.Success [sheet] -> do
                    period <- scopedPeriod tenant (Just "calendar-preview") sheet.xeroTimesheetStartDate sheet.xeroTimesheetEndDate
                    pure $ case period of
                        Right _ | sheet.xeroTimesheetEmployeeId == "employee-a" && sheet.xeroTimesheetStatus == Just "DRAFT" ->
                            Right [sheet
                                { xeroTimesheetId = Just "e2e-created-timesheet"
                                , xeroTimesheetRaw = case sheet.xeroTimesheetRaw of
                                    Aeson.Object raw -> Aeson.Object (KeyMap.insert "TimesheetID" (Aeson.String "e2e-created-timesheet") raw)
                                    value -> value
                                }]
                        _ -> Left (XeroHttpError "Unexpected E2E Xero timesheet create")
                _ -> pure (Left (XeroHttpError "Invalid E2E Xero timesheet create"))
            }
    -- Rate pacing/retry clocks have focused Hspec authority. Local browser
    -- fixtures need the real job/publication, not waits for a remote rate limit.
    withXeroReferenceSyncRuntimeForTest (XeroReferenceSyncRuntime getCurrentTime (const (pure ())) (pure 0)) $
        withXeroConfigForTest (Right testXeroConfig) (withXeroClientForTest client action)

-- Each browser example gets its own venue, owner and sealed approvals. Reuse the
-- canonical payroll builder instead of hand-authoring incomplete ledger SQL.
seedXeroFixture :: (?modelContext :: ModelContext) => IO ()
seedXeroFixture = do
    enabled <- Env.lookupEnv "IHP_ROSTER_E2E"
    unless (enabled == Just "1") (die "Xero browser fixtures require the E2E runner")
    path <- Env.getEnv "E2E_XERO_FIXTURE"
    fixture <- Preview.createPreviewFixture "weekly"
        [ Preview.EntrySpec 0 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
        , Preview.EntrySpec 1 Preview.fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
        ]
    let email = "e2e-xero-owner-" <> tshow fixture.venue.id <> "@example.com"
        tenant = "e2e-xero-tenant-" <> tshow fixture.venue.id
    _ <- fixture.owner |> set #email email |> updateRecord
    _ <- createTestPasskeyRecord fixture.owner "E2E Xero passkey"
    staffUserId <- requireFixtureResult (fixtureRequired (MissingFixtureValue "fixture staff user") fixture.staffA.userId)
    staffUser <- fetch (Id staffUserId :: Id User)
    _ <- staffUser |> set #email ("e2e-xero-staff-" <> tshow fixture.venue.id <> "@example.com") |> updateRecord
    encrypted <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
    _ <- fixture.connection |> set #tenantId tenant |> set #encryptedRefreshToken encrypted |> updateRecord
    employees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    rates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    calendars <- query @XeroPayrollCalendar |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    payRuns <- query @XeroPayRun |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    employeeValues <- mapM (requireFixtureResult . employeeJson) employees
    let contents = Aeson.object
            [ "venueId" Aeson..= fixture.venue.id
            , "connectionId" Aeson..= fixture.connection.id
            , "email" Aeson..= email
            , "periodKey" Aeson..= (fixturePeriodKey fixture :: Text)
            , "tenantId" Aeson..= tenant
            , "employees" Aeson..= employeeValues
            , "earningsRates" Aeson..= map rateJson rates
            , "payrollCalendars" Aeson..= map calendarJson calendars
            , "payRuns" Aeson..= map (xeroPayRunRefJson . xeroPayRunRefFromRecord) payRuns
            ]
    LBS.writeFile (path <> ".tmp") (Aeson.encode contents)
    renameFile (path <> ".tmp") path
    LBS.putStrLn (Aeson.encode contents)
  where
    employeeJson employee = case employee.rawPayload of
        Aeson.Object raw -> Right (Aeson.Object (KeyMap.insert "Name" (Aeson.String employee.displayName) raw))
        _ -> Left (InvalidFixtureBoundary "fixture employee has no provider object")
    rateJson rate = Aeson.object
        [ "EarningsRateID" Aeson..= rate.xeroEarningsRateId, "Name" Aeson..= rate.name
        , "EarningsType" Aeson..= rate.earningsType, "RateType" Aeson..= rate.rateType
        , "AccountCode" Aeson..= rate.accountCode, "IsActive" Aeson..= rate.isActive
        ]
    calendarJson calendar = Aeson.object
        [ "PayrollCalendarID" Aeson..= calendar.xeroPayrollCalendarId, "Name" Aeson..= calendar.name
        , "CalendarType" Aeson..= calendar.calendarType, "StartDate" Aeson..= calendar.startDate
        ]
