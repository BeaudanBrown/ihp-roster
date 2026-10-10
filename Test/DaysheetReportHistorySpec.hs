module Test.DaysheetReportHistorySpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Application.Daysheet.ReportCodec (decodeReportContent)
import Application.Daysheet.ReportHistory
import Application.Daysheet.ReportStorage
import Application.EmailDelivery.Correlation (prepareProviderCorrelation, markSmtpAccepted)
import Application.EmailDelivery.Status
import Application.Helper.FrontendContract.Surface.Daysheet.Live
import Application.Helper.FrontendContract.Surface.Daysheet.Resource
import Application.Helper.FrontendContract.Surface.DependencyPlanner
import Application.Helper.LiveUpdate.Runtime (SurfaceSubscription (..))
import qualified Data.Set as Set
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Data.List (sortOn)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.DaysheetReportStorageSpec (setup, reportKey, nonce, day)
import Test.Hspec
import Test.Support
import qualified Test.Support.Daysheet as Fixture

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet frozen report history" do
        it "maps venue delivery changes only to subscribed history fragments" $ \_ -> do
            let venue = nonce 1
            let scope = daysheetLiveScope venue (nonce 2)
            let history = daysheetHistoryLiveFragment (Just (nonce 3))
            let subscription = SurfaceSubscription scope "history" [history, daysheetBodyLiveFragment] 0
            planFrontendSurfaceInvalidations (Set.singleton (daysheetDeliveryResource venue)) [subscription]
                `shouldBe` [SurfaceInvalidationTarget scope [history]]
            planFrontendSurfaceInvalidations (Set.singleton (daysheetDeliveryResource (nonce 4))) [subscription]
                `shouldBe` []
        it "navigates one scoped run at a time, including deterministic timestamp ties and empty days" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right empty <- readFrozenHistory (memberAccess manager) state.daysheet.id Nothing
                (.snapshotId) <$> empty.selected `shouldBe` Nothing
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right first <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
                second <- newRecord @DaysheetReportSnapshot
                    |> set #id (Id (nonce 900)) |> set #requestKey (nonce 901)
                    |> set #venueId first.venueId |> set #daysheetId first.daysheetId
                    |> set #definitionCaptureId first.definitionCaptureId |> set #reportId first.reportId
                    |> set #origin first.origin |> set #senderId first.senderId |> set #cutoffAt first.cutoffAt
                    |> set #capturedAt first.capturedAt |> set #sourceRevision first.sourceRevision
                    |> set #content first.content |> set #recipientIds first.recipientIds |> createRecord
                let [older, newer] = sortOn (.id) [first, second]
                Right latest <- readFrozenHistory (memberAccess manager) state.daysheet.id Nothing
                (.snapshotId) <$> latest.selected `shouldBe` Just newer.id
                latest.older `shouldBe` Just older.id
                latest.newer `shouldBe` Nothing
                Right previous <- readFrozenHistory (memberAccess manager) state.daysheet.id (Just (unpackId older.id))
                previous.older `shouldBe` Nothing
                previous.newer `shouldBe` Just newer.id
                Right other <- createDailySheet (memberAccess manager) (addDays 1 day)
                wrongDay <- readFrozenHistory (memberAccess manager) other.daysheet.id (Just (unpackId older.id))
                isLeft wrongDay `shouldBe` True
                missing <- readFrozenHistory (memberAccess manager) state.daysheet.id (Just (nonce 999))
                isLeft missing `shouldBe` True
        it "reads the frozen content, sender and exact old recipients after corrections and replacement" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right firstRecipient <- addReportRecipient (memberAccess owner) version.id reportKey "first@example.test"
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right snapshot <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
                Right initial <- readFrozenReport (memberAccess manager) snapshot.id
                initial.operationalDate `shouldBe` day
                initial.origin `shouldBe` DaysheetManual
                initial.senderId `shouldBe` Just (Id manager.userId)
                initial.senderAddress `shouldBe` Just "frozen-manager@example.test"
                initial.capturedAt `shouldBe` snapshot.capturedAt
                initial.cutoffAt `shouldBe` Nothing
                map (.address) initial.recipients `shouldBe` ["first@example.test"]
                map ((.queue) . (.delivery)) initial.recipients `shouldBe` [DeliveryQueued]
                Right _ <- editDailyCell (memberAccess manager) state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "New live value")
                Right _ <- removeReportRecipient (memberAccess owner) reportKey firstRecipient.id
                Right _ <- addReportRecipient (memberAccess owner) version.id reportKey "replacement@example.test"
                Right retained <- readFrozenReport (memberAccess manager) snapshot.id
                Right retained.content `shouldBe` decodeReportContent snapshot.content
                map (.recipientId) retained.recipients `shouldBe` [firstRecipient.id]
                map (.removed) retained.recipients `shouldBe` [True]
                map ((.queue) . (.delivery)) retained.recipients `shouldBe` [DeliveryCancelled]
        it "exposes acceptance and confirmed delivery without losing retry or cancellation facts" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient (memberAccess owner) version.id reportKey "recipient@example.test"
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right snapshot <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
                job <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                correlation <- prepareProviderCorrelation job
                now <- getCurrentTime
                accepted <- markSmtpAccepted correlation now
                _ <- job |> set #status JobStatusRetry |> updateRecord
                Right retry <- readFrozenReport (memberAccess manager) snapshot.id
                map ((.provider) . (.delivery)) retry.recipients `shouldBe` [ProviderAccepted]
                map ((.queue) . (.delivery)) retry.recipients `shouldBe` [DeliveryRetrying]
                Right _ <- removeReportRecipient (memberAccess owner) reportKey recipient.id
                _ <- accepted |> set #providerStatus "delivered" |> set #providerStatusAt (Just now) |> updateRecord
                Right removed <- readFrozenReport (memberAccess manager) snapshot.id
                map ((.provider) . (.delivery)) removed.recipients `shouldBe` [ProviderConfirmed]
                map ((.queue) . (.delivery)) removed.recipients `shouldBe` [DeliveryCancelled]
        it "requires fresh manager authority and rejects foreign runs" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right snapshot <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
                otherVenue <- createVenueWithConfig "Other history"
                otherUser <- createUserRecord "other-history@example.test" "manager" True
                other <- createVenueMembershipRecord otherVenue otherUser Manager
                isLeft <$> readFrozenReport (memberAccess other) snapshot.id `shouldReturn` True
                _ <- manager |> set #venueRole Worker |> updateRecord
                isLeft <$> readFrozenReport (memberAccess manager) snapshot.id `shouldReturn` True
        it "does not present a forged or missing delivery job as queued or delivered" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- addReportRecipient (memberAccess owner) version.id reportKey "intended@example.test"
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                Right snapshot <- captureManualReport (memberAccess manager) state.daysheet.id reportKey (nonce 1)
                job <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                _ <- job |> set #payload Aeson.Null |> updateRecord
                Right history <- readFrozenReport (memberAccess manager) snapshot.id
                map (.address) history.recipients `shouldBe` ["intended@example.test"]
                map (.delivery) history.recipients `shouldBe` [unavailableDelivery]
