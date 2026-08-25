module Test.XeroTimesheetSubmissionSpec where

import Application.Error.Types (AppResult)
import Application.Helper.Xero
import Application.Helper.XeroTimesheetReadiness (XeroTimesheetReadinessRequest)
import Application.Xero.Timesheets.ProviderWrite
import Application.Xero.Timesheets.ReconciliationReview
import Application.Xero.Timesheets.Submission hiding (reviewXeroDraftTimesheets,
                                               submitReviewedXeroDraftTimesheetsForPreparation,
                                               submitXeroDraftTimesheets)
import qualified Application.Xero.Timesheets.Submission as Submission
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status (status200, status404, status409, status500,
                                  status504)
import qualified Network.Wai as Wai
import Test.Hspec
import Test.Support
import qualified Test.XeroMock as XeroMock
import Test.XeroTimesheetPreviewSpec (EntrySpec (..), PreviewFixture (..),
                                      createLateBindingPreviewFixture,
                                      createPreviewFixture,
                                      createPreviewFixtureAtPeriod,
                                      fixtureStaffA, fixtureStaffB)

reviewXeroDraftTimesheets :: (?modelContext :: ModelContext) => XeroTimesheetReadinessRequest -> IO (Either Text Aeson.Value)
reviewXeroDraftTimesheets request = Submission.reviewXeroDraftTimesheets request >>= expectSubmissionResult

submitXeroDraftTimesheets :: (?modelContext :: ModelContext) => Id User -> XeroTimesheetReadinessRequest -> IO (Either Text XeroSubmissionRun)
submitXeroDraftTimesheets userId request = Submission.submitXeroDraftTimesheets userId request >>= expectSubmissionResult

submitReviewedXeroDraftTimesheetsForPreparation :: (?modelContext :: ModelContext) => Id User -> Id XeroTimesheetPreparationRun -> Aeson.Value -> XeroTimesheetReadinessRequest -> IO (Either Text XeroTimesheetReviewedSubmissionOutcome)
submitReviewedXeroDraftTimesheetsForPreparation userId runId snapshot request =
    Submission.submitReviewedXeroDraftTimesheetsForPreparation userId runId snapshot request >>= expectSubmissionResult

expectSubmissionResult :: AppResult value -> IO value
expectSubmissionResult = either (\appError -> expectationFailure (cs (show appError)) >> fail "unexpected submission infrastructure error") pure

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
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
                            run.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                            run.xeroDuplicateCheckJson `shouldSatisfy` jsonObjectHasKey "reconciliationReview"
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldSatisfy` ((== 1) . length)
                            case submissions of
                                [submission] -> do
                                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                                    run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                                    run.selectedPeriodKey `shouldBe` Just ("calendar-preview:" <> tshow fixture.periodStart <> ":" <> tshow fixture.periodEnd)
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

            it "submits late-bound components approved before Xero setup" $ withContext do
                withCleanDb do
                    fixture <- createLateBindingPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                            bindings <- query @TimesheetPayComponentXeroBinding
                                |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                                |> fetch
                            bindings `shouldSatisfy` (not . null)
                            sealedComponents <- query @TimesheetPayEarningsComponent
                                |> filterWhereIn (#timesheetPayCalculationId, mapMaybe (fmap unpackId . (.activePayCalculationId)) fixture.entries)
                                |> fetch
                            sealedComponents `shouldSatisfy` all (isNothing . (.xeroLocalBucketKey))
                            sealedComponents `shouldSatisfy` all (isNothing . (.xeroEarningsRateId))

            it "submits a historical selected Xero period without a global calendar selection" $ withContext do
                withCleanDb do
                    let historicalStart = fromGregorian 2026 1 5
                    fixture <- createPreviewFixtureAtPeriod "weekly" historicalStart [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                            run.payPeriodStart `shouldBe` historicalStart
                            run.payPeriodEnd `shouldBe` addDays 6 historicalStart
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"

            it "updates when the immediate duplicate check finds a remote Xero draft timesheet for the employee and period" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [timesheetsDateTimeResponse fixture "employee-id" "DRAFT"]
                            []
                            [successfulTimesheetResponse]

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldSatisfy` ((== 1) . length)
                            case submissions of
                                [submission] -> do
                                    submission.idempotencyKey
                                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 0 (UpdateXeroTimesheetDraft "timesheet-id")
                                    submission.requestPayloadJson `shouldSatisfy` jsonValueContainsText "timesheet-id"
                                    submission.xeroTimesheetId `shouldBe` Just "timesheet-id"
                                _ -> expectationFailure "expected one Xero timesheet submission row"

            it "replaces a confirmed missing prior draft with a prior-id-specific stable key" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    firstResult <- submitWithStrictResponses identitySpec payrollSpec fixture [emptyTimesheetsResponse] [successfulTimesheetResponse] []
                    firstRun <- expectRun firstResult
                    firstSubmission <- onlySubmissionForRun firstRun

                    secondResult <- submitWithStrictResponses identitySpec payrollSpec fixture [emptyTimesheetsResponse] [successfulTimesheetResponse] []
                    secondRun <- expectRun secondResult
                    secondSubmission <- onlySubmissionForRun secondRun

                    refreshedFirst <- fetch firstSubmission.id
                    refreshedFirst.status `shouldBe` XeroTimesheetSubmissionStatusEnumSuperseded
                    secondSubmission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId secondSubmission.id) 0 (ReplaceMissingXeroTimesheetDraft)
                    secondSubmission.idempotencyKey `shouldNotBe` firstSubmission.idempotencyKey
                    submissionExistingTimesheetIdForTest secondSubmission `shouldBe` Nothing

            it "reviews a confirmed-missing Bepis draft as an explicit replacement warning" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    _ <- submitWithStrictResponses identitySpec payrollSpec fixture [emptyTimesheetsResponse] [successfulTimesheetResponse] []
                    snapshot <-
                        XeroMock.withStrictXeroMockTimesheetResponses identitySpec payrollSpec [emptyTimesheetsResponse] [] [] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    reviewXeroDraftTimesheets fixture.request
                    reviewedSnapshot <- snapshot |> either (\message -> expectationFailure (cs message) >> pure Aeson.Null) pure
                    notices <- reconciliationReviewNotices reviewedSnapshot |> either (\message -> expectationFailure (cs message) >> pure []) pure

                    reconciliationReviewAllowsSubmission reviewedSnapshot `shouldBe` Right True
                    map (.reconciliationNoticeSeverity) notices `shouldBe` [ReconciliationWarning]
                    map (.reconciliationNoticeMessage) notices
                        `shouldBe` ["Bepis previously created Xero draft timesheet-id, but it is now missing. Confirm to create a replacement draft."]

            it "requires review again when fresh Xero reconciliation state changes after confirmation" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    reviewed <-
                        XeroMock.withStrictXeroMockTimesheetResponses identitySpec payrollSpec [emptyTimesheetsResponse] [] [] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    reviewXeroDraftTimesheets fixture.request
                    reviewedSnapshot <- reviewed |> either (\message -> expectationFailure (cs message) >> pure Aeson.Null) pure
                    outcome <-
                        XeroMock.withStrictXeroMockTimesheetResponses identitySpec payrollSpec [timesheetsResponse fixture "employee-a" "DRAFT"] [] [] \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitReviewedXeroDraftTimesheetsForPreparation
                                        fixture.owner.id
                                        (Id (unpackId fixture.connection.id))
                                        reviewedSnapshot
                                        fixture.request
                    case outcome of
                        Right (XeroTimesheetReviewedStateChanged freshSnapshot) -> do
                            reconciliationReviewSnapshotIsConfirmed freshSnapshot `shouldBe` True
                            reconciliationReviewNotices freshSnapshot `shouldBe` Right []
                        other -> expectationFailure (cs ("Expected changed reconciliation state, got " <> show other))
                    query @XeroSubmissionRun |> fetchCount >>= (`shouldBe` 0)
                    query @XeroTimesheetSubmission |> fetchCount >>= (`shouldBe` 0)

            it "refetches once after update 404 and replaces only after confirmed absence" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [timesheetsResponse fixture "employee-id" "DRAFT", emptyTimesheetsResponse]
                            [successfulTimesheetResponse]
                            [XeroMock.jsonResponse status404 (Aeson.object ["error" Aeson..= ("missing" :: Text)])]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                    submission.attemptCount `shouldBe` 2
                    submission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 1 (ReplaceMissingXeroTimesheetDraft)

            it "blocks when an update 404 refetch observes a non-draft transition" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [timesheetsResponse fixture "employee-id" "DRAFT", timesheetsResponse fixture "employee-id" "APPROVED"]
                            []
                            [XeroMock.jsonResponse status404 (Aeson.object ["error" Aeson..= ("missing" :: Text)])]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    run.status `shouldBe` XeroSubmissionRunStatusEnumBlocked
                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumBlocked
                    submission.attemptCount `shouldBe` 1
                    submission.lastError `shouldSatisfy` maybe False ("APPROVED" `Text.isInfixOf`)

            it "does not fall back from an unrelated update provider error" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [timesheetsResponse fixture "employee-id" "DRAFT"]
                            []
                            [XeroMock.jsonResponse status500 (Aeson.object ["error" Aeson..= ("upstream unavailable" :: Text)])]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    run.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumFailed
                    submission.attemptCount `shouldBe` 1
                    submission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 0 (UpdateXeroTimesheetDraft "timesheet-id")

            it "refetches a create conflict and updates exactly one confirmed draft" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [emptyTimesheetsResponse, timesheetsResponse fixture "employee-a" "DRAFT"]
                            [XeroMock.jsonResponse status409 (Aeson.object ["error" Aeson..= ("duplicate" :: Text)])]
                            [successfulTimesheetResponse]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                    submission.attemptCount `shouldBe` 2
                    submission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 1 (UpdateXeroTimesheetDraft "timesheet-id")

            it "handles an update-404 replacement racing with a newly created draft" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection
                    forceFixtureEmployeeId fixture "employee-id"

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [ timesheetsResponse fixture "employee-id" "DRAFT"
                            , emptyTimesheetsResponse
                            , timesheetsResponse fixture "employee-id" "DRAFT"
                            ]
                            [XeroMock.jsonResponse status409 (Aeson.object ["error" Aeson..= ("replacement conflict" :: Text)])]
                            [ XeroMock.jsonResponse status404 (Aeson.object ["error" Aeson..= ("missing" :: Text)])
                            , successfulTimesheetResponse
                            ]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                    submission.attemptCount `shouldBe` 3
                    submission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 2 (UpdateXeroTimesheetDraft "timesheet-id")

            it "handles a create-conflict update racing with draft deletion" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [ emptyTimesheetsResponse
                            , timesheetsResponse fixture "employee-a" "DRAFT"
                            , emptyTimesheetsResponse
                            ]
                            [ XeroMock.jsonResponse status409 (Aeson.object ["error" Aeson..= ("create conflict" :: Text)])
                            , successfulTimesheetResponse
                            ]
                            [XeroMock.jsonResponse status404 (Aeson.object ["error" Aeson..= ("deleted" :: Text)])]
                    run <- expectRun result
                    submission <- onlySubmissionForRun run

                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumSubmitted
                    submission.attemptCount `shouldBe` 3
                    submission.idempotencyKey
                        `shouldBe` xeroTimesheetWriteIdempotencyKey (unpackId submission.id) 2 (ReplaceMissingXeroTimesheetDraft)

            it "fails an uncertain write with guidance to reconcile through fresh preparation" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [emptyTimesheetsResponse]
                            [XeroMock.jsonResponse status504 (Aeson.object ["error" Aeson..= ("timeout" :: Text)])]
                            []
                    run <- expectRun result
                    submission <- onlySubmissionForRun run
                    run.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                    run.completedAt `shouldSatisfy` isJust
                    submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumFailed
                    submission.attemptCount `shouldBe` 1
                    submission.lastError `shouldSatisfy` maybe False ("could not confirm whether Xero received" `Text.isInfixOf`)
                    submission.lastError `shouldSatisfy` maybe False ("start a fresh preparation" `Text.isInfixOf`)

            it "marks a multi-employee run partially failed when one write outcome is uncertain" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    prepareConnectionForStrictMock fixture.connection

                    result <-
                        submitWithStrictResponses
                            identitySpec
                            payrollSpec
                            fixture
                            [emptyTimesheetsResponse]
                            [ XeroMock.jsonResponse status504 (Aeson.object ["error" Aeson..= ("timeout" :: Text)])
                            , XeroMock.jsonResponse status200 XeroMock.timesheetsFixture
                            ]
                            []
                    run <- expectRun result
                    submissions <- submissionsForRun run

                    run.status `shouldBe` PartiallyFailed
                    run.completedAt `shouldSatisfy` isJust
                    sort (map (.status) submissions)
                        `shouldBe` [XeroTimesheetSubmissionStatusEnumSubmitted, XeroTimesheetSubmissionStatusEnumFailed]

            it "submits only mapped employees assigned to the selected synced Xero payroll calendar" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    prepareConnectionForStrictMock fixture.connection
                    overwriteFixtureEmployeeRawCalendar fixture "employee-b" "calendar-other"

                    result <-
                        XeroMock.withStrictXeroMock identitySpec payrollSpec \urls ->
                            withXeroRequestBaseUrlsForTest urls do
                                withXeroConfigForTest (Right testXeroConfig) do
                                    submitXeroDraftTimesheets fixture.owner.id fixture.request

                    case result of
                        Left message -> expectationFailure (cs message)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumSubmitted
                            submissions <- query @XeroTimesheetSubmission |> filterWhere (#xeroSubmissionRunId, unpackId run.id) |> fetch
                            submissions `shouldSatisfy` ((== 1) . length)
                            map (.xeroEmployeeId) submissions `shouldBe` ["employee-a"]

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
                            run.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                            submission <- onlySubmissionForRun run
                            submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumFailed
                            submission.attemptCount `shouldBe` 1
                            submission.lastError `shouldBe` Just "provider rejected the request."
                            submission.lastError `shouldSatisfy` maybe True (not . ("ValidationException" `isInfixOf`))
                            submission.lastError `shouldSatisfy` maybe True (not . ("Timesheet invalid" `isInfixOf`))
                            submission.responsePayloadJson `shouldSatisfy` jsonValueContainsText "provider rejected the request."
                            submission.responsePayloadJson `shouldSatisfy` (not . jsonValueContainsText "ValidationException")

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
                            run.status `shouldBe` XeroSubmissionRunStatusEnumFailed
                            submission <- onlySubmissionForRun run
                            submission.status `shouldBe` XeroTimesheetSubmissionStatusEnumFailed
                            submission.attemptCount `shouldBe` 1
                            submission.idempotencyKey `shouldSatisfy` (not . null)
                            submission.requestPayloadJson `shouldSatisfy` isSingletonArrayValue
                            submission.lastError `shouldBe` Just "provider request returned status 500."

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
                            run.status `shouldBe` PartiallyFailed
                            submissions <- submissionsForRun run
                            sort (map (.status) submissions) `shouldBe` [XeroTimesheetSubmissionStatusEnumSubmitted, XeroTimesheetSubmissionStatusEnumFailed]
                            run.errorSummary `shouldBe` Just "provider rejected the request."

submitWithStrictResponses ::
    (?modelContext :: ModelContext) =>
    XeroMock.OpenApiSpec ->
    XeroMock.OpenApiSpec ->
    PreviewFixture ->
    [Wai.Response] ->
    [Wai.Response] ->
    [Wai.Response] ->
    IO (Either Text XeroSubmissionRun)
submitWithStrictResponses identitySpec payrollSpec fixture listResponses createResponses updateResponses =
    XeroMock.withStrictXeroMockTimesheetResponses identitySpec payrollSpec listResponses createResponses updateResponses \urls ->
        withXeroRequestBaseUrlsForTest urls do
            withXeroConfigForTest (Right testXeroConfig) do
                submitXeroDraftTimesheets fixture.owner.id fixture.request

expectRun :: Either Text XeroSubmissionRun -> IO XeroSubmissionRun
expectRun (Right run) = pure run
expectRun (Left message) = expectationFailure (cs message) >> error "unreachable"

emptyTimesheetsResponse :: Wai.Response
emptyTimesheetsResponse = XeroMock.jsonResponse status200 (Aeson.object ["Timesheets" Aeson..= ([] :: [Aeson.Value])])

successfulTimesheetResponse :: Wai.Response
successfulTimesheetResponse = XeroMock.jsonResponse status200 XeroMock.timesheetsFixture

timesheetsResponse :: PreviewFixture -> Text -> Text -> Wai.Response
timesheetsResponse fixture =
    timesheetsResponseWithDates (tshow fixture.periodStart) (tshow fixture.periodEnd)

timesheetsDateTimeResponse :: PreviewFixture -> Text -> Text -> Wai.Response
timesheetsDateTimeResponse fixture =
    timesheetsResponseWithDates
        (tshow fixture.periodStart <> "T00:00:00")
        (tshow fixture.periodEnd <> "T00:00:00")

timesheetsResponseWithDates :: Text -> Text -> Text -> Text -> Wai.Response
timesheetsResponseWithDates startDate endDate employeeId status =
    XeroMock.jsonResponse status200 $
        Aeson.object
            [ "Timesheets" Aeson..=
                [ Aeson.object
                    [ "TimesheetID" Aeson..= ("timesheet-id" :: Text)
                    , "EmployeeID" Aeson..= employeeId
                    , "StartDate" Aeson..= startDate
                    , "EndDate" Aeson..= endDate
                    , "Status" Aeson..= status
                    , "Hours" Aeson..= (2 :: Int)
                    , "TimesheetLines" Aeson..= ([] :: [Aeson.Value])
                    ]
                ]
            ]

submissionExistingTimesheetIdForTest :: XeroTimesheetSubmission -> Maybe Text
submissionExistingTimesheetIdForTest submission =
    join (AesonTypes.parseMaybe parser submission.requestPayloadJson)
  where
    parser = AesonTypes.withArray "request" \array -> do
        firstObject <- maybe (fail "missing request") pure (array Vector.!? 0)
        AesonTypes.withObject "request object" (AesonTypes..:? "TimesheetID") firstObject


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

overwriteFixtureEmployeeRawCalendar :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> Text -> IO ()
overwriteFixtureEmployeeRawCalendar fixture employeeId payrollCalendarId = do
    employees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> filterWhere (#xeroEmployeeId, employeeId)
            |> fetch
    forM_ employees \employee ->
        void (employee |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeId, "PayrollCalendarID" Aeson..= payrollCalendarId]) |> updateRecord)


isSingletonArray :: Maybe Aeson.Value -> Bool
isSingletonArray (Just (Aeson.Array values)) = Vector.length values == 1
isSingletonArray _                           = False

jsonObjectHasKey :: AesonKey.Key -> Aeson.Value -> Bool
jsonObjectHasKey key (Aeson.Object object) = AesonKeyMap.member key object
jsonObjectHasKey _ _                       = False

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
