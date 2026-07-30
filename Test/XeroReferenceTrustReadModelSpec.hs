module Test.XeroReferenceTrustReadModelSpec where

import Application.Async.Queue
import Application.Xero.ReferenceSyncJob
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel
import qualified Data.Aeson as Aeson
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.XeroAdmin

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Xero reference trust read model" do
        it "aggregates future continuation jobs as retry waiting while preserving fresh snapshot use" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Trust Read Model Venue"
                owner <- createUserRecord "xero-trust-read-model@example.com" "staff" True
                connection <- createSyncableXeroConnection venue owner
                now <- getCurrentTime
                trustedConnection <- connection |> set #lastSyncAt (Just (addUTCTime (negate (6.5 * oneDay)) now)) |> updateRecord
                EnqueuedAppJob firstAttempt <- enqueueXeroReferenceSyncJob Nothing trustedConnection
                _ <- firstAttempt
                    |> set #status JobStatusSucceeded
                    |> set #progress
                        ( Aeson.object
                            [ "phase" Aeson..= ("retry_wait" :: Text)
                            , "completedPayItemsPage" Aeson..= (42 :: Int)
                            , "failedPhase" Aeson..= ("accounts" :: Text)
                            , "retryAt" Aeson..= addUTCTime 300 now
                            ]
                        )
                    |> set #result (Aeson.object ["status" Aeson..= ("retry_scheduled" :: Text), "message" Aeson..= ("unsafe provider body token=secret" :: Text)])
                    |> updateRecord
                EnqueuedAppJob continuationJob <- enqueueXeroReferenceSyncJob Nothing trustedConnection
                retryAt <- pure (addUTCTime 300 now)
                continuation <- continuationJob
                    |> set #runAt retryAt
                    |> set #payload (Aeson.object ["requestedAt" Aeson..= now, "retryNumber" Aeson..= (1 :: Int)])
                    |> updateRecord

                state <- fetchXeroReferenceTrustState now trustedConnection NoMissingPayrollReferenceDemand
                state.syncActivity `shouldBe` XeroReferenceSyncRetryWaiting continuation.runAt
                state.syncProgress.progressCompletedPayItemsPage `shouldBe` Just 42
                state.syncProgress.progressFailedPhase `shouldBe` Just "accounts"
                state.syncSanitizedError `shouldBe` Just "Xero reference sync is waiting to retry after the accounts phase failed."
                state.trustDecision `shouldBe` UseTrustedXeroReferenceSnapshot

        it "returns a sanitized terminal block for a failed stale snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Stale Trust Venue"
                owner <- createUserRecord "xero-stale-trust@example.com" "staff" True
                connection <- createSyncableXeroConnection venue owner
                now <- getCurrentTime
                staleConnection <- connection |> set #lastSyncAt (Just (addUTCTime (negate (8 * oneDay)) now)) |> updateRecord
                EnqueuedAppJob job <- enqueueXeroReferenceSyncJob Nothing staleConnection
                _ <- job
                    |> set #status JobStatusFailed
                    |> set #progress (Aeson.object ["phase" Aeson..= ("accounts" :: Text)])
                    |> set #lastError (Just "unsafe provider body token=secret")
                    |> updateRecord

                state <- fetchXeroReferenceTrustState now staleConnection NoMissingPayrollReferenceDemand
                state.syncActivity `shouldBe` XeroReferenceSyncFailed "Xero reference sync stopped safely."
                state.syncSanitizedError `shouldBe` Just "Xero reference sync stopped after the accounts phase failed."
                state.trustDecision `shouldBe` BlockStaleXeroReferenceData "Xero reference sync stopped safely."

oneDay :: NominalDiffTime
oneDay = 24 * 60 * 60
