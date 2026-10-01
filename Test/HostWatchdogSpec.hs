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

        it "projects stopped-worker and failed or stale backup verification incidents without host details" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                _ <-
                    newRecord @HostWatchdogStatus
                        |> set #hostName (Id "rozzy")
                        |> set #observedAt now
                        |> set #lastBackupSnapshotAt (Just (addUTCTime (-120000) now))
                        |> set #lastRestoreVerifiedAt Nothing
                        |> set #backupResult "failed"
                        |> set #verificationResult "failed"
                        |> createRecord
                forM_ hostIncidentCategories (createHostIncident now)

                health <- fetchNotificationHealth
                map (.category) health.openIncidents `shouldMatchList` hostIncidentCategories
                (.backupResult) <$> health.hostWatchdogStatus `shouldBe` Just "failed"
                (.verificationResult) <$> health.hostWatchdogStatus `shouldBe` Just "failed"

hostIncidentCategories :: [Text]
hostIncidentCategories =
    [ "host_worker_unavailable"
    , "host_backup_execution_failed"
    , "host_backup_snapshot_overdue"
    , "host_restore_verification_failed"
    , "host_restore_verification_overdue"
    ]

createHostIncident :: (?modelContext :: ModelContext) => UTCTime -> Text -> IO OperationalIncident
createHostIncident now category =
    newRecord @OperationalIncident
        |> set #category category
        |> set #scopeKey "host:rozzy"
        |> set #stableIdentity category
        |> set #affectedSource "host_watchdog"
        |> set #firstObservedAt now
        |> set #lastObservedAt now
        |> set #openedAt now
        |> set #state "open"
        |> set #severity "critical"
        |> set #impactKey "operator_intervention_required"
        |> set #impactRank 1
        |> createRecord
