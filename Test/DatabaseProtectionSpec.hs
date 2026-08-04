module Test.DatabaseProtectionSpec where

import Control.Exception (SomeException, try)
import Data.Either (isLeft, isRight)
import qualified Data.Text as Text
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Types as PGTypes
import Generated.Types
import qualified Hasql.Session as HasqlSession
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult, sqlQuery, sqlQueryScalar,
                         unpackId)
import IHP.ModelSupport.Types (ModelContext (transactionRunner),
                               TransactionRunner (runInTransaction))
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
        it "keeps approval-pinned imported Xero remote identities immutable" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Immutable Xero identity"
                owner <- createUserRecord "immutable-xero@example.com" "staff" True
                importedItem <- createImportedXeroPayItemRecord venue owner "Pinned imported rate" "xero-rate-pinned" 42
                replacementItem <- newRecord @XeroImportedPayItem
                    |> set #venueId (unpackId venue.id)
                    |> set #xeroConnectionId importedItem.xeroConnectionId
                    |> set #xeroEarningsRateId "xero-rate-replacement"
                    |> set #name "Replacement imported rate"
                    |> set #earningsType "ordinarytimeearnings"
                    |> set #rateType "rateperunit"
                    |> set #typeOfUnits "hours"
                    |> set #ratePerUnit 44
                    |> set #importedByUserId (unpackId owner.id)
                    |> createRecord

                identityChange <- try (importedItem |> set #xeroEarningsRateId "xero-rate-changed" |> updateRecord) :: IO (Either SomeException XeroImportedPayItem)
                identityChange `shouldSatisfy` isLeft
                importedItem |> set #name "Refreshed display name" |> updateRecord >>= (\updated -> updated.name `shouldBe` "Refreshed display name")

                staff <- createStaffRecord venue Nothing "Pinned" "Worker"
                now <- getCurrentTime
                lockedVersion <- newRecord @StaffPayVersion
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId staff.id)
                    |> set #payAssignmentMode XeroRate
                    |> set #importedXeroPayItemId (Just importedItem.id)
                    |> set #employmentBasis Permanent
                    |> set #effectiveFrom (fromGregorian 2026 1 1)
                    |> set #createdByUserId (unpackId owner.id)
                    |> set #lockedAt (Just now)
                    |> set #lockedByUserId (Just (unpackId owner.id))
                    |> createRecord
                versionReroute <- try (lockedVersion |> set #importedXeroPayItemId (Just replacementItem.id) |> updateRecord) :: IO (Either SomeException StaffPayVersion)
                versionReroute `shouldSatisfy` isLeft
                modeChange <- try (lockedVersion |> set #payAssignmentMode RosterOnly |> set #importedXeroPayItemId Nothing |> updateRecord) :: IO (Either SomeException StaffPayVersion)
                modeChange `shouldSatisfy` isLeft

                awardLevel <- createPayLevelRecord venue "Level 1"
                replacementAwardLevel <- createPayLevelRecord venue "Level 2"
                awardStaff <- createStaffRecord venue Nothing "Pinned Award" "Worker"
                lockedAwardVersion <- newRecord @StaffPayVersion
                    |> set #venueId (unpackId venue.id)
                    |> set #staffId (unpackId awardStaff.id)
                    |> set #payAssignmentMode AwardRate
                    |> set #defaultAwardLevelId (Just (unpackId awardLevel.id))
                    |> set #employmentBasis Permanent
                    |> set #effectiveFrom (fromGregorian 2026 2 1)
                    |> set #createdByUserId (unpackId owner.id)
                    |> set #lockedAt (Just now)
                    |> set #lockedByUserId (Just (unpackId owner.id))
                    |> createRecord
                staffAwardChange <- try (lockedAwardVersion |> set #defaultAwardLevelId (Just (unpackId replacementAwardLevel.id)) |> updateRecord) :: IO (Either SomeException StaffPayVersion)
                staffAwardChange `shouldSatisfy` isLeft

                shiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Pinned shift"
                    |> set #sortOrder 1
                    |> createRecord
                lockedShiftVersion <- newRecord @ShiftTypePayVersion
                    |> set #venueId (unpackId venue.id)
                    |> set #shiftTypeId (unpackId shiftType.id)
                    |> set #payAssignmentMode XeroRate
                    |> set #importedXeroPayItemId (Just importedItem.id)
                    |> set #payrollLabel "Pinned payroll label"
                    |> set #effectiveFrom (fromGregorian 2026 1 1)
                    |> set #createdByUserId (unpackId owner.id)
                    |> set #lockedAt (Just now)
                    |> set #lockedByUserId (Just (unpackId owner.id))
                    |> createRecord
                labelChange <- try (lockedShiftVersion |> set #payrollLabel "Changed payroll label" |> updateRecord) :: IO (Either SomeException ShiftTypePayVersion)
                labelChange `shouldSatisfy` isLeft
                awardShiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Pinned Award shift"
                    |> set #sortOrder 2
                    |> createRecord
                lockedAwardShiftVersion <- newRecord @ShiftTypePayVersion
                    |> set #venueId (unpackId venue.id)
                    |> set #shiftTypeId (unpackId awardShiftType.id)
                    |> set #payAssignmentMode AwardRate
                    |> set #overrideAwardLevelId (Just (unpackId awardLevel.id))
                    |> set #payrollLabel "Pinned Award label"
                    |> set #effectiveFrom (fromGregorian 2026 2 1)
                    |> set #createdByUserId (unpackId owner.id)
                    |> set #lockedAt (Just now)
                    |> set #lockedByUserId (Just (unpackId owner.id))
                    |> createRecord
                shiftAwardChange <- try (lockedAwardShiftVersion |> set #overrideAwardLevelId (Just (unpackId replacementAwardLevel.id)) |> updateRecord) :: IO (Either SomeException ShiftTypePayVersion)
                shiftAwardChange `shouldSatisfy` isLeft

        it "rejects pay-assignment modes whose rate references do not match" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Pay assignment shapes"
                awardLevel <- createPayLevelRecord venue "Level 1"
                staff <- createStaffRecord venue Nothing "Shape" "Check"
                invalidStaff <- try (staff |> set #defaultAwardLevelId (Just awardLevel.id) |> updateRecord) :: IO (Either SomeException Staff)
                invalidStaff `shouldSatisfy` isLeft

                shiftType <- newRecord @ShiftType
                    |> set #venueId (unpackId venue.id)
                    |> set #name "Shape check"
                    |> set #sortOrder 1
                    |> createRecord
                invalidShiftType <- try (shiftType |> set #payAssignmentMode LegacyUnresolved |> updateRecord) :: IO (Either SomeException ShiftType)
                invalidShiftType `shouldSatisfy` isLeft

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

    describe "explicit roster shift assignment migration" do
        it "upgrades representative predecessor rows without deleting history or Timesheet provenance" $ withContext do
            withCleanDb do
                migrationSql <- TextIO.readFile "Application/Migration/1785813000.sql"
                sqlExecDiscardResult "DROP SCHEMA IF EXISTS assignment_migration_304 CASCADE" ()
                withTransaction do
                    sqlExecDiscardResult "CREATE SCHEMA assignment_migration_304" ()
                    sqlExecDiscardResult "SET LOCAL search_path TO assignment_migration_304, public" ()
                    sqlExecDiscardResult "CREATE TABLE staff (id UUID PRIMARY KEY, venue_id UUID NOT NULL)" ()
                    sqlExecDiscardResult "CREATE TABLE shift_types (id UUID PRIMARY KEY, venue_id UUID NOT NULL)" ()
                    sqlExecDiscardResult "CREATE TABLE roster_weeks (id UUID PRIMARY KEY, venue_id UUID NOT NULL)" ()
                    sqlExecDiscardResult "CREATE TABLE roster_days (id UUID PRIMARY KEY, roster_week_id UUID NOT NULL REFERENCES roster_weeks (id))" ()
                    sqlExecDiscardResult "CREATE TABLE roster_week_slot_definitions (id UUID PRIMARY KEY, roster_week_id UUID NOT NULL REFERENCES roster_weeks (id), deleted_at TIMESTAMPTZ)" ()
                    sqlExecDiscardResult
                        "CREATE TABLE roster_slots (id UUID PRIMARY KEY, roster_day_id UUID NOT NULL REFERENCES roster_days (id), staff_id UUID, roster_week_slot_definition_id UUID NOT NULL REFERENCES roster_week_slot_definitions (id), slot_sort_order INT DEFAULT 0 NOT NULL, row_index INT NOT NULL, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, timezone TEXT NOT NULL, shift_type_id UUID, deleted_at TIMESTAMPTZ, delete_reason TEXT, updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL, CONSTRAINT roster_slots_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE SET NULL, CONSTRAINT roster_slots_shift_type_id_fkey FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE SET NULL)"
                        ()
                    sqlExecDiscardResult "CREATE TABLE timesheet_entries (id UUID PRIMARY KEY, source_roster_slot_id UUID REFERENCES roster_slots (id) ON DELETE RESTRICT)" ()
                    sqlExecDiscardResult
                        "CREATE FUNCTION enforce_roster_slot_week_definition_integrity() RETURNS TRIGGER AS $$ BEGIN IF NOT EXISTS (SELECT 1 FROM roster_days rd JOIN roster_week_slot_definitions rwsd ON rwsd.id = NEW.roster_week_slot_definition_id WHERE rd.id = NEW.roster_day_id AND rd.roster_week_id = rwsd.roster_week_id) THEN RAISE EXCEPTION 'invalid predecessor placement'; END IF; RETURN NEW; END; $$ LANGUAGE plpgsql"
                        ()
                    sqlExecDiscardResult "CREATE TRIGGER enforce_roster_slot_week_definition_integrity BEFORE INSERT OR UPDATE ON roster_slots FOR EACH ROW EXECUTE FUNCTION enforce_roster_slot_week_definition_integrity()" ()
                    sqlExecDiscardResult
                        "CREATE FUNCTION prevent_hard_delete() RETURNS TRIGGER AS $$ BEGIN RAISE EXCEPTION 'hard delete blocked'; END; $$ LANGUAGE plpgsql"
                        ()
                    sqlExecDiscardResult "CREATE TRIGGER prevent_hard_delete_roster_slots BEFORE DELETE ON roster_slots FOR EACH ROW EXECUTE FUNCTION prevent_hard_delete()" ()
                    sqlExecDiscardResult "INSERT INTO staff (id, venue_id) VALUES ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'), ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002')" ()
                    sqlExecDiscardResult "INSERT INTO shift_types (id, venue_id) VALUES ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001')" ()
                    sqlExecDiscardResult "INSERT INTO roster_weeks (id, venue_id) VALUES ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001')" ()
                    sqlExecDiscardResult "INSERT INTO roster_days (id, roster_week_id) VALUES ('50000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001')" ()
                    sqlExecDiscardResult "INSERT INTO roster_week_slot_definitions (id, roster_week_id) VALUES ('60000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001')" ()
                    sqlExecDiscardResult
                        "INSERT INTO roster_slots (id, roster_day_id, staff_id, roster_week_slot_definition_id, row_index, starts_at, ends_at, timezone, shift_type_id, deleted_at, delete_reason) VALUES ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 0, '2026-08-03 00:00:00+00', '2026-08-03 08:00:00+00', 'Australia/Melbourne', '30000000-0000-0000-0000-000000000001', NULL, NULL), ('70000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000001', NULL, '60000000-0000-0000-0000-000000000001', 1, '2026-08-03 00:00:00+00', '2026-08-03 08:00:00+00', 'Australia/Melbourne', '30000000-0000-0000-0000-000000000001', NULL, NULL), ('70000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000001', NULL, '60000000-0000-0000-0000-000000000001', 2, NULL, NULL, 'Australia/Melbourne', NULL, NULL, NULL), ('70000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000001', 3, '2026-08-03 00:00:00+00', '2026-08-03 08:00:00+00', 'Australia/Melbourne', '30000000-0000-0000-0000-000000000001', NULL, NULL), ('70000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000001', NULL, '60000000-0000-0000-0000-000000000001', 4, NULL, NULL, 'Australia/Melbourne', NULL, NOW(), 'old_history'), ('70000000-0000-0000-0000-000000000006', '50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000001', 5, NULL, NULL, 'Australia/Melbourne', NULL, NULL, NULL)"
                        ()
                    sqlExecDiscardResult "INSERT INTO timesheet_entries (id, source_roster_slot_id) VALUES ('80000000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-000000000001')" ()

                    case transactionRunner ?modelContext of
                        Nothing -> error "Assignment migration fixture requires a transaction runner"
                        Just runner -> runInTransaction runner (HasqlSession.script migrationSql)

                    migratedRows :: [(UUID, Text, Maybe UUID, Bool, Maybe Text)] <-
                        sqlQuery "SELECT id, assignment_state, staff_id, deleted_at IS NOT NULL, delete_reason FROM roster_slots ORDER BY id" ()
                    migratedRows `shouldBe`
                        [ (migrationUuid "70000000-0000-0000-0000-000000000001", "staff", Just (migrationUuid "20000000-0000-0000-0000-000000000001"), False, Nothing)
                        , (migrationUuid "70000000-0000-0000-0000-000000000002", "open", Nothing, False, Nothing)
                        , (migrationUuid "70000000-0000-0000-0000-000000000003", "open", Nothing, True, Just "legacy_incomplete_shift_cleanup")
                        , (migrationUuid "70000000-0000-0000-0000-000000000004", "open", Nothing, False, Nothing)
                        , (migrationUuid "70000000-0000-0000-0000-000000000005", "open", Nothing, True, Just "old_history")
                        , (migrationUuid "70000000-0000-0000-0000-000000000006", "open", Nothing, True, Just "legacy_incomplete_shift_cleanup")
                        ]
                    sourceReferenceCount :: Int <- sqlQueryScalar "SELECT COUNT(*)::int FROM timesheet_entries WHERE source_roster_slot_id IS NOT NULL" ()
                    sourceReferenceCount `shouldBe` 1
                    hardDeleteTriggerState :: Text <- sqlQueryScalar "SELECT tgenabled::text FROM pg_trigger WHERE tgrelid = 'roster_slots'::regclass AND tgname = 'prevent_hard_delete_roster_slots'" ()
                    hardDeleteTriggerState `shouldBe` "O"
                    sqlExecDiscardResult "SET LOCAL search_path TO public" ()
                    sqlExecDiscardResult "DROP SCHEMA assignment_migration_304 CASCADE" ()

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

    describe "roster shift assignment constraints" do
        it "accepts only structurally complete explicit Staff or Open active shifts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Explicit shift assignment"
                staff <- createStaffRecord venue Nothing "Assigned" "Worker"
                foreignVenue <- createVenueWithConfig "Foreign shift assignment"
                foreignStaff <- createStaffRecord foreignVenue Nothing "Foreign" "Worker"
                shiftType <- ensureVenueDefaultShiftType venue
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let startsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 9 0 0)
                let endsAt = resolveTestFixtureInstant "Australia/Melbourne" defaultWeekEpoch (TimeOfDay 17 0 0)
                let insertShift :: Int -> Text -> Maybe UUID -> Maybe UTCTime -> Maybe UTCTime -> Maybe UUID -> IO (Either SomeException ())
                    insertShift rowIndex assignmentState maybeStaffId maybeStartsAt maybeEndsAt maybeShiftTypeId =
                        try
                            ( sqlExecDiscardResult
                                "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, row_index, assignment_state, staff_id, starts_at, ends_at, timezone, shift_type_id) VALUES (?, ?, ?, ?, ?, ?, ?, 'Australia/Melbourne', ?)"
                                (unpackId rosterDay.id, unpackId slotDefinition.id, rowIndex, assignmentState :: Text, maybeStaffId, maybeStartsAt, maybeEndsAt, maybeShiftTypeId)
                            ) :: IO (Either SomeException ())

                assigned <- insertShift 0 "staff" (Just (unpackId staff.id)) (Just startsAt) (Just endsAt) (Just (unpackId shiftType.id))
                open <- insertShift 1 "open" Nothing (Just startsAt) (Just endsAt) (Just (unpackId shiftType.id))
                staffWithoutWorker <- insertShift 2 "staff" Nothing (Just startsAt) (Just endsAt) (Just (unpackId shiftType.id))
                openWithWorker <- insertShift 3 "open" (Just (unpackId staff.id)) (Just startsAt) (Just endsAt) (Just (unpackId shiftType.id))
                missingStart <- insertShift 4 "staff" (Just (unpackId staff.id)) Nothing (Just endsAt) (Just (unpackId shiftType.id))
                missingEnd <- insertShift 5 "staff" (Just (unpackId staff.id)) (Just startsAt) Nothing (Just (unpackId shiftType.id))
                missingShiftType <- insertShift 6 "staff" (Just (unpackId staff.id)) (Just startsAt) (Just endsAt) Nothing
                wrongVenueStaff <- insertShift 7 "staff" (Just (unpackId foreignStaff.id)) (Just startsAt) (Just endsAt) (Just (unpackId shiftType.id))

                map isRight [assigned, open] `shouldBe` replicate 2 True
                map isLeft [staffWithoutWorker, openWithWorker, missingStart, missingEnd, missingShiftType, wrongVenueStaff]
                    `shouldBe` replicate 6 True

        it "retains structurally incomplete deleted history" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Deleted shift history"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- fetchSlotNameRecord venue "Early"
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName

                result <- try
                    ( sqlExecDiscardResult
                        "INSERT INTO roster_slots (roster_day_id, roster_week_slot_definition_id, row_index, assignment_state, staff_id, timezone, deleted_at, delete_reason) VALUES (?, ?, 0, 'open', NULL, 'Australia/Melbourne', NOW(), 'historical_fixture')"
                        (unpackId rosterDay.id, unpackId slotDefinition.id)
                    ) :: IO (Either SomeException ())

                result `shouldSatisfy` isRight

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

migrationUuid :: String -> UUID
migrationUuid value = fromMaybe (error "Invalid assignment migration fixture UUID") (UUID.fromString value)

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
