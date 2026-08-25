module Test.TimesheetApprovalSpec where

import Application.Error.Types (appErrorCode)
import Application.Helper.Audit.Vocabulary (AuditEventType (TimesheetApprovedAudit),
                                            auditEventTypeText)
import Application.TimesheetApproval
import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Concurrent.Async (concurrently, wait, withAsync)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (addUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.XeroTimesheetPreviewSpec (PreviewFixture (..))
import qualified Test.XeroTimesheetReadinessSpec as Readiness
import qualified Test.XeroTimesheetReservationSpec as Reservation

tests :: Spec
tests = describe "Timesheet approval engine" do
    it "refreshes one approval atomically, retains its prior ledger, and audits both calculation ids" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Readiness.createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
            entry <- fetchFixtureEntry fixture
            expected <- expectedIdentity entry
            oldCalculationId <- maybe (expectationFailure "expected active calculation" >> fail "missing calculation") (pure . unpackId) entry.activePayCalculationId
            oldApprovedAt <- maybe (expectationFailure "expected approval timestamp" >> fail "missing approval timestamp") pure entry.approvedAt

            result <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected

            refreshed <- either (\appError -> expectationFailure (Text.unpack (tshow appError)) >> fail "approval refresh failed") (pure . (.approvalEngineEntry)) result
            refreshed.activePayCalculationId `shouldSatisfy` maybe False ((/= oldCalculationId) . unpackId)
            refreshed.approvedByUserId `shouldBe` Just (unpackId fixture.owner.id)
            refreshed.approvedAt `shouldSatisfy` maybe False (> oldApprovedAt)
            query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId entry.id) |> fetchCount >>= (`shouldBe` 2)
            oldCalculation <- fetch (Id oldCalculationId :: Id TimesheetPayCalculation)
            oldCalculation.sealedAt `shouldSatisfy` isJust
            audit <- query @AuditEvent
                |> filterWhere (#eventType, auditEventTypeText TimesheetApprovedAudit)
                |> orderByDesc #createdAt
                |> fetchOne
            newCalculationId <- maybe (expectationFailure "expected replacement calculation" >> fail "missing replacement") (pure . unpackId) refreshed.activePayCalculationId
            audit.payload `shouldSatisfy` payloadHasRefreshProvenance oldCalculationId newCalculationId
            auditCountAfterRefresh <- query @AuditEvent |> fetchCount
            let fabricatedOlderControl = expected { expectedActiveCalculationId = unpackId fixture.owner.id }
            staleResult <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id fabricatedOlderControl
            staleResult `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-control-stale") . appErrorCode) (const False)
            let fabricatedTimestampControl = expected { expectedApprovedAt = addUTCTime 1 expected.expectedApprovedAt }
            staleTimestampResult <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id fabricatedTimestampControl
            staleTimestampResult `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-control-stale") . appErrorCode) (const False)
            query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId entry.id) |> fetchCount >>= (`shouldBe` 2)
            query @AuditEvent |> fetchCount >>= (`shouldBe` auditCountAfterRefresh)

    it "rolls back every replacement row when current Xero mapping is incomplete" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Readiness.createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
            entry <- fetchFixtureEntry fixture
            expected <- expectedIdentity entry
            calculationCount <- query @TimesheetPayCalculation |> fetchCount
            auditCount <- query @AuditEvent |> fetchCount

            result <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected

            result `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-still-blocked") . appErrorCode) (const False)
            reloaded <- fetch entry.id
            reloaded.activePayCalculationId `shouldBe` entry.activePayCalculationId
            reloaded.approvedAt `shouldBe` entry.approvedAt
            query @TimesheetPayCalculation |> fetchCount >>= (`shouldBe` calculationCount)
            query @AuditEvent |> fetchCount >>= (`shouldBe` auditCount)

    it "rejects a stale control even when the prior approval is otherwise healthy" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Readiness.createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
            entry <- fetchFixtureEntry fixture
            expected <- expectedIdentity entry
            let staleExpected = expected { expectedActiveCalculationId = unpackId fixture.owner.id }
            calculationCount <- query @TimesheetPayCalculation |> fetchCount

            result <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id staleExpected

            result `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-control-stale") . appErrorCode) (const False)
            query @TimesheetPayCalculation |> fetchCount >>= (`shouldBe` calculationCount)

    it "returns a typed timeout after waiting five seconds for the Timesheet row lock" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Readiness.createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
            entry <- fetchFixtureEntry fixture
            expected <- expectedIdentity entry
            locked <- newEmptyMVar
            let holdLock = withTransaction do
                    (_ :: [Only UUID]) <- sqlQuery "SELECT id FROM timesheet_entries WHERE id = ? FOR UPDATE" (Only (unpackId entry.id))
                    putMVar locked ()
                    threadDelay 6000000
            withAsync holdLock \holder -> do
                takeMVar locked
                result <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected
                result `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-refresh-lock-timed-out") . appErrorCode) (const False)
                wait holder
            query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId entry.id) |> fetchCount >>= (`shouldBe` 1)

    it "blocks refresh only while a provider write is active" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Reservation.reservationFixture
            entry <- maybe (expectationFailure "expected reservation source entry" >> fail "missing entry") pure (listToMaybe fixture.entries)
            expected <- expectedIdentity entry
            _ <- Reservation.reserve fixture [entry]
            calculationCount <- query @TimesheetPayCalculation |> fetchCount

            result <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected

            result `shouldSatisfy` either ((== "application.timesheet-approval.error.timesheet-approval/approval-provider-write-active") . appErrorCode) (const False)
            query @TimesheetPayCalculation |> fetchCount >>= (`shouldBe` calculationCount)
            submission <- query @XeroTimesheetSubmission |> fetchOne
            _ <- submission |> set #status XeroTimesheetSubmissionStatusEnumSubmitted |> updateRecord
            retry <- refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected
            retry `shouldSatisfy` either (const False) (const True)

    it "coalesces concurrent controls onto the first completed healthy replacement" $ withDatabaseTestContext $ withContext do
        withCleanDb do
            fixture <- Readiness.createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
            entry <- fetchFixtureEntry fixture
            expected <- expectedIdentity entry

            (left, right) <- concurrently
                (refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected)
                (refreshProblemApproval fixture.owner.id fixture.venue.id entry.id expected)

            [left, right] `shouldSatisfy` all (either (const False) (const True))
            map (fmap (.approvalEngineChanged)) [left, right] `shouldMatchList` [Right True, Right False]
            query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId entry.id) |> fetchCount >>= (`shouldBe` 2)

fetchFixtureEntry :: (?modelContext :: ModelContext) => Readiness.ReadinessFixture -> IO TimesheetEntry
fetchFixtureEntry fixture =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId fixture.venue.id)
        |> filterWhere (#isApproved, True)
        |> fetchOne

expectedIdentity :: TimesheetEntry -> IO ExpectedApprovalIdentity
expectedIdentity entry = ExpectedApprovalIdentity
    <$> maybe (expectationFailure "expected active calculation" >> fail "missing calculation") (pure . unpackId) entry.activePayCalculationId
    <*> maybe (expectationFailure "expected approval timestamp" >> fail "missing timestamp") pure entry.approvedAt

payloadHasRefreshProvenance :: UUID -> UUID -> Aeson.Value -> Bool
payloadHasRefreshProvenance oldCalculationId newCalculationId (Aeson.Object object) =
    KeyMap.lookup "source" object == Just (Aeson.String "xero_preparation_refresh")
        && KeyMap.lookup "priorCalculationId" object == Just (Aeson.toJSON oldCalculationId)
        && KeyMap.lookup "newCalculationId" object == Just (Aeson.toJSON newCalculationId)
payloadHasRefreshProvenance _ _ _ = False
