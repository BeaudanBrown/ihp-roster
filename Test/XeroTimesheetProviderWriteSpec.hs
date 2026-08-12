module Test.XeroTimesheetProviderWriteSpec where

import Application.Helper.Xero.Types (XeroClientError (..))
import Application.Xero.Timesheets.ProviderWrite
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.UUID as UUID
import qualified Data.Vector as Vector
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Xero timesheet provider write policy" do
        it "scopes a stable provider key to one persisted submission operation" do
            let submissionId = fromMaybe (error "invalid test UUID") (UUID.fromText "11111111-1111-4111-8111-111111111111")
                key = xeroTimesheetWriteIdempotencyKey submissionId 0
            key InitialXeroTimesheetCreate
                `shouldBe` "xero-timesheet:11111111-1111-4111-8111-111111111111:0:create"
            key (UpdateXeroTimesheetDraft "remote-id")
                `shouldBe` "xero-timesheet:11111111-1111-4111-8111-111111111111:0:update"
            key (ReplaceMissingXeroTimesheetDraft)
                `shouldBe` "xero-timesheet:11111111-1111-4111-8111-111111111111:0:replace"

        it "changes the key for independent submissions and recovery operations" do
            let firstSubmissionId = fromMaybe (error "invalid test UUID") (UUID.fromText "11111111-1111-4111-8111-111111111111")
                secondSubmissionId = fromMaybe (error "invalid test UUID") (UUID.fromText "22222222-2222-4222-8222-222222222222")
                update = UpdateXeroTimesheetDraft "same-remote-id"
            xeroTimesheetWriteIdempotencyKey firstSubmissionId 0 update
                `shouldNotBe` xeroTimesheetWriteIdempotencyKey secondSubmissionId 0 update
            xeroTimesheetWriteIdempotencyKey firstSubmissionId 0 update
                `shouldNotBe` xeroTimesheetWriteIdempotencyKey firstSubmissionId 1 (ReplaceMissingXeroTimesheetDraft)

        it "recovers the same persisted operation key for an exact retry" do
            let submissionId = fromMaybe (error "invalid test UUID") (UUID.fromText "11111111-1111-4111-8111-111111111111")
                operation = UpdateXeroTimesheetDraft "remote-id"
                key = xeroTimesheetWriteIdempotencyKey submissionId 0 operation
                payload = xeroTimesheetRequestForOperation operation (Aeson.Array (pure (Aeson.object [])))
            xeroTimesheetWriteOperationFromPersistence submissionId key payload
                `shouldBe` Right operation
            xeroTimesheetWriteOperationFromPersistence submissionId "xero-timesheet:update:legacy-key" payload
                `shouldBe` Left "Persisted Xero timesheet operation does not match its idempotency key."

        it "puts only update targets in the provider request payload" do
            let original = Aeson.Array (pure (Aeson.object ["TimesheetID" Aeson..= ("stale-id" :: Text), "EmployeeID" Aeson..= ("employee-id" :: Text)]))
            requestTimesheetId (xeroTimesheetRequestForOperation InitialXeroTimesheetCreate original)
                `shouldBe` Nothing
            requestTimesheetId (xeroTimesheetRequestForOperation (UpdateXeroTimesheetDraft "current-id") original)
                `shouldBe` Just "current-id"
            requestTimesheetId (xeroTimesheetRequestForOperation (ReplaceMissingXeroTimesheetDraft) original)
                `shouldBe` Nothing

        it "classifies only operation-specific recoveries and indeterminate writes" do
            let response status = XeroHttpResponseError status Nothing "provider response"
            xeroTimesheetWriteFailureAction (UpdateXeroTimesheetDraft "stale-id") (response 404)
                `shouldBe` RefetchAfterMissingUpdate
            xeroTimesheetWriteFailureAction InitialXeroTimesheetCreate (response 409)
                `shouldBe` RefetchAfterCreateConflict
            xeroTimesheetWriteFailureAction (ReplaceMissingXeroTimesheetDraft) (response 409)
                `shouldBe` RefetchAfterCreateConflict
            xeroTimesheetWriteFailureAction (UpdateXeroTimesheetDraft "stale-id") (response 409)
                `shouldBe` FailXeroTimesheetWrite
            map (xeroTimesheetWriteFailureAction InitialXeroTimesheetCreate)
                [ XeroHttpError "timeout"
                , XeroDecodeError "indeterminate success response"
                , response 408
                , response 502
                , response 503
                , response 504
                ]
                `shouldBe` replicate 6 FailUncertainXeroTimesheetWrite
            map (xeroTimesheetWriteFailureAction InitialXeroTimesheetCreate)
                [ response 400
                , response 404
                , response 429
                , response 500
                , XeroSemanticError "validation failed"
                , XeroNoTenantsError
                ]
                `shouldBe` replicate 6 FailXeroTimesheetWrite

requestTimesheetId :: Aeson.Value -> Maybe Text
requestTimesheetId (Aeson.Array values) =
    case Vector.toList values of
        Aeson.Object object : _ ->
            case AesonKeyMap.lookup (AesonKey.fromText "TimesheetID") object of
                Just (Aeson.String value) -> Just value
                _                         -> Nothing
        _ -> Nothing
requestTimesheetId _ = Nothing
