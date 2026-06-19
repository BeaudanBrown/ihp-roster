module Test.RosterTimesheetsAutomationSpec where

import Application.Async.Queue (AppJobRequest (..), EnqueueAppJobResult (..), enqueueAppJob)
import Application.Helper.Controller (venueWeekStartDate)
import Application.RosterTimesheets.Automation
import qualified Data.Aeson as Aeson
import Data.Maybe (fromJust)
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "Roster timesheet automation" do
        it "does not enqueue when the venue is not opted in or the roster week is draft" $ withContext do
            withCleanDb do
                (venue, _manager, liveWeek, _rosterDay, _slot, _shiftType) <- createCompleteLiveRosterSlotFixture

                disabledJobs <- enqueueRosterTimesheetCreationJobsForWeek Nothing liveWeek
                disabledJobs `shouldBe` []

                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                draftWeek <- liveWeek |> set #isLive False |> updateRecord

                draftJobs <- enqueueRosterTimesheetCreationJobsForWeek Nothing draftWeek
                draftJobs `shouldBe` []
                query @AppJob |> fetchCount >>= (`shouldBe` 0)

        it "does not enqueue jobs for complete trial-staff roster slots" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                trialStaff <- createStaffRecord venue Nothing "Trial" "RosterOnly"
                _ <- updateRecord (slot |> set #staffId (Just (unpackId trialStaff.id)))

                queuedJobs <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek

                queuedJobs `shouldBe` []
                query @AppJob |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "skips a queued job if its roster slot is reassigned to trial staff before execution" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                trialStaff <- createStaffRecord venue Nothing "Trial" "LateSwap"
                _ <- updateRecord (slot |> set #staffId (Just (unpackId trialStaff.id)))

                performRosterTimesheetCreationJob job

                assertJobSkipped job "trial_staff_roster_only"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "queues one delayed job per complete live roster slot when the venue opts in" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, rosterDay, slot, shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                incompleteSlot <- createRosterSlotRecord rosterDay slotName Nothing 1
                _ <- updateRecord (incompleteSlot |> set #startTime (Just (timeOfDay 12 0)))
                invalidTimingSlot <- createRosterSlotRecord rosterDay slotName Nothing 2
                _ <- updateRecord
                    ( invalidTimingSlot
                        |> set #staffId slot.staffId
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 8 0))
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> set #durationMinutes (Just 1380)
                    )

                queuedJobs <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek

                case queuedJobs of
                    [EnqueuedAppJob job] -> do
                        expectedRunAt <- rosterTimesheetRunAt venueConfig (addDays 1 (venueWeekStartDate venueConfig rosterWeek.weekOffset)) (timeOfDay 22 0) (timeOfDay 2 0)
                        job.jobKind `shouldBe` rosterTimesheetCreationJobKind
                        job.venueId `shouldBe` Just (unpackId venue.id)
                        job.relatedTable `shouldBe` Just "roster_slots"
                        job.relatedId `shouldBe` Just (unpackId slot.id)
                        job.dedupeKey `shouldBe` Just (rosterTimesheetDedupeKey slot.id)
                        job.requestedByUserId `shouldBe` Just (unpackId manager.id)
                        job.runAt `shouldBe` expectedRunAt
                    other ->
                        expectationFailure ("Expected one enqueued app job, got " <> cs (tshow other))

                jobs <- query @AppJob |> fetch
                length jobs `shouldBe` 1

        it "creates one pending timesheet from a roster slot and leaves it unchanged on rerun" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek

                performRosterTimesheetCreationJob job

                entries <- query @TimesheetEntry |> fetch
                length entries `shouldBe` 1
                let entry = fromJust (head entries)
                entry.venueId `shouldBe` unpackId venue.id
                entry.staffId `shouldBe` fromJust slot.staffId
                entry.shiftTypeId `shouldBe` unpackId shiftType.id
                entry.workedOn `shouldBe` addDays 1 (venueWeekStartDate venueConfig rosterWeek.weekOffset)
                entry.startTime `shouldBe` timeOfDay 22 0
                entry.endTime `shouldBe` timeOfDay 2 0
                entry.hadBreak `shouldBe` False
                entry.breakStartTime `shouldBe` Nothing
                entry.breakEndTime `shouldBe` Nothing
                entry.breakMinutes `shouldBe` 0
                entry.isApproved `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId slot.id)

                versions <- query @TimesheetEntryVersion |> fetch
                length versions `shouldBe` 1

                performRosterTimesheetCreationJob job

                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 1)

        it "creates an automatic 30 minute break for generated roster timesheets at least 6h15m long" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                _ <- updateRecord
                    ( slot
                        |> set #startTime (Just (timeOfDay 9 0))
                        |> set #endTime (Just (timeOfDay 15 15))
                        |> set #durationMinutes (Just 375)
                    )
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek

                performRosterTimesheetCreationJob job

                entry <- query @TimesheetEntry |> fetchOne
                entry.hadBreak `shouldBe` True
                entry.breakStartTime `shouldBe` Just (timeOfDay 14 30)
                entry.breakEndTime `shouldBe` Just (timeOfDay 15 0)
                entry.breakMinutes `shouldBe` 30

        it "skips a queued job when the venue opt-in is disabled before execution" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, _slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled False)

                performRosterTimesheetCreationJob job

                assertJobSkipped job "venue_opt_in_disabled"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "cancels pending and retry jobs for a roster week without touching terminal or running jobs" $ withContext do
            withCleanDb do
                (venue, _manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                notStartedJob <- createRosterTimesheetJobForSlot venue slot JobStatusNotStarted
                retryJob <- createRosterTimesheetJobForSlot venue slot JobStatusRetry
                runningJob <- createRosterTimesheetJobForSlot venue slot JobStatusRunning
                succeededJob <- createRosterTimesheetJobForSlot venue slot JobStatusSucceeded
                failedJob <- createRosterTimesheetJobForSlot venue slot JobStatusFailed

                cancelledCount <- cancelPendingRosterTimesheetCreationJobsForWeek rosterWeek

                cancelledCount `shouldBe` 2
                assertJobCancelled notStartedJob
                assertJobCancelled retryJob
                assertJobStatusAndResult runningJob JobStatusRunning (Aeson.object [])
                assertJobStatusAndResult succeededJob JobStatusSucceeded (Aeson.object [])
                assertJobStatusAndResult failedJob JobStatusFailed (Aeson.object [])
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "skips a queued job when the roster week is moved back to draft before execution" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, _slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                _ <- updateRecord (rosterWeek |> set #isLive False)

                performRosterTimesheetCreationJob job

                assertJobSkipped job "roster_week_not_live"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "skips a queued job when the roster slot is deleted before execution" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                now <- getCurrentTime
                _ <- updateRecord (slot |> set #deletedAt (Just now))

                performRosterTimesheetCreationJob job

                assertJobSkipped job "roster_slot_deleted"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "skips a queued job when the roster slot becomes incomplete before execution" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, _rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                [EnqueuedAppJob job] <- enqueueRosterTimesheetCreationJobsForWeek (Just manager.id) rosterWeek
                _ <- updateRecord (slot |> set #endTime Nothing)

                performRosterTimesheetCreationJob job

                assertJobSkipped job "roster_slot_incomplete"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "schedules overnight shifts two hours after their actual local end time" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Automation UTC Venue"
                venueConfig <- fetchVenueConfigFor venue
                utcConfig <- updateRecord (venueConfig |> set #timezone "UTC")

                runAt <- rosterTimesheetRunAt utcConfig (fromGregorian 2026 6 8) (timeOfDay 22 0) (timeOfDay 2 0)

                runAt `shouldBe` UTCTime (fromGregorian 2026 6 9) (secondsToDiffTime (4 * 60 * 60))

assertJobCancelled :: (?modelContext :: ModelContext) => AppJob -> IO ()
assertJobCancelled job =
    assertJobStatusAndResult
        job
        JobStatusSucceeded
        (Aeson.object
            [ "status" Aeson..= ("cancelled" :: Text)
            , "reason" Aeson..= ("roster_week_moved_to_draft" :: Text)
            ]
        )

assertJobSkipped :: (?modelContext :: ModelContext) => AppJob -> Text -> IO ()
assertJobSkipped job reason = do
    updatedJob <- fetch job.id
    updatedJob.status `shouldBe` JobStatusSucceeded
    updatedJob.result `shouldBe` Aeson.object ["status" Aeson..= ("skipped" :: Text), "reason" Aeson..= reason]

assertJobStatusAndResult :: (?modelContext :: ModelContext) => AppJob -> JobStatus -> Aeson.Value -> IO ()
assertJobStatusAndResult job expectedStatus expectedResult = do
    updatedJob <- fetch job.id
    updatedJob.status `shouldBe` expectedStatus
    updatedJob.result `shouldBe` expectedResult

createRosterTimesheetJobForSlot :: (?modelContext :: ModelContext) => Venue -> RosterSlot -> JobStatus -> IO AppJob
createRosterTimesheetJobForSlot venue rosterSlot status = do
    result <- enqueueAppJob
        AppJobRequest
            { jobKind = rosterTimesheetCreationJobKind
            , payload = Aeson.object []
            , payloadSchemaVersion = 1
            , requestedByUserId = Nothing
            , venueId = Just (unpackId venue.id)
            , relatedTable = Just "roster_slots"
            , relatedId = Just (unpackId rosterSlot.id)
            , dedupeKey = Nothing
            , runAt = Nothing
            }
    job <- case result of
        EnqueuedAppJob appJob -> pure appJob
        ExistingActiveAppJob _ -> error "Unexpected duplicate roster timesheet job"
    updateRecord (job |> set #status status)

createCompleteLiveRosterSlotFixture ::
    (?modelContext :: ModelContext) =>
    IO (Venue, User, RosterWeek, RosterDay, RosterSlot, ShiftType)
createCompleteLiveRosterSlotFixture = do
    venue <- createVenueWithConfig "Automation Venue"
    manager <- createUserRecord "roster-timesheet-manager@example.com" "staff" True
    _ <- createVenueMembershipRecord venue manager "manager"
    slotName <- fetchSlotNameRecord venue "Early"
    staffUser <- createUserRecord "roster-timesheet-worker@example.com" "staff" True
    _ <- createVenueMembershipRecord venue staffUser "worker"
    staffMember <- createStaffRecord venue (Just staffUser) "Alpha" "Crew"
    level <- createPayLevelRecord venue "Level 1"
    shiftType <- createShiftTypeRecord venue level "Late"
    rosterWeek <- createRosterWeekRecord venue 0 True
    rosterDay <- createRosterDayRecord rosterWeek 1
    slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
    updatedSlot <-
        slot
            |> set #startTime (Just (timeOfDay 22 0))
            |> set #endTime (Just (timeOfDay 2 0))
            |> set #shiftTypeId (Just (unpackId shiftType.id))
            |> set #durationMinutes (Just 240)
            |> updateRecord
    pure (venue, manager, rosterWeek, rosterDay, updatedSlot, shiftType)

fetchVenueConfigFor :: (?modelContext :: ModelContext) => Venue -> IO VenueConfig
fetchVenueConfigFor venue =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOne

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
