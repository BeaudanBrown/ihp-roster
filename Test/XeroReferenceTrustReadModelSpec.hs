module Test.XeroReferenceTrustReadModelSpec where

import Application.Async.Queue
import Application.Xero.ReferenceSyncJob
import Application.Xero.ReferenceTrust
import Application.Xero.ReferenceTrust.ReadModel
import Application.Xero.ReferenceTrust.Service
import Control.Monad (replicateM_)
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, getCurrentTime,
                        secondsToDiffTime)
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
        it "observes trust repeatedly without starting jobs or sync runs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Read Only Observation Venue"
                owner <- createUserRecord "xero-read-only-observation@example.com" "staff" True
                connection <- createSyncableXeroConnection venue owner
                let now = fixedReferenceTrustTime

                replicateM_ 3 do
                    state <- fetchXeroReferenceTrustState now connection NoMissingPayrollReferenceDemand
                    state.trustDecision `shouldBe` StartOrJoinXeroReferenceSync

                query @AppJob |> fetchCount >>= (`shouldBe` 0)
                query @XeroSyncRun |> fetchCount >>= (`shouldBe` 0)

        it "does not start another job after a command observes the newly trusted snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Idempotent Trust Command Venue"
                owner <- createUserRecord "xero-idempotent-command@example.com" "staff" True
                staleConnection <- createSyncableXeroConnection venue owner
                let now = fixedReferenceTrustTime

                firstState <- requestTrustedXeroReferenceData now (Just owner.id) staleConnection NoMissingPayrollReferenceDemand
                firstState.trustDecision `shouldSatisfy` \case
                    WaitForTrustedXeroReferenceSnapshot _ -> True
                    _ -> False
                activeState <- requestTrustedXeroReferenceData now (Just owner.id) staleConnection NoMissingPayrollReferenceDemand
                activeState.trustDecision `shouldSatisfy` \case
                    WaitForTrustedXeroReferenceSnapshot _ -> True
                    _ -> False
                query @AppJob |> fetchCount >>= (`shouldBe` 1)
                [firstJob] <- query @AppJob |> fetch
                _ <- firstJob |> set #status JobStatusSucceeded |> updateRecord
                _ <- staleConnection |> set #lastSyncAt (Just now) |> updateRecord

                secondState <- requestTrustedXeroReferenceData now (Just owner.id) staleConnection NoMissingPayrollReferenceDemand

                secondState.trustDecision `shouldBe` UseTrustedXeroReferenceSnapshot
                query @AppJob |> fetchCount >>= (`shouldBe` 1)

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
                    |> set #payload (Aeson.object ["xeroConnectionId" Aeson..= tshow trustedConnection.id, "tenantId" Aeson..= trustedConnection.tenantId, "requestedAt" Aeson..= now, "retryNumber" Aeson..= (1 :: Int)])
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

fixedReferenceTrustTime :: UTCTime
fixedReferenceTrustTime = UTCTime (fromGregorian 2026 8 7) (secondsToDiffTime 0)

oneDay :: NominalDiffTime
oneDay = 24 * 60 * 60
