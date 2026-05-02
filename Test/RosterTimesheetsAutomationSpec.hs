module Test.RosterTimesheetsAutomationSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Helper.Controller (venueWeekStartDate)
import Application.RosterTimesheets.Automation
import Data.Maybe (fromJust)
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "Roster timesheet automation" do
        it "queues one delayed job per complete live roster slot when the venue opts in" $ withContext do
            withCleanDb do
                (venue, manager, rosterWeek, rosterDay, slot, _shiftType) <- createCompleteLiveRosterSlotFixture
                venueConfig <- fetchVenueConfigFor venue
                _ <- updateRecord (venueConfig |> set #autoTimesheetCreationEnabled True)
                slotName <- fetchSlotNameRecord venue "Early"
                incompleteSlot <- createRosterSlotRecord rosterDay slotName Nothing 1
                _ <- updateRecord (incompleteSlot |> set #startTime (Just (timeOfDay 12 0)))

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
                entry.isApproved `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId slot.id)

                versions <- query @TimesheetEntryVersion |> fetch
                length versions `shouldBe` 1

                performRosterTimesheetCreationJob job

                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 1)

createCompleteLiveRosterSlotFixture ::
    (?modelContext :: ModelContext) =>
    IO (Venue, User, RosterWeek, RosterDay, RosterSlot, ShiftType)
createCompleteLiveRosterSlotFixture = do
    venue <- createVenueWithConfig "Automation Venue"
    manager <- createUserRecord "roster-timesheet-manager@example.com" "staff" True
    _ <- createVenueMembershipRecord venue manager "manager"
    slotName <- fetchSlotNameRecord venue "Early"
    staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
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
