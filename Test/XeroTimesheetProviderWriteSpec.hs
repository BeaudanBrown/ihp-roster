module Test.XeroTimesheetProviderWriteSpec where

import Application.Helper.Xero.Types (XeroClientError (..))
import Application.Xero.Timesheets.ProviderWrite
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Time.Calendar (fromGregorian)
import qualified Data.Vector as Vector
import IHP.Prelude
import Test.Hspec

tests :: Spec
tests =
    describe "Xero timesheet provider write policy" do
        it "uses stable operation-specific idempotency keys including replacement provenance" do
            let periodStart = fromGregorian 2026 8 3
                periodEnd = fromGregorian 2026 8 9
                key = xeroTimesheetWriteIdempotencyKey "employee-id" periodStart periodEnd
            key InitialXeroTimesheetCreate
                `shouldBe` "xero-timesheet:create:employee-id:2026-08-03:2026-08-09"
            key (UpdateXeroTimesheetDraft "remote-id")
                `shouldBe` "xero-timesheet:update:employee-id:2026-08-03:2026-08-09:remote-id"
            key (ReplaceMissingXeroTimesheetDraft "missing-prior-id")
                `shouldBe` "xero-timesheet:replace:employee-id:2026-08-03:2026-08-09:missing-prior-id"

        it "puts only update targets in the provider request payload" do
            let original = Aeson.Array (pure (Aeson.object ["TimesheetID" Aeson..= ("stale-id" :: Text), "EmployeeID" Aeson..= ("employee-id" :: Text)]))
            requestTimesheetId (xeroTimesheetRequestForOperation InitialXeroTimesheetCreate original)
                `shouldBe` Nothing
            requestTimesheetId (xeroTimesheetRequestForOperation (UpdateXeroTimesheetDraft "current-id") original)
                `shouldBe` Just "current-id"
            requestTimesheetId (xeroTimesheetRequestForOperation (ReplaceMissingXeroTimesheetDraft "stale-id") original)
                `shouldBe` Nothing

        it "classifies only operation-specific recoveries and indeterminate writes" do
            let response status = XeroHttpResponseError status Nothing "provider response"
            xeroTimesheetWriteFailureAction (UpdateXeroTimesheetDraft "stale-id") (response 404)
                `shouldBe` RefetchAfterMissingUpdate
            xeroTimesheetWriteFailureAction InitialXeroTimesheetCreate (response 409)
                `shouldBe` RefetchAfterCreateConflict
            xeroTimesheetWriteFailureAction (ReplaceMissingXeroTimesheetDraft "stale-id") (response 409)
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
                `shouldBe` replicate 6 PreservePendingXeroTimesheetWrite
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
