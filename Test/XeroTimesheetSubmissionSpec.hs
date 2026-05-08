module Test.XeroTimesheetSubmissionSpec where

import Application.Helper.Xero
import Application.Xero.Timesheets.Submission
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Text as Text
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (status200, status500)
import qualified Network.Wai as Wai
import Test.Hspec
import Test.Support
import qualified Test.XeroMock as XeroMock
import Test.XeroTimesheetPreviewSpec (EntrySpec (..), PreviewFixture (..),
                                      createPreviewFixture, fixtureStaffA,
                                      fixtureStaffB)

tests :: Spec
tests =
    beforeAll testContext do
        describe "Xero draft timesheet submission" do
            (identitySpec, payrollSpec) <- runIO XeroMock.loadXeroOpenApiSpecs

            it "creates draft timesheets through the strict Xero mock and persists request/response/source state" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "submitted"
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldSatisfy` ((== 1) . length)
                            case submissions of
                                [submission] -> do
                                    submission.status `shouldBe` "submitted"
                                    submission.attemptCount `shouldBe` 1
                                    submission.idempotencyKey `shouldSatisfy` (not . null)
                                    Text.length submission.idempotencyKey `shouldSatisfy` (<= 128)
                                    Aeson.decode (Aeson.encode submission.requestPayloadJson) `shouldSatisfy` isSingletonArray
                                    submission.responsePayloadJson `shouldSatisfy` responseHasTimesheets
                                    submission.xeroTimesheetId `shouldBe` Just "timesheet-id"
                                    submission.xeroTimesheetStatus `shouldBe` Just "DRAFT"
                                    let submissionId = unpackId (get #id submission) :: UUID
                                    entries <- query @XeroTimesheetSubmissionEntry |> filterWhere (#xeroTimesheetSubmissionId, submissionId) |> fetch
                                    map (.timesheetEntryId) entries `shouldBe` map (unpackId . (.id)) fixture.entries
                                _ -> expectationFailure "expected one Xero timesheet submission row"

            it "blocks create when the immediate duplicate check finds a remote Xero timesheet for the employee and period" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "blocked"
                            run.errorSummary `shouldSatisfy` maybe False ("Xero already has a timesheet" `isInfixOf`)
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldBe` []

            it "submits selected-calendar employees and excludes different-calendar employees" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeCalendarById fixture "employee-b" "calendar-other"

                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "submitted"
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldSatisfy` ((== 1) . length)
                            map (.xeroEmployeeId) submissions `shouldBe` ["employee-a"]
                            entries <- query @XeroTimesheetSubmissionEntry |> fetch
                            map (.timesheetEntryId) entries `shouldBe` map (unpackId . (.id)) (take 1 fixture.entries)

            it "persists semantic Xero validation errors from strict create responses" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        XeroMock.withStrictXeroMockTimesheetCreateResponses identitySpec payrollSpec [semanticValidationResponse] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "failed"
                            submission <- onlySubmissionForRun run
                            submission.status `shouldBe` "failed"
                            submission.attemptCount `shouldBe` 1
                            submission.lastError `shouldSatisfy` maybe False ("ValidationException" `isInfixOf`)
                            submission.lastError `shouldSatisfy` maybe False ("Timesheet invalid" `isInfixOf`)
                            submission.responsePayloadJson `shouldSatisfy` jsonValueContainsText "ValidationException"

            it "persists transport failures without losing the request payload or idempotency key" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        XeroMock.withStrictXeroMockTimesheetCreateResponses identitySpec payrollSpec [transportFailureResponse] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "failed"
                            submission <- onlySubmissionForRun run
                            submission.status `shouldBe` "failed"
                            submission.attemptCount `shouldBe` 1
                            submission.idempotencyKey `shouldSatisfy` (not . null)
                            submission.requestPayloadJson `shouldSatisfy` isSingletonArrayValue
                            submission.lastError `shouldSatisfy` maybe False ("failed with status 500" `isInfixOf`)

            it "marks a multi-employee run partially_failed when one strict create call fails" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        XeroMock.withStrictXeroMockTimesheetCreateResponses identitySpec payrollSpec [XeroMock.jsonResponse status200 XeroMock.timesheetsFixture, semanticValidationResponse] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` "partially_failed"
                            submissions <- submissionsForRun run
                            sort (map (.status) submissions) `shouldBe` ["failed", "submitted"]
                            run.errorSummary `shouldSatisfy` maybe False ("ValidationException" `isInfixOf`)

            it "retries a failed submission with the persisted idempotency key and submission row" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    initialResult <-
                        XeroMock.withStrictXeroMockTimesheetCreateResponses identitySpec payrollSpec [transportFailureResponse] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    failedSubmission <-
                        case initialResult of
                            Left message -> expectationFailure (cs message) >> error "unreachable"
                            Right run -> onlySubmissionForRun run
                    let originalSubmissionId = failedSubmission.id
                        originalIdempotencyKey = failedSubmission.idempotencyKey

                    retryResult <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    retryXeroDraftTimesheetSubmission failedSubmission.id

                    case retryResult of
                        Left message -> expectationFailure (cs message)
                        Right retriedSubmission -> do
                            retriedSubmission.id `shouldBe` originalSubmissionId
                            retriedSubmission.status `shouldBe` "submitted"
                            retriedSubmission.attemptCount `shouldBe` 2
                            retriedSubmission.idempotencyKey `shouldBe` originalIdempotencyKey
                            submissions <- submissionsForRunId retriedSubmission.xeroSubmissionRunId
                            submissions `shouldSatisfy` ((== 1) . length)
                            run <- fetch (Id retriedSubmission.xeroSubmissionRunId :: Id XeroSubmissionRun)
                            run.status `shouldBe` "submitted"

testXeroConfig :: XeroConfig
testXeroConfig =
    XeroConfig
        { clientId = "client-id"
        , clientSecret = "client-secret"
        , redirectUri = "http://localhost:8000/XeroOAuthCallback"
        , tokenEncryptionKey = "test-secret"
        }

prepareConnectionForStrictMock :: (?modelContext :: ModelContext) => XeroConnection -> IO XeroConnection
prepareConnectionForStrictMock connection = do
    encryptedRefreshToken <- encryptXeroToken testXeroConfig.tokenEncryptionKey "refresh-token"
    connection
        |> set #tenantId ("tenant-id" :: Text)
        |> set #encryptedRefreshToken encryptedRefreshToken
        |> updateRecord

forceFixtureEmployeeId :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> IO ()
forceFixtureEmployeeId fixture employeeId = do
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> filterWhere (#staffId, unpackId fixture.staffA.id)
            |> fetch
    forM_ mappings \mapping ->
        void (mapping |> set #xeroEmployeeId (Just employeeId) |> updateRecord)
    employees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> filterWhere (#xeroEmployeeId, "employee-a" :: Text)
            |> fetch
    forM_ employees \employee ->
        void (employee |> set #xeroEmployeeId employeeId |> updateRecord)

forceFixtureEmployeeCalendarById :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> Text -> IO ()
forceFixtureEmployeeCalendarById fixture employeeId payrollCalendarId = do
    employees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> filterWhere (#xeroEmployeeId, employeeId)
            |> fetch
    forM_ employees \employee ->
        void (employee |> set #payrollCalendarId (Just payrollCalendarId) |> updateRecord)

failIfCreateTimesheetClient :: XeroClient
failIfCreateTimesheetClient =
    XeroClient
        { exchangeCodeForToken = \_ _ -> pure (Right (XeroTokenResponse "access-token" "refresh-token" 1800 (Just requiredXeroScopesText)))
        , fetchConnectedTenants = \_ -> pure (Right [])
        , deleteXeroConnection = \_ _ -> pure (Right ())
        , refreshXeroToken = \_ _ -> pure (Right (XeroTokenResponse "access-token" "refresh-token" 1800 (Just requiredXeroScopesText)))
        , fetchPayrollEmployees = \_ _ -> pure (Right [])
        , fetchEarningsRates = \_ _ -> pure (Right [])
        , fetchPayrollCalendars = \_ _ -> pure (Right [])
        , fetchPayRuns = \_ _ _ -> pure (Right [])
        , createPayItem = \_ _ _ _ -> pure (Right [])
        , fetchTimesheets = \_ _ _ -> pure (Right [])
        , fetchTimesheet = \_ _ _ -> pure (Left (XeroHttpError "unexpected fetchTimesheet call"))
        , createTimesheet = \_ _ _ _ -> expectationFailure "createTimesheet should not be reached when readiness is blocked" >> pure (Left (XeroHttpError "unexpected createTimesheet call"))
        , updateTimesheet = \_ _ _ _ _ -> pure (Left (XeroHttpError "unexpected updateTimesheet call"))
        }

isSingletonArray :: Maybe Aeson.Value -> Bool
isSingletonArray (Just (Aeson.Array values)) = Vector.length values == 1
isSingletonArray _                           = False

responseHasTimesheets :: Aeson.Value -> Bool
responseHasTimesheets (Aeson.Object object) = AesonKeyMap.member (AesonKey.fromText "Timesheets") object
responseHasTimesheets _ = False

semanticValidationResponse :: Wai.Response
semanticValidationResponse =
    XeroMock.jsonResponse
        status200
        ( Aeson.object
            [ "Type" Aeson..= ("ValidationException" :: Text)
            , "Message" Aeson..= ("Timesheet invalid" :: Text)
            ]
        )

transportFailureResponse :: Wai.Response
transportFailureResponse =
    XeroMock.jsonResponse status500 (Aeson.object ["error" Aeson..= ("upstream unavailable" :: Text)])

onlySubmissionForRun :: (?modelContext :: ModelContext) => XeroSubmissionRun -> IO XeroTimesheetSubmission
onlySubmissionForRun run = do
    submissions <- submissionsForRun run
    case submissions of
        [submission] -> pure submission
        _            -> expectationFailure (cs ("expected one Xero timesheet submission row, got " <> tshow (length submissions))) >> error "unreachable"

submissionsForRun :: (?modelContext :: ModelContext) => XeroSubmissionRun -> IO [XeroTimesheetSubmission]
submissionsForRun run =
    submissionsForRunId (unpackId run.id)

submissionsForRunId :: (?modelContext :: ModelContext) => UUID -> IO [XeroTimesheetSubmission]
submissionsForRunId runId =
    query @XeroTimesheetSubmission
        |> filterWhere (#xeroSubmissionRunId, runId)
        |> fetch

isSingletonArrayValue :: Aeson.Value -> Bool
isSingletonArrayValue (Aeson.Array values) = Vector.length values == 1
isSingletonArrayValue _                    = False

jsonValueContainsText :: Text -> Aeson.Value -> Bool
jsonValueContainsText expected = \case
    Aeson.String value -> expected `isInfixOf` value
    Aeson.Object object -> any (jsonValueContainsText expected) object
    Aeson.Array values -> any (jsonValueContainsText expected) values
    _ -> False
