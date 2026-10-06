module Test.DaysheetReportHistorySpec where

import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Application.Daysheet.ReportCodec (decodeReportContent)
import Application.Daysheet.ReportHistory
import Application.Daysheet.ReportStorage
import Application.EmailDelivery.Correlation (prepareProviderCorrelation, markSmtpAccepted)
import Application.EmailDelivery.Status
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
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
        it "reads the frozen content, sender and exact old recipients after corrections and replacement" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right firstRecipient <- addReportRecipient owner version.id reportKey "first@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                Right initial <- readFrozenReport manager snapshot.id
                initial.operationalDate `shouldBe` day
                initial.origin `shouldBe` DaysheetManual
                initial.senderId `shouldBe` Just (Id manager.userId)
                initial.senderAddress `shouldBe` Just "frozen-manager@example.test"
                initial.capturedAt `shouldBe` snapshot.capturedAt
                initial.cutoffAt `shouldBe` Nothing
                map (.address) initial.recipients `shouldBe` ["first@example.test"]
                map ((.queue) . (.delivery)) initial.recipients `shouldBe` [DeliveryQueued]
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "New live value")
                Right _ <- removeReportRecipient owner reportKey firstRecipient.id
                Right _ <- addReportRecipient owner version.id reportKey "replacement@example.test"
                Right retained <- readFrozenReport manager snapshot.id
                Right retained.content `shouldBe` decodeReportContent snapshot.content
                map (.recipientId) retained.recipients `shouldBe` [firstRecipient.id]
                map (.removed) retained.recipients `shouldBe` [True]
                map ((.queue) . (.delivery)) retained.recipients `shouldBe` [DeliveryCancelled]
        it "exposes acceptance and confirmed delivery without losing retry or cancellation facts" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "recipient@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                job <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                correlation <- prepareProviderCorrelation job
                now <- getCurrentTime
                accepted <- markSmtpAccepted correlation now
                _ <- job |> set #status JobStatusRetry |> updateRecord
                Right retry <- readFrozenReport manager snapshot.id
                map ((.provider) . (.delivery)) retry.recipients `shouldBe` [ProviderAccepted]
                map ((.queue) . (.delivery)) retry.recipients `shouldBe` [DeliveryRetrying]
                Right _ <- removeReportRecipient owner reportKey recipient.id
                _ <- accepted |> set #providerStatus "delivered" |> set #providerStatusAt (Just now) |> updateRecord
                Right removed <- readFrozenReport manager snapshot.id
                map ((.provider) . (.delivery)) removed.recipients `shouldBe` [ProviderConfirmed]
                map ((.queue) . (.delivery)) removed.recipients `shouldBe` [DeliveryCancelled]
        it "requires fresh manager authority and rejects foreign runs" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                otherVenue <- createVenueWithConfig "Other history"
                otherUser <- createUserRecord "other-history@example.test" "manager" True
                other <- createVenueMembershipRecord otherVenue otherUser Manager
                isLeft <$> readFrozenReport other snapshot.id `shouldReturn` True
                _ <- manager |> set #venueRole Worker |> updateRecord
                isLeft <$> readFrozenReport manager snapshot.id `shouldReturn` True
        it "does not present a forged or missing delivery job as queued or delivered" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- addReportRecipient owner version.id reportKey "intended@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                job <- query @AppJob |> filterWhere (#relatedId, Just (unpackId snapshot.id)) |> fetchOne
                _ <- job |> set #payload Aeson.Null |> updateRecord
                Right history <- readFrozenReport manager snapshot.id
                map (.address) history.recipients `shouldBe` ["intended@example.test"]
                map (.delivery) history.recipients `shouldBe` [unavailableDelivery]
