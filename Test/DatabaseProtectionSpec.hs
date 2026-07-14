module Test.DatabaseProtectionSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft)
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery, unpackId)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "database schema retirement" do
        it "removes only the approved legacy tables and retains current export and Xero records" $ withContext do
            retiredTables :: [PG.Only (Maybe Text)] <-
                sqlQuery
                    "SELECT to_regclass(name)::text FROM unnest(ARRAY['report_definitions', 'report_definition_shift_type_filters', 'xero_payroll_calendar_selections']) AS names(name) ORDER BY name"
                    ()
            retainedTables :: [PG.Only (Maybe Text)] <-
                sqlQuery
                    "SELECT to_regclass(name)::text FROM unnest(ARRAY['export_jobs', 'xero_payroll_calendars', 'xero_timesheet_preparation_runs', 'xero_timesheet_submissions']) AS names(name) ORDER BY name"
                    ()

            map PG.fromOnly retiredTables `shouldBe` replicate 3 Nothing
            map PG.fromOnly retainedTables `shouldSatisfy` all isJust

    describe "database hard-delete protection" do
        it "blocks direct DELETEs on protected operational records" $ withContext do
            withCleanDb do
                preference <- createProtectedShiftPreference

                result <-
                    try
                        ( sqlExecDiscardResult
                            "DELETE FROM staff_shift_preferences WHERE id = ?"
                            (PG.Only (unpackId preference.id))
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft
                retainedPreference <-
                    query @StaffShiftPreference
                        |> filterWhere (#id, preference.id)
                        |> fetchOneOrNothing
                retainedPreference `shouldSatisfy` isJust

        it "allows maintenance hard DELETEs only when the session setting opts in" $ withContext do
            withCleanDb do
                preference <- createProtectedShiftPreference

                withTransaction do
                    sqlExecDiscardResult
                        "SET LOCAL ihp_roster.allow_hard_delete = 'on'"
                        ()
                    sqlExecDiscardResult
                        "DELETE FROM staff_shift_preferences WHERE id = ?"
                        (PG.Only (unpackId preference.id))

                deletedPreference <-
                    query @StaffShiftPreference
                        |> filterWhere (#id, preference.id)
                        |> fetchOneOrNothing
                deletedPreference `shouldBe` Nothing

    describe "database tenant integrity protection" do
        it "rejects direct SQL roster weeks whose venue does not match the roster group" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Tenant Roster A"
                venueB <- createVenueWithConfig "Tenant Roster B"
                foreignGroup <-
                    query @RosterGroup
                        |> filterWhere (#venueId, unpackId venueB.id)
                        |> fetchOne

                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO roster_weeks (venue_id, roster_group_id, week_offset) VALUES (?, ?, ?)"
                            (unpackId venueA.id, unpackId foreignGroup.id, 42 :: Int)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

        it "rejects direct SQL staff roster-group assignments across venues" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Tenant Staff Group A"
                venueB <- createVenueWithConfig "Tenant Staff Group B"
                staffA <- createStaffRecord venueA Nothing "Tenant" "Staff"
                foreignGroup <-
                    query @RosterGroup
                        |> filterWhere (#venueId, unpackId venueB.id)
                        |> fetchOne

                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO staff_roster_groups (staff_id, roster_group_id) VALUES (?, ?)"
                            (unpackId staffA.id, unpackId foreignGroup.id)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

        it "rejects direct SQL venue invitations whose adoption staff belongs to another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Tenant Invitation A"
                venueB <- createVenueWithConfig "Tenant Invitation B"
                foreignStaff <- createStaffRecord venueB Nothing "Tenant" "Trial"

                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO venue_invitations (venue_id, staff_id, email) VALUES (?, ?, ?)"
                            (unpackId venueA.id, unpackId foreignStaff.id, "trial-invite@example.com" :: Text)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

        it "rejects direct SQL timesheets whose shift type belongs to another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Tenant Timesheet A"
                venueB <- createVenueWithConfig "Tenant Timesheet B"
                staffA <- createStaffRecord venueA Nothing "Tenant" "Worker"
                foreignShiftType <- ensureVenueDefaultShiftType venueB

                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, worked_on, start_time, end_time, had_break, break_minutes) VALUES (?, ?, ?, ?, '09:00', '17:00', FALSE, 0)"
                            (unpackId venueA.id, unpackId staffA.id, unpackId foreignShiftType.id, defaultWeekEpoch)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

        it "keeps roster-derived timesheet staff, date, and source immutable" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Provenance Guard Venue"
                sourceStaff <- createStaffRecord venue Nothing "Source" "Staff"
                otherStaff <- createStaffRecord venue Nothing "Other" "Staff"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just sourceStaff) 0
                shiftType <- ensureVenueDefaultShiftType venue
                linkedEntry <-
                    newRecord @TimesheetEntry
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId sourceStaff.id)
                        |> set #shiftTypeId (unpackId shiftType.id)
                        |> set #workedOn defaultWeekEpoch
                        |> set #startTime (TimeOfDay 9 0 0)
                        |> set #endTime (TimeOfDay 17 0 0)
                        |> set #sourceRosterSlotId (Just (unpackId rosterSlot.id))
                        |> createRecord

                result <-
                    try
                        ( sqlExecDiscardResult
                            "UPDATE timesheet_entries SET staff_id = ?, worked_on = ?, source_roster_slot_id = NULL WHERE id = ?"
                            (unpackId otherStaff.id, addDays 1 defaultWeekEpoch, unpackId linkedEntry.id)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft
                retainedEntry <- fetch linkedEntry.id
                retainedEntry.staffId `shouldBe` unpackId sourceStaff.id
                retainedEntry.workedOn `shouldBe` defaultWeekEpoch
                retainedEntry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

                secondRosterSlot <- createRosterSlotRecord rosterDay slotName (Just sourceStaff) 1
                adHocEntry <- createTimesheetEntryRecord venue sourceStaff (addDays 1 defaultWeekEpoch)
                linkAfterInsertResult <-
                    try
                        ( sqlExecDiscardResult
                            "UPDATE timesheet_entries SET source_roster_slot_id = ? WHERE id = ?"
                            (unpackId secondRosterSlot.id, unpackId adHocEntry.id)
                        ) :: IO (Either SomeException ())
                linkAfterInsertResult `shouldSatisfy` isLeft

        it "rejects direct SQL leave requests whose staff belongs to another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Tenant Leave A"
                venueB <- createVenueWithConfig "Tenant Leave B"
                foreignStaff <- createStaffRecord venueB Nothing "Tenant" "Leave"

                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO leave_requests (venue_id, staff_id, start_date, end_date, status) VALUES (?, ?, ?, ?, 'pending')"
                            (unpackId venueA.id, unpackId foreignStaff.id, defaultWeekEpoch, defaultWeekEpoch |> addDays 1)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

createProtectedShiftPreference :: (?modelContext :: ModelContext) => IO StaffShiftPreference
createProtectedShiftPreference = do
    venue <- createVenueWithConfig "Delete Guard Venue"
    user <- createUserRecord "delete-guard@example.com" "staff" True
    staff <- createStaffRecord venue (Just user) "Delete" "Guard"
    newRecord @StaffShiftPreference
        |> set #venueId (unpackId venue.id)
        |> set #staffId (unpackId staff.id)
        |> set #weekdayIndex 1
        |> set #preferredStartHour 9
        |> set #preferredEndHour 17
        |> createRecord
