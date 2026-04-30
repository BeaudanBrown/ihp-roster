module Test.XeroTimesheetSubmissionSpec where

import Application.Helper.Xero
import Application.Xero.Timesheets.Submission
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.Vector as Vector
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import qualified Test.XeroMock as XeroMock
import Test.XeroTimesheetPreviewSpec (EntrySpec (..), PreviewFixture (..),
                                      createPreviewFixture, fixtureStaffA)

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

isSingletonArray :: Maybe Aeson.Value -> Bool
isSingletonArray (Just (Aeson.Array values)) = Vector.length values == 1
isSingletonArray _                           = False

responseHasTimesheets :: Aeson.Value -> Bool
responseHasTimesheets (Aeson.Object object) = AesonKeyMap.member (AesonKey.fromText "Timesheets") object
responseHasTimesheets _ = False
