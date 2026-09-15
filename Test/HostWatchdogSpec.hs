module Test.HostWatchdogSpec where

import Application.EmailDelivery.Support
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Host watchdog Support projection" do
        it "exposes only bounded backup and isolated-restore status" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                _ <-
                    newRecord @HostWatchdogStatus
                        |> set #hostName (Id "rozzy")
                        |> set #observedAt now
                        |> set #lastBackupSnapshotAt (Just now)
                        |> set #lastRestoreVerifiedAt (Just now)
                        |> set #backupResult "success"
                        |> set #verificationResult "success"
                        |> createRecord

                health <- fetchNotificationHealth
                health.hostWatchdogStatus `shouldSatisfy` isJust
                ((.lastBackupSnapshotAt) =<< health.hostWatchdogStatus) `shouldSatisfy` isJust
                ((.lastRestoreVerifiedAt) =<< health.hostWatchdogStatus) `shouldSatisfy` isJust
                (.backupResult) <$> health.hostWatchdogStatus `shouldBe` Just "success"
                (.verificationResult) <$> health.hostWatchdogStatus `shouldBe` Just "success"
