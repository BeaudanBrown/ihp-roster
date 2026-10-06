module Test.DaysheetReportStorageSpec where

import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Cutoff as Cutoff
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Application.Daysheet.ReportStorage
import Application.Daysheet.Storage
import Control.Concurrent.Async (concurrently)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.DaysheetCutoffCaptureSpec (makeClock)
import Test.Hspec
import Test.Support
import qualified Test.Support.Daysheet as Fixture
import Data.Either (isLeft)

reportKey :: D.ReportId
reportKey = D.ReportId (UUID.fromWords 0 0 0 710)

nonce :: Int -> UUID
nonce n = UUID.fromWords 0 0 0 (fromIntegral n)

day :: Day
day = fromGregorian 2030 10 1

setup :: (?modelContext :: ModelContext) => IO (VenueMembership, VenueMembership, DaysheetDefinitionVersion, DailyState)
setup = do
    venue <- createVenueWithConfig "Frozen reports"
    ownerUser <- createUserRecord "frozen-owner@example.test" "admin" True
    managerUser <- createUserRecord "frozen-manager@example.test" "manager" True
    owner <- createVenueMembershipRecord venue ownerUser VenueOwner
    manager <- createVenueMembershipRecord venue managerUser Manager
    let definition = Fixture.definition { D.reports = [D.Report reportKey "Closing"
            [D.Section (D.SectionId (nonce 711)) "Summary" [D.FieldBlock (Fixture.field 1), D.FieldBlock (Fixture.field 2)]] [D.FormattedReport]] }
    Right _ <- saveDraft owner 0 Nothing definition Fixture.references
    Right version <- publishDraft owner 0 0
    Right state <- createDailySheet manager day
    pure (owner, manager, version, state)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet frozen report persistence" do
        it "requires submission, then captures incomplete data and configured external recipients atomically" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "external@example.test"
                denied <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                isLeft denied `shouldBe` True
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
                Right submitted <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                snapshot.origin `shouldBe` DaysheetManual
                snapshot.cutoffAt `shouldBe` Nothing
                snapshot.senderId `shouldBe` Just (Id manager.userId)
                snapshot.sourceRevision `shouldBe` submitted.daysheet.revision
                snapshot.recipientIds `shouldBe` Aeson.toJSON [unpackId recipient.id]
                job <- query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchOne
                job.payloadSchemaVersion `shouldBe` 2
                job.relatedId `shouldBe` Just (unpackId snapshot.id)
                job.requestedByUserId `shouldBe` Just manager.userId
                query @AuditEvent |> filterWhere (#eventType, "daysheet_report_captured") |> fetchCount >>= (`shouldBe` 1)
        it "deduplicates concurrent/retried Sends and preserves old values and intended recipients" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right firstRecipient <- addReportRecipient owner version.id reportKey "first@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                (Right first, Right repeated) <- concurrently
                    (captureManualReport manager state.daysheet.id reportKey (nonce 1))
                    (captureManualReport manager state.daysheet.id reportKey (nonce 1))
                repeated.id `shouldBe` first.id
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Later correction")
                Right _ <- removeReportRecipient owner reportKey firstRecipient.id
                Right newRecipient <- addReportRecipient owner version.id reportKey "new@example.test"
                Right retry <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                retry `shouldBe` first
                Right fresh <- captureManualReport manager state.daysheet.id reportKey (nonce 2)
                fresh.id `shouldNotBe` first.id
                fresh.content `shouldNotBe` first.content
                fresh.recipientIds `shouldBe` Aeson.toJSON [unpackId newRecipient.id]
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 2)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 2)
                retained <- fetch first.id
                retained.content `shouldBe` first.content
                retained.recipientIds `shouldBe` Aeson.toJSON [unpackId firstRecipient.id]
        it "denies wrong reports, reused request scope, workers and foreign venue requests" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right _ <- submitDailySheet manager state.daysheet.id
                Right _ <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                isLeft <$> captureManualReport manager state.daysheet.id (D.ReportId (nonce 900)) (nonce 1) `shouldReturn` True
                isLeft <$> captureManualReport manager state.daysheet.id (D.ReportId (nonce 900)) (nonce 2) `shouldReturn` True
                venue <- createVenueWithConfig "Foreign report venue"
                user <- fetch (Id manager.userId :: Id User)
                foreignMember <- createVenueMembershipRecord venue user VenueOwner
                isLeft <$> captureManualReport foreignMember state.daysheet.id reportKey (nonce 3) `shouldReturn` True
                _ <- manager |> set #venueRole Worker |> updateRecord
                isLeft <$> captureManualReport manager state.daysheet.id reportKey (nonce 1) `shouldReturn` True
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
        it "captures submitted days only inside cutoff, without later reconstruction" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (addUTCTime (-0.5) (Cutoff.cutoffAt plan))
                captureScheduledReports clock manager.venueId plan `shouldReturn` Right Nothing
                Right _ <- submitDailySheet manager state.daysheet.id
                -- The already-advanced clock is now at cutoff: later submission
                -- cannot turn the previously skipped Draft into an automatic send.
                captureScheduledReports clock manager.venueId plan `shouldReturn` Right Nothing
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                (onTime, _) <- makeClock (addUTCTime (-0.5) (Cutoff.cutoffAt plan))
                Right (Just [snapshot]) <- captureScheduledReports onTime manager.venueId plan
                snapshot.origin `shouldBe` DaysheetScheduled
                snapshot.senderId `shouldBe` Nothing
                snapshot.cutoffAt `shouldBe` Just (Cutoff.cutoffAt plan)
                snapshot.capturedAt `shouldBe` Cutoff.cutoffAt plan
                captureScheduledReports onTime manager.venueId plan `shouldReturn` Right Nothing
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
        it "enforces submitted source, venue, revision and recipient scope in the database" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right recipient <- addReportRecipient owner version.id reportKey "scope@example.test"
                now <- getCurrentTime
                let D.ReportId reportId = reportKey
                let candidate = newRecord @DaysheetReportSnapshot
                        |> set #venueId state.daysheet.venueId |> set #daysheetId state.daysheet.id
                        |> set #definitionCaptureId state.daysheet.definitionCaptureId
                        |> set #reportId reportId |> set #requestKey (nonce 10)
                        |> set #origin DaysheetManual |> set #senderId (Just (Id manager.userId))
                        |> set #capturedAt now |> set #sourceRevision state.daysheet.revision
                        |> set #content (Aeson.object []) |> set #recipientIds (Aeson.toJSON [unpackId recipient.id])
                deniedDraft <- try @SomeException (createRecord candidate)
                isLeft deniedDraft `shouldBe` True
                Right submitted <- submitDailySheet manager state.daysheet.id
                capturedAt <- getCurrentTime
                let valid = candidate |> set #sourceRevision submitted.daysheet.revision |> set #capturedAt capturedAt
                other <- createVenueWithConfig "Wrong snapshot scope"
                forM_ [ valid |> set #venueId other.id
                      , valid |> set #sourceRevision (submitted.daysheet.revision + 1)
                      , valid |> set #recipientIds (Aeson.toJSON [unpackId recipient.id, unpackId recipient.id])
                      , valid |> set #reportId (nonce 999)
                      ] \invalid -> do
                    rejected <- try @SomeException (createRecord invalid)
                    isLeft rejected `shouldBe` True
                stored <- createRecord valid
                stored.daysheetId `shouldBe` state.daysheet.id
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
        it "rejects SQL mutation/deletion of snapshots and rolls back failed job creation" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- submitDailySheet manager state.daysheet.id
                Right snapshot <- captureManualReport manager state.daysheet.id reportKey (nonce 1)
                changed <- try @SomeException (snapshot |> set #content (Aeson.object []) |> updateRecord)
                isLeft changed `shouldBe` True
                removed <- try @SomeException (deleteRecord snapshot)
                isLeft removed `shouldBe` True
                -- Deliberately corrupt fixture bypasses the ordinary address
                -- validator. Shared envelope rejection must roll back the run.
                let D.ReportId reportId = reportKey
                _ <- newRecord @DaysheetReportRecipient |> set #venueId owner.venueId
                    |> set #reportId reportId |> set #definitionVersionId (unpackId version.id)
                    |> set #address "bad\naddress@example.test" |> set #createdBy owner.userId |> createRecord
                failed <- try @SomeException (captureManualReport manager state.daysheet.id reportKey (nonce 2))
                isLeft failed `shouldBe` True
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
                query @AuditEvent |> filterWhere (#eventType, "daysheet_report_captured") |> fetchCount >>= (`shouldBe` 1)
