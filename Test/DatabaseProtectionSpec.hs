module Test.DatabaseProtectionSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Types as PGTypes
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery, sqlQueryScalar,
                         unpackId)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
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

    describe "authoritative time migration" do
        it "executes the migration resolver with first-occurrence and gap-rejection policy" $ withContext do
            migrationSql <- TextIO.readFile "Application/Migration/1784932300.sql"
            let (_, resolverAndRemainder) = Text.breakOn "CREATE OR REPLACE FUNCTION bepis_first_civil_occurrence" migrationSql
            let (resolverSql, remainder) = Text.breakOn "\nALTER TABLE roster_slots" resolverAndRemainder
            resolverSql `shouldSatisfy` (not . Text.null)
            remainder `shouldSatisfy` (not . Text.null)
            sqlExecDiscardResult (PGTypes.Query (encodeUtf8 resolverSql)) ()

            firstOccurrence :: UTCTime <- sqlQueryScalar
                "SELECT bepis_first_civil_occurrence('2026-04-05 02:30:00'::timestamp, 'Australia/Melbourne')"
                ()
            firstOccurrence
                `shouldBe` UTCTime (fromGregorian 2026 4 4) (secondsToDiffTime (15 * 60 * 60 + 30 * 60))
            nonexistent <- try
                (sqlQueryScalar
                    "SELECT bepis_first_civil_occurrence('2026-10-04 02:30:00'::timestamp, 'Australia/Melbourne')"
                    () :: IO UTCTime)
                :: IO (Either SomeException UTCTime)
            nonexistent `shouldSatisfy` isLeft

            sqlExecDiscardResult
                "DROP FUNCTION bepis_first_civil_occurrence(TIMESTAMP WITHOUT TIME ZONE, TEXT)"
                ()

    describe "authoritative time boundary constraints" do
        it "enforces duration, break pairing/containment, and timezone snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Boundary Constraint Venue"
                staff <- createStaffRecord venue Nothing "Boundary" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let startsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 9 0 0)
                let endsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 17 0 0)
                let beforeStart = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 8 45 0)
                let breakStart = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 12 0 0)

                nonPositiveTimesheet <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, timezone) VALUES (?, ?, ?, ?, ?, 'Australia/Melbourne')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, startsAt))
                    :: IO (Either SomeException ())
                halfBreak <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, break_starts_at, timezone) VALUES (?, ?, ?, ?, ?, ?, 'Australia/Melbourne')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, endsAt, breakStart))
                    :: IO (Either SomeException ())
                outsideBreak <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, break_starts_at, break_ends_at, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, 'Australia/Melbourne')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, endsAt, beforeStart, breakStart))
                    :: IO (Either SomeException ())
                emptyTimesheetTimezone <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, timezone) VALUES (?, ?, ?, ?, ?, '')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, endsAt))
                    :: IO (Either SomeException ())
                unsupportedTimesheetTimezone <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, timezone) VALUES (?, ?, ?, ?, ?, 'not-a-zone')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, endsAt))
                    :: IO (Either SomeException ())
                wholeShiftBreak <- try
                    (sqlExecDiscardResult
                        "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, break_starts_at, break_ends_at, timezone) VALUES (?, ?, ?, ?, ?, ?, ?, 'Australia/Melbourne')"
                        (unpackId venue.id, unpackId staff.id, unpackId shiftType.id, startsAt, endsAt, startsAt, endsAt))
                    :: IO (Either SomeException ())
                nonPositiveRoster <- try
                    (sqlExecDiscardResult
                        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, row_index, starts_at, ends_at, timezone) VALUES (?, ?, 0, ?, ?, 'Australia/Melbourne')"
                        (unpackId rosterDay.id, unpackId slotDefinition.id, startsAt, startsAt))
                    :: IO (Either SomeException ())
                emptyRosterTimezone <- try
                    (sqlExecDiscardResult
                        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, row_index, timezone) VALUES (?, ?, 1, '')"
                        (unpackId rosterDay.id, unpackId slotDefinition.id))
                    :: IO (Either SomeException ())
                unsupportedRosterTimezone <- try
                    (sqlExecDiscardResult
                        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, row_index, timezone) VALUES (?, ?, 2, 'not-a-zone')"
                        (unpackId rosterDay.id, unpackId slotDefinition.id))
                    :: IO (Either SomeException ())

                map isLeft [nonPositiveTimesheet, halfBreak, outsideBreak, emptyTimesheetTimezone, unsupportedTimesheetTimezone, nonPositiveRoster, emptyRosterTimezone, unsupportedRosterTimezone]
                    `shouldBe` replicate 8 True
                wholeShiftBreak `shouldSatisfy` isRight

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

                let startsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 9 0 0)
                let endsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 17 0 0)
                result <-
                    try
                        ( sqlExecDiscardResult
                            "INSERT INTO timesheet_entries (venue_id, staff_id, shift_type_id, starts_at, ends_at, timezone) VALUES (?, ?, ?, ?, ?, 'Australia/Melbourne')"
                            (unpackId venueA.id, unpackId staffA.id, unpackId foreignShiftType.id, startsAt, endsAt)
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft

        it "allows roster-derived staff corrections while keeping date and source immutable" $ withContext do
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
                        |> setTestWorkedOn defaultWeekEpoch
                        |> setTestStartTime (TimeOfDay 9 0 0)
                        |> setTestEndTime (TimeOfDay 17 0 0)
                        |> set #sourceRosterSlotId (Just (unpackId rosterSlot.id))
                        |> createRecord

                sqlExecDiscardResult
                    "UPDATE timesheet_entries SET staff_id = ? WHERE id = ?"
                    (unpackId otherStaff.id, unpackId linkedEntry.id)
                reassignedEntry <- fetch linkedEntry.id
                reassignedEntry.staffId `shouldBe` unpackId otherStaff.id
                testWorkedOn reassignedEntry `shouldBe` defaultWeekEpoch
                reassignedEntry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

                let movedStartsAt = resolveTestFixtureInstant linkedEntry.timezone (addDays 1 defaultWeekEpoch) (TimeOfDay 9 0 0)
                changedDateResult <-
                    try
                        ( sqlExecDiscardResult
                            "UPDATE timesheet_entries SET starts_at = ? WHERE id = ?"
                            (movedStartsAt, unpackId linkedEntry.id)
                        ) :: IO (Either SomeException ())
                changedDateResult `shouldSatisfy` isLeft

                removedSourceResult <-
                    try
                        ( sqlExecDiscardResult
                            "UPDATE timesheet_entries SET source_roster_slot_id = NULL WHERE id = ?"
                            (PG.Only (unpackId linkedEntry.id))
                        ) :: IO (Either SomeException ())
                removedSourceResult `shouldSatisfy` isLeft

                retainedEntry <- fetch linkedEntry.id
                retainedEntry.staffId `shouldBe` unpackId otherStaff.id
                testWorkedOn retainedEntry `shouldBe` defaultWeekEpoch
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
