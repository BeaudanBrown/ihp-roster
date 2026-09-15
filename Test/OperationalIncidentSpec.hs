module Test.OperationalIncidentSpec where

import Application.EmailDelivery (emailDeliveryJobKind)
import Application.OperationalIncident
import Control.Concurrent.Async (concurrently)
import Control.Monad (void)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.Time.Clock (addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Operational incident reconciliation" do
        it "serializes concurrent opening and permanently deduplicates recipients" $ withContext do
            withCleanDb do
                recipient <- createUserRecordWithPlatformRole "incident-admin@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                let input = observation now True 10 "coverage_missing"
                _ <- concurrently (reconcileOperationalIncident input) (reconcileOperationalIncident input)

                query @OperationalIncident |> fetchCount >>= (`shouldBe` 1)
                query @OperationalIncidentEvent |> fetchCount >>= (`shouldBe` 1)
                recipients <- query @OperationalIncidentEventRecipient |> fetch
                map (.recipientUserId) recipients `shouldBe` [unpackId recipient.id]
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 1)

        it "records only explicit escalation, recovery and recurrence transitions" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "incident-lifecycle@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                _ <- reconcileOperationalIncident (observation now True 10 "degraded")
                _ <- reconcileOperationalIncident (observation (addUTCTime 1 now) True 10 "same-impact")
                _ <- reconcileOperationalIncident (observation (addUTCTime 2 now) True 20 "payroll-blocked")
                markAllDeliveryJobsSent
                _ <- reconcileOperationalIncident (observation (addUTCTime 3 now) False 20 "recovered")
                _ <- reconcileOperationalIncident (observation (addUTCTime 4 now) True 10 "degraded")

                events <- query @OperationalIncidentEvent |> orderByAsc #eventSequence |> fetch
                map (.transition) events `shouldBe` ["opened", "impact_escalated", "recovered", "recurred"]
                map (.eligibleRecipientCount) events `shouldBe` [1, 1, 1, 1]
                incident <- query @OperationalIncident |> fetchOne
                incident.occurrenceCount `shouldBe` 2
                incident.state `shouldBe` "open"

        it "records zero recipients without replaying the terminal event" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                _ <- reconcileOperationalIncident (observation now True 10 "missing")
                event <- query @OperationalIncidentEvent |> fetchOne
                event.eligibleRecipientCount `shouldBe` 0
                event.recipientsReconciledAt `shouldBe` Just now

                _ <- createUserRecordWithPlatformRole "incident-late-admin@example.com" "staff" (Just SuperAdmin) True
                _ <- reconcileOperationalIncident (observation (addUTCTime 1 now) True 10 "missing")
                query @OperationalIncidentEventRecipient |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 0)

        it "does not notify recovery when no earlier event reached SMTP sent" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "incident-unsent@example.com" "staff" (Just SuperAdmin) True
                now <- getCurrentTime
                _ <- reconcileOperationalIncident (observation now True 10 "missing")
                _ <- reconcileOperationalIncident (observation (addUTCTime 1 now) False 10 "healthy")
                events <- query @OperationalIncidentEvent |> orderByAsc #eventSequence |> fetch
                map (.notificationRequired) events `shouldBe` [True, False]
                map (.eligibleRecipientCount) events `shouldBe` [1, 0]

        it "keeps venue-scoped identities isolated" $ withContext do
            withCleanDb do
                firstVenue <- createVenueWithConfig "Incident First"
                secondVenue <- createVenueWithConfig "Incident Second"
                now <- getCurrentTime
                _ <- reconcileOperationalIncident ((observation now True 10 "failed") { scopeKey = "venue:" <> tshow (unpackId firstVenue.id), venueId = Just (unpackId firstVenue.id) })
                _ <- reconcileOperationalIncident ((observation now True 10 "failed") { scopeKey = "venue:" <> tshow (unpackId secondVenue.id), venueId = Just (unpackId secondVenue.id) })
                incidents <- query @OperationalIncident |> fetch
                map (.venueId) incidents `shouldMatchList` [Just (unpackId firstVenue.id), Just (unpackId secondVenue.id)]

        it "rolls back incident creation when bounded metadata is rejected" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                let oversized = Aeson.object ["value" Aeson..= replicate 5000 ('x' :: Char)]
                result <- Exception.try (reconcileOperationalIncident ((observation now True 10 "bad") { safeMetadata = oversized })) :: IO (Either Exception.SomeException ReconciliationResult)
                result `shouldSatisfy` isLeft
                query @OperationalIncident |> fetchCount >>= (`shouldBe` 0)
                query @OperationalIncidentEvent |> fetchCount >>= (`shouldBe` 0)

observation :: UTCTime -> Bool -> Int -> Text -> IncidentObservation
observation observedAt isActive impactRank impactKey =
    IncidentObservation
        { category = "test_category"
        , scopeKey = "global"
        , stableIdentity = "test-incident"
        , affectedSource = "test-source"
        , venueId = Nothing
        , observedAt
        , isActive
        , severity = if impactRank >= 20 then IncidentCritical else IncidentWarning
        , impactKey
        , impactRank
        , symptomCodes = [impactKey]
        , safeMetadata = Aeson.object ["check" Aeson..= ("bounded" :: Text)]
        }

markAllDeliveryJobsSent :: (?modelContext :: ModelContext) => IO ()
markAllDeliveryJobsSent = do
    jobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
    forM_ jobs \job ->
        void $
            job
                |> set #status JobStatusSucceeded
                |> set #result (Aeson.object ["deliveryStatus" Aeson..= ("sent" :: Text)])
                |> updateRecord
