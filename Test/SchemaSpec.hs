module Test.SchemaSpec where

import Application.Helper.Controller
import Application.Helper.Export
import Application.Helper.View (appendQueryParams, formatDateDisplay,
                                isTrialStaff, linkedActiveStaffForRosterPanel,
                                quarterHourTimeOptions,
                                quarterHourTimeOptionsInRange,
                                storageTimeToDisplayLabel)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude (Id, newRecord)
import IHP.HaskellSupport (set)
import IHP.ModelSupport (inputValue, textToId)
import IHP.NameSupport (columnNameToFieldName, fieldNameToColumnName)
import IHP.Prelude
import Test.Hspec
import Web.Controller.Timesheets (resetApprovalOnEdit)

tests :: Spec
tests = describe "Schema" do
    it "generates core foundation models" do
        let _ = (Nothing :: Maybe Staff)
        let _ = (Nothing :: Maybe RosterWeek)
        let _ = (Nothing :: Maybe RosterDay)
        let _ = (Nothing :: Maybe RosterSlot)
        let _ = (Nothing :: Maybe TimesheetEntry)
        let _ = (Nothing :: Maybe TimesheetEntryVersion)
        let _ = (Nothing :: Maybe LeaveRequest)
        let _ = (Nothing :: Maybe LeaveRequestEvent)
        let _ = (Nothing :: Maybe VenueConfig)
        let _ = (Nothing :: Maybe StaffAvailability)
        let _ = (Nothing :: Maybe StaffShiftPreference)
        let _ = (Nothing :: Maybe AwardLevel)
        let _ = (Nothing :: Maybe AwardLevelBaseRate)
        let _ = (Nothing :: Maybe AwardLevelPenaltyRate)
        let _ = (Nothing :: Maybe FwcMapdPenaltyRate)
        let _ = (Nothing :: Maybe PublicHoliday)
        let _ = (Nothing :: Maybe PayConfigSnapshot)
        let _ = (Nothing :: Maybe ShiftType)
        let _ = (Nothing :: Maybe ReportDefinition)
        let _ = (Nothing :: Maybe ReportDefinitionShiftTypeFilter)
        let _ = (Nothing :: Maybe RosterGroup)
        let _ = (Nothing :: Maybe SlotName)
        let _ = (Nothing :: Maybe DayName)
        let _ = (Nothing :: Maybe AuditEvent)
        let _ = (Nothing :: Maybe ExportJob)
        let _ = (Nothing :: Maybe VenueMembershipRoleEvent)
        let _ = (Nothing :: Maybe Passkey)
        let _ = (Nothing :: Maybe AppJob)
        True `shouldBe` True

    it "generates venue and venue membership models" do
        let _ = (Nothing :: Maybe Venue)
        let _ = (Nothing :: Maybe VenueMembership)
        let _ = (Nothing :: Maybe VenueInvitation)
        let _ = (Nothing :: Maybe VenueOnboardingInvitation)
        let _ = (Nothing :: Maybe EmailVerificationToken)
        True `shouldBe` True

    it "exposes a separate optional platform role on users" do
        let user = newRecord @User
        get #platformRole user `shouldBe` Nothing
        get #emailVerifiedAt user `shouldBe` Nothing

    it "exposes venue-scoped config fields on venue config" do
        let _readConfigFields venueConfig =
                ( get #venueId venueConfig
                , get #timezone venueConfig
                , get #rosterWeekStartsOn venueConfig
                , get #weekOffsetEpoch venueConfig
                , get #lateToEarlyMinStartGapMinutes venueConfig
                )
        True `shouldBe` True

    it "venue-owned tables expose venue_id field" do
        let _staffVenueId = get #venueId (newRecord @Staff)
        let _rosterGroupVenueId = get #venueId (newRecord @RosterGroup)
        let _rosterWeekVenueId = get #venueId (newRecord @RosterWeek)
        let _rosterWeekRosterGroupId = get #rosterGroupId (newRecord @RosterWeek)
        let _timesheetVenueId = get #venueId (newRecord @TimesheetEntry)
        let _timesheetSnapshotId = get #payConfigSnapshotId (newRecord @TimesheetEntry)
        let _leaveVenueId = get #venueId (newRecord @LeaveRequest)
        let _availabilityVenueId = get #venueId (newRecord @StaffAvailability)
        let _shiftPreferenceVenueId = get #venueId (newRecord @StaffShiftPreference)
        let _shiftPreferenceRosterGroupId = get #rosterGroupId (newRecord @StaffShiftPreference)
        let _shiftPreferenceSlotNameId = get #slotNameId (newRecord @StaffShiftPreference)
        let _shiftTypeVenueId = get #venueId (newRecord @ShiftType)
        let _reportDefinitionVenueId = get #venueId (newRecord @ReportDefinition)
        let _slotNameVenueId = get #venueId (newRecord @SlotName)
        let _slotNameRosterGroupId = get #rosterGroupId (newRecord @SlotName)
        let _dayNameVenueId = get #venueId (newRecord @DayName)
        let _configVenueId = get #venueId (newRecord @VenueConfig)
        True `shouldBe` True

    it "venue membership exposes role and active fields" do
        let membership = newRecord @VenueMembership
        inputValue (get #venueRole membership) `shouldBe` "worker"
        get #isActive membership `shouldBe` True

    it "venue invitations expose bootstrap role and status fields" do
        let invitation = newRecord @VenueInvitation
        inputValue (get #inviteRole invitation) `shouldBe` "worker"
        inputValue (get #status invitation) `shouldBe` "pending"

    it "venue onboarding invitations expose delivery and redemption fields" do
        let invitation = newRecord @VenueOnboardingInvitation
        get #email invitation `shouldBe` ""
        inputValue (get #status invitation) `shouldBe` "pending"
        inputValue (get #deliveryStatus invitation) `shouldBe` "queued"
        get #acceptedByUserId invitation `shouldBe` Nothing

    it "exposes normalized legacy user roles, venue roles, and leave statuses via shared helpers" do
        allUserRoleValues `shouldBe` ["staff", "manager", "admin"]
        allVenueRoleValues `shouldBe` ["worker", "manager", "venue_admin", "venue_owner"]
        allPlatformRoleValues `shouldBe` ["super_admin"]
        allLeaveRequestStatusValues `shouldBe` ["pending", "approved", "denied"]
        allAuditEventTypeValues `shouldBe`
            [ "timesheet_approved"
            , "timesheet_unapproved"
            , "timesheet_approval_reset"
            , "leave_approved"
            , "leave_denied"
            , "leave_deleted"
            , "venue_role_assigned"
            , "venue_role_changed"
            , "venue_bootstrapped"
            , "export_generated"
            , "export_downloaded"
            , "support_access_granted"
            , "login_succeeded"
            , "login_failed"
            , "login_blocked"
            , "passkey_step_up_succeeded"
            , "passkey_step_up_failed"
            ]
        allAuditSourceChannelValues `shouldBe` ["web", "htmx", "system"]
        allExportJobTypeValues `shouldBe` ["approved_timesheets_csv", "staff_pay_csv", "hourly_breakdown_zip", "payroll_earnings_csv"]
        allReportDefinitionEngineValues `shouldBe` ["staff_pay_csv", "hourly_breakdown_zip", "payroll_earnings_csv"]
        allExportJobStatusValues `shouldBe` ["pending", "ready", "expired"]

        parseUserRole ("staff" :: Text) `shouldBe` Just StaffRole
        parseUserRole ("manager" :: Text) `shouldBe` Just ManagerRole
        parseUserRole ("admin" :: Text) `shouldBe` Just AdminRole
        parseUserRole ("owner" :: Text) `shouldBe` Nothing

        parseVenueRole ("worker" :: Text) `shouldBe` Just WorkerRole
        parseVenueRole ("manager" :: Text) `shouldBe` Just ManagerRole'
        parseVenueRole ("venue_admin" :: Text) `shouldBe` Just VenueAdminRole
        parseVenueRole ("venue_owner" :: Text) `shouldBe` Just VenueOwnerRole
        parseVenueRole ("admin" :: Text) `shouldBe` Nothing

        parsePlatformRole ("super_admin" :: Text) `shouldBe` Just SuperAdminRole
        parsePlatformRole ("venue_owner" :: Text) `shouldBe` Nothing

        parseLeaveRequestStatus ("pending" :: Text) `shouldBe` Just LeavePending
        parseLeaveRequestStatus ("approved" :: Text) `shouldBe` Just LeaveApproved
        parseLeaveRequestStatus ("denied" :: Text) `shouldBe` Just LeaveDenied
        parseLeaveRequestStatus ("cancelled" :: Text) `shouldBe` Nothing
        parseExportJobType "approved_timesheets_csv" `shouldBe` Just ApprovedTimesheetsCsv
        parseExportJobType "staff_pay_csv" `shouldBe` Just StaffPayCsv
        parseExportJobType "hourly_breakdown_zip" `shouldBe` Just HourlyBreakdownZip
        parseExportJobType "payroll_earnings_csv" `shouldBe` Just PayrollEarningsCsv
        parseExportJobType "leave_csv" `shouldBe` Nothing
        parseReportDefinitionEngine "staff_pay_csv" `shouldBe` Just StaffPayCsvReport
        parseReportDefinitionEngine "hourly_breakdown_zip" `shouldBe` Just HourlyBreakdownZipReport
        parseReportDefinitionEngine "payroll_earnings_csv" `shouldBe` Just PayrollEarningsCsvReport
        parseReportDefinitionEngine "approved_timesheets_csv" `shouldBe` Nothing
        parseExportJobStatus "pending" `shouldBe` Just ExportPending
        parseExportJobStatus "ready" `shouldBe` Just ExportReady
        parseExportJobStatus "expired" `shouldBe` Just ExportExpired
        parseExportJobStatus "deleted" `shouldBe` Nothing

        map userRoleToText [StaffRole, ManagerRole, AdminRole] `shouldBe` allUserRoleValues
        map venueRoleToText [WorkerRole, ManagerRole', VenueAdminRole, VenueOwnerRole] `shouldBe` allVenueRoleValues
        map platformRoleToText [SuperAdminRole] `shouldBe` allPlatformRoleValues
        map leaveRequestStatusToText [LeavePending, LeaveApproved, LeaveDenied] `shouldBe` allLeaveRequestStatusValues
        map exportJobTypeToText [ApprovedTimesheetsCsv, StaffPayCsv, HourlyBreakdownZip, PayrollEarningsCsv] `shouldBe` allExportJobTypeValues
        map reportDefinitionEngineToText [StaffPayCsvReport, HourlyBreakdownZipReport, PayrollEarningsCsvReport] `shouldBe` allReportDefinitionEngineValues
        map exportJobStatusToText [ExportPending, ExportReady, ExportExpired] `shouldBe` allExportJobStatusValues

    it "avoids IN-based CHECK constraints that pg_dump rewrites into parser-hostile ANY(ARRAY ...)" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        let riskyCheckLines =
                filter
                    (\line -> "CHECK" `Text.isInfixOf` line && " IN (" `Text.isInfixOf` line)
                    (Text.lines schemaSqlText)
        riskyCheckLines `shouldBe` []

    it "keeps custom enum type names away from parser-hostile built-in type prefixes" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        let enumNames =
                map
                    (Text.takeWhile (\char -> char /= ' ' && char /= '\t'))
                    (mapMaybe (Text.stripPrefix "CREATE TYPE " . Text.stripStart) (Text.lines schemaSqlText))
        let riskyEnumNames =
                filter
                    (\name -> any (`Text.isPrefixOf` Text.toLower name) ["time", "timestamp", "interval"])
                    enumNames
        riskyEnumNames `shouldBe` []

    it "enforces one linked staff row per user per venue while still allowing trial staff" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy`
            Text.isInfixOf "CREATE UNIQUE INDEX idx_staff_linked_user_per_venue ON staff (venue_id, user_id) WHERE user_id IS NOT NULL AND is_active = TRUE AND archived_at IS NULL;"

    it "adds lifecycle columns and hard-delete triggers for payroll-adjacent records" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1777070800.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION prevent_hard_delete()"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_timesheet_entries BEFORE DELETE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_leave_requests BEFORE DELETE ON leave_requests"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_roster_slots BEFORE DELETE ON roster_slots"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (leave_request_id) REFERENCES leave_requests (id) ON DELETE RESTRICT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD CONSTRAINT timesheet_entries_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD CONSTRAINT roster_days_roster_week_id_fk FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD CONSTRAINT export_jobs_purged_by_user_id_fk FOREIGN KEY (purged_by_user_id) REFERENCES users (id) ON DELETE RESTRICT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "DROP CONSTRAINT IF EXISTS roster_slots_roster_day_id_fkey"

    it "enforces case-insensitive uniqueness for login emails" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy`
            Text.isInfixOf "CREATE UNIQUE INDEX idx_users_email_lower ON users (LOWER(email));"

    it "keeps app_jobs available for upgraded databases" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1777070900.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE IF NOT EXISTS app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX IF NOT EXISTS idx_app_jobs_pending ON app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX IF NOT EXISTS idx_app_jobs_active_dedupe"

    it "enforces V1 roster, availability, and timesheet shape constraints" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1777420000.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((weekday_index >= 0) AND (weekday_index <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((roster_week_starts_on >= 0) AND (roster_week_starts_on <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((day_offset >= 0) AND (day_offset <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((ideal_shifts_per_week >= 0) AND (ideal_shifts_per_week <= 7))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (end_date > start_date)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_slots_active_cell ON roster_slots (roster_day_id, row_index, slot_name_id) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_groups_one_active_default ON roster_groups (venue_id) WHERE is_default = TRUE AND is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_shift_types_active_name ON shift_types (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_staff_availability_active_weekday ON staff_availability (staff_id, weekday_index) WHERE weekday_index IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_staff_availability_active_date ON staff_availability (staff_id, specific_date) WHERE specific_date IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (((had_break = FALSE) AND break_start_time IS NULL AND break_end_time IS NULL AND break_minutes = 0) OR ((had_break = TRUE) AND break_start_time IS NOT NULL AND break_end_time IS NOT NULL AND break_minutes > 0))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND pay_config_snapshot_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND pay_config_snapshot_id IS NOT NULL))"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD CONSTRAINT timesheet_entries_approval_shape_check"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_slots_active_cell"

    it "stores passkeys as user-owned credential records" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE passkeys"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "credential_id BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(credential_id)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "public_key BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_passkeys_user_id ON passkeys (user_id);"

    describe "Leave request helpers" do
        it "validates leave date ranges as unavailable-from to available-again" do
            let startDate = fromGregorian 2025 3 10
            let sameDay = fromGregorian 2025 3 10
            let laterDate = fromGregorian 2025 3 12
            let earlierDate = fromGregorian 2025 3 9

            isLeaveDateRangeValid startDate sameDay `shouldBe` False
            isLeaveDateRangeValid startDate laterDate `shouldBe` True
            isLeaveDateRangeValid startDate earlierDate `shouldBe` False

        it "computes affected week offsets for a leave range" do
            let mondayVenueConfig =
                    newRecord @VenueConfig
                        |> set #rosterWeekStartsOn 1
                        |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay 1)
            affectedVenueWeekOffsetsForDateRange mondayVenueConfig (fromGregorian 2025 1 6) (fromGregorian 2025 1 13) `shouldBe` [0]
            affectedVenueWeekOffsetsForDateRange mondayVenueConfig (fromGregorian 2025 1 12) (fromGregorian 2025 1 14) `shouldBe` [0, 1]
            affectedVenueWeekOffsetsForDateRange mondayVenueConfig (fromGregorian 2025 1 20) (fromGregorian 2025 1 21) `shouldBe` [2]
            affectedVenueWeekOffsetsForDateRange mondayVenueConfig (fromGregorian 2025 1 21) (fromGregorian 2025 1 20) `shouldBe` []

        it "computes affected week offsets for a non-monday roster week" do
            let tuesdayVenueConfig =
                    newRecord @VenueConfig
                        |> set #rosterWeekStartsOn 2
                        |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay 2)
            affectedVenueWeekOffsetsForDateRange tuesdayVenueConfig (fromGregorian 2025 1 7) (fromGregorian 2025 1 14) `shouldBe` [0]
            affectedVenueWeekOffsetsForDateRange tuesdayVenueConfig (fromGregorian 2025 1 13) (fromGregorian 2025 1 15) `shouldBe` [0, 1]
            affectedVenueWeekOffsetsForDateRange tuesdayVenueConfig (fromGregorian 2025 1 14) (fromGregorian 2025 1 16) `shouldBe` [1]

    it "requires all mandatory contact fields for profile completion" do
        let completeStaff =
                newRecord @Staff
                    |> set #firstName "Taylor"
                    |> set #lastName "Smith"
                    |> set #phone "0400000000"
                    |> set #emergencyContactName "Jordan Smith"
                    |> set #emergencyContactPhone "0411111111"
                    |> set #idealShiftsPerWeek 3
        requiredProfileFieldsCompleted completeStaff `shouldBe` True
        requiredProfileFieldsCompleted (completeStaff |> set #phone "") `shouldBe` False
        requiredProfileFieldsCompleted (completeStaff |> set #emergencyContactName "") `shouldBe` False
        requiredProfileFieldsCompleted (completeStaff |> set #emergencyContactPhone "") `shouldBe` False

    describe "Venue-scoped authorization helpers" do
        it "uses venue role hierarchy worker < manager < venue_admin < venue_owner" do
            WorkerRole `shouldSatisfy` (< ManagerRole')
            ManagerRole' `shouldSatisfy` (< VenueAdminRole)
            VenueAdminRole `shouldSatisfy` (< VenueOwnerRole)

        it "checks minimum venue role correctly" do
            hasVenueRole WorkerRole WorkerRole `shouldBe` True
            hasVenueRole WorkerRole ManagerRole' `shouldBe` False
            hasVenueRole ManagerRole' WorkerRole `shouldBe` True
            hasVenueRole ManagerRole' VenueAdminRole `shouldBe` False
            hasVenueRole VenueAdminRole ManagerRole' `shouldBe` True
            hasVenueRole VenueOwnerRole VenueAdminRole `shouldBe` True

        it "selects the session venue when it matches an active membership" do
            let venueUuidA = fromString "00000000-0000-0000-0000-000000000001" :: UUID
            let venueUuidB = fromString "00000000-0000-0000-0000-000000000002" :: UUID
            let venueIdB = textToId ("00000000-0000-0000-0000-000000000002" :: Text) :: Id Venue
            let membershipA =
                    newRecord @VenueMembership
                        |> set #venueId venueUuidA
                        |> set #createdAt (UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0))
            let membershipB =
                    newRecord @VenueMembership
                        |> set #venueId venueUuidB
                        |> set #createdAt (UTCTime (fromGregorian 2025 1 2) (secondsToDiffTime 0))

            fmap (.venueId) (selectCurrentVenueMembership (Just venueIdB) [membershipA, membershipB])
                `shouldBe` Just venueUuidB

        it "falls back to the earliest active membership when the session venue is missing or stale" do
            let venueUuidA = fromString "00000000-0000-0000-0000-000000000001" :: UUID
            let venueUuidB = fromString "00000000-0000-0000-0000-000000000002" :: UUID
            let staleVenueId = textToId ("00000000-0000-0000-0000-000000000099" :: Text) :: Id Venue
            let membershipA =
                    newRecord @VenueMembership
                        |> set #venueId venueUuidA
                        |> set #createdAt (UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0))
            let membershipB =
                    newRecord @VenueMembership
                        |> set #venueId venueUuidB
                        |> set #createdAt (UTCTime (fromGregorian 2025 1 2) (secondsToDiffTime 0))

            fmap (.venueId) (selectCurrentVenueMembership Nothing [membershipB, membershipA])
                `shouldBe` Just venueUuidA
            fmap (.venueId) (selectCurrentVenueMembership (Just staleVenueId) [membershipB, membershipA])
                `shouldBe` Just venueUuidA

        it "does not treat users.user_role as venue authority" do
            let user =
                    newRecord @User
                        |> set #userRole "admin"
            let membership =
                    newRecord @VenueMembership
                        |> set #venueRole (unsafeEnumFromText @VenueRoleEnum "worker")

            parseUserRole user.userRole `shouldBe` Just AdminRole
            parseVenueRole membership.venueRole `shouldBe` Just WorkerRole
            maybe False (`hasVenueRole` VenueAdminRole) (parseVenueRole membership.venueRole)
                `shouldBe` False

    describe "Trial staff" do
        it "identifies trial staff by missing user_id" do
            let trialStaff = newRecord @Staff
                    |> set #firstName "Trial"
                    |> set #lastName "Person"
            isTrialStaff trialStaff `shouldBe` True

        it "identifies linked staff by present user_id" do
            let linkedStaff = newRecord @Staff
                    |> set #firstName "Linked"
                    |> set #lastName "Person"
                    |> set #userId (Just def)
            isTrialStaff linkedStaff `shouldBe` False

        it "filters roster panel staff to active linked staff sorted by first name" do
            let inactiveLinkedStaff = newRecord @Staff
                    |> set #firstName "Avery"
                    |> set #lastName "Inactive"
                    |> set #userId (Just def)
                    |> set #isActive False
            let trialStaff = newRecord @Staff
                    |> set #firstName "Blair"
                    |> set #lastName "Trial"
            let linkedStaffZed = newRecord @Staff
                    |> set #firstName "Zed"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
            let linkedStaffAlex = newRecord @Staff
                    |> set #firstName "Alex"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)

            map (.firstName) (linkedActiveStaffForRosterPanel [inactiveLinkedStaff, trialStaff, linkedStaffZed, linkedStaffAlex])
                `shouldBe` ["Alex", "Zed"]

    describe "Quarter-hour time picker helpers" do
        it "generates canonical options from 06:00 to 23:45 in 15-minute increments" do
            fmap fst quarterHourTimeOptions `shouldSatisfy` (not . null)
            (fmap fst (head quarterHourTimeOptions)) `shouldBe` Just "06:00"
            (fmap fst (last quarterHourTimeOptions)) `shouldBe` Just "23:45"
            length quarterHourTimeOptions `shouldBe` 72

        it "supports wrapped overnight ranges ending at 04:45 without an orphan 05:00 row" do
            let overnightOptions = quarterHourTimeOptionsInRange (TimeOfDay 6 0 0) (TimeOfDay 4 45 0)
            fmap fst (head overnightOptions) `shouldBe` Just "06:00"
            fmap fst (last overnightOptions) `shouldBe` Just "04:45"
            fmap fst overnightOptions `shouldNotContain` ["05:00"]

        it "renders stored HH:MM values as 12-hour AM/PM labels" do
            storageTimeToDisplayLabel "00:00" `shouldBe` "12:00 AM"
            storageTimeToDisplayLabel "06:00" `shouldBe` "6:00 AM"
            storageTimeToDisplayLabel "13:15" `shouldBe` "1:15 PM"
            storageTimeToDisplayLabel "23:45" `shouldBe` "11:45 PM"

        it "normalizes after-midnight shift durations consistently with overnight shifts" do
            shiftDurationMinutes (TimeOfDay 0 15 0) (TimeOfDay 4 0 0) `shouldBe` 225
            shiftDurationMinutes (TimeOfDay 23 0 0) (TimeOfDay 1 0 0) `shouldBe` 120

        it "returns original text when value is not a valid HH:MM input" do
            storageTimeToDisplayLabel "not-a-time" `shouldBe` "not-a-time"
            storageTimeToDisplayLabel "" `shouldBe` ""

        it "ensures all option labels are 12-hour AM/PM and values are HH:MM" do
            forM_ quarterHourTimeOptions $ \(value, label) -> do
                value `shouldSatisfy` (\v -> Text.length v == 5 && Text.index v 2 == ':')
                label `shouldSatisfy` (\l -> "AM" `Text.isSuffixOf` l || "PM" `Text.isSuffixOf` l)

    describe "Date formatting helpers" do
        it "renders display dates as dd/mm/yyyy" do
            formatDateDisplay (fromGregorian 2026 3 2) `shouldBe` "02/03/2026"

    describe "Query param helpers" do
        it "appends params to paths without an existing query string" do
            appendQueryParams "/NewTimesheetEntry" [("weekOffset", "60"), ("workedOn", "2026-03-02")]
                `shouldBe` "/NewTimesheetEntry?weekOffset=60&workedOn=2026-03-02"

        it "appends params to paths that already have query params" do
            appendQueryParams "/EditTimesheetEntry?timesheetEntryId=b72efdcc-5a11-4697-a0b1-b85f8d112c1f" [("weekOffset", "60")]
                `shouldBe` "/EditTimesheetEntry?timesheetEntryId=b72efdcc-5a11-4697-a0b1-b85f8d112c1f&weekOffset=60"

    it "all schema column names round-trip through IHP NameSupport" do
        -- Every column name must survive columnNameToFieldName and
        -- fieldNameToColumnName without throwing a parse error.
        -- This catches Haskell reserved-word collisions (e.g. "role")
        -- that only surface at runtime.
        let columnNames =
                [ "id", "email", "password_hash", "user_role"
                , "platform_role", "is_profile_completed", "email_verified_at", "locked_at", "failed_login_attempts"
                , "created_at", "updated_at", "user_id", "first_name"
                , "last_name", "preferred_name", "phone", "emergency_contact_name"
                , "emergency_contact_phone", "ideal_shifts_per_week", "employment_basis", "is_active"
                , "name", "default_award_level_id", "override_award_level_id"
                , "weekday_index", "shift_type_id", "day_name_id"
                , "venue_id", "venue_role", "invited_by_user_id", "accepted_by_user_id"
                , "invite_role", "accepted_at", "expires_at"
                , "timezone", "week_offset_epoch"
                , "late_to_early_min_start_gap_minutes"
                , "staff_timesheet_edit_window_days", "week_offset"
                , "is_live", "roster_week_id", "day_offset", "roster_day_id"
                , "staff_id", "slot_name_id", "row_index", "start_time"
                , "duration_minutes", "specific_date", "is_available", "note"
                , "start_date", "end_date", "status", "notes", "worked_on"
                , "end_time", "had_break", "break_start_time", "break_end_time"
                , "break_minutes", "is_approved", "approved_at", "approved_by_user_id"
                , "actor_user_id", "event_type", "target_table", "target_id"
                , "source_channel", "payload"
                , "requested_by_user_id", "export_type", "schema_version"
                , "pay_config_snapshot_version", "range_start", "range_end"
                , "scope", "delivery_method", "destination_metadata"
                , "generated_file_id", "file_name", "content_type"
                , "file_contents", "download_token", "expires_at"
                , "downloaded_at", "downloaded_by_user_id"
                , "roster_group_id"
                ]
        forM_ columnNames $ \col -> do
            let fieldName = columnNameToFieldName col
            let backToCol = fieldNameToColumnName fieldName
            backToCol `shouldBe` col

    describe "Pay SQL functions" do
        it "defines canonical pay function signatures in schema" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION resolve_effective_pay_level(p_staff_id UUID, p_shift_type_id UUID, p_day_of_week INT)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION calculate_timesheet_pay(p_entry_id UUID)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION calculate_timesheet_pay_range(p_staff_id UUID, p_from_date DATE, p_to_date DATE)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "RETURNS JSONB"

        it "documents expected JSON output fields for calculate_timesheet_pay" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'segments', sj.segments"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'totals', jsonb_build_object"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'paidMinutes', pw.paid_minutes"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'shiftTypeName', pw.shift_type_name"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'payLevelName', pw.pay_level_name"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'baseRate', sr.base_rate"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'amount', ROUND(((sr.segment_minutes::NUMERIC / 60.0) * sr.segment_hourly_rate), 2)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "'totalAmount', st.total_amount"

        it "uses calculate_timesheet_pay as the canonical range payload source" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "calculate_timesheet_pay(te.id)"

        it "defines weekday segmentation windows and boundaries" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('late_night_after_midnight'::TEXT, 0, 420, 1)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('ordinary'::TEXT, 420, 1140, 2)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('evening_after_7pm'::TEXT, 1140, 1440, 3)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "LEAST(r.start_minute_of_day + r.paid_minutes, 1860)"

        it "builds segment minute overlaps from the paid window and subtracts positioned breaks" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "GREATEST("
            schemaSqlText `shouldSatisfy` Text.isInfixOf "break_start_minute_of_day"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "break_end_minute_of_day"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "LEAST(pw.paid_end_minute_of_day, sw.window_end_minute)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "- GREATEST(pw.start_minute_of_day, sw.window_start_minute)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "- GREATEST(pw.break_start_minute_of_day, sw.window_start_minute)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "FILTER (WHERE sr.segment_minutes > 0)"

        it "uses projected award rates and penalty kinds in pay segments" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_level_base_rates"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_level_penalty_rates"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_time_penalty_allowances"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "ph.holiday_date = (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN EXTRACT(DOW FROM (pw.worked_on + CASE WHEN sw.window_start_minute >= 1440 THEN 1 ELSE 0 END))::INT = 6 THEN 'saturday_penalty'::award_penalty_kind_enum"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN sw.segment_name = 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN sw.segment_name = 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "SELECT alpr.hourly_rate"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "SELECT atpa.hourly_amount"

    describe "Timesheet validation helpers" do
        it "parseTimeParam parses valid HH:MM values" do
            parseTimeParam "09:00" `shouldBe` Just (TimeOfDay 9 0 0)
            parseTimeParam "14:30" `shouldBe` Just (TimeOfDay 14 30 0)
            parseTimeParam "23:45" `shouldBe` Just (TimeOfDay 23 45 0)

        it "parseTimeParam rejects invalid values" do
            parseTimeParam "" `shouldBe` Nothing
            parseTimeParam "25:00" `shouldBe` Nothing
            parseTimeParam "abc" `shouldBe` Nothing

        it "isQuarterHourTime accepts 15-minute boundaries" do
            isQuarterHourTime (TimeOfDay 9 0 0) `shouldBe` True
            isQuarterHourTime (TimeOfDay 9 15 0) `shouldBe` True
            isQuarterHourTime (TimeOfDay 9 30 0) `shouldBe` True
            isQuarterHourTime (TimeOfDay 9 45 0) `shouldBe` True

        it "isQuarterHourTime rejects non-15-minute values" do
            isQuarterHourTime (TimeOfDay 9 10 0) `shouldBe` False
            isQuarterHourTime (TimeOfDay 9 1 0) `shouldBe` False
            isQuarterHourTime (TimeOfDay 9 0 30) `shouldBe` False

        it "isQuarterHourMinutes validates break values" do
            isQuarterHourMinutes 0 `shouldBe` True
            isQuarterHourMinutes 15 `shouldBe` True
            isQuarterHourMinutes 30 `shouldBe` True
            isQuarterHourMinutes 10 `shouldBe` False
            isQuarterHourMinutes (-15) `shouldBe` False

        it "shiftDurationMinutes computes correct durations" do
            shiftDurationMinutes (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) `shouldBe` 480
            shiftDurationMinutes (TimeOfDay 6 0 0) (TimeOfDay 6 15 0) `shouldBe` 15
            shiftDurationMinutes (TimeOfDay 22 0 0) (TimeOfDay 2 0 0) `shouldBe` 240
            shiftDurationMinutes (TimeOfDay 9 0 0) (TimeOfDay 9 0 0) `shouldBe` 0

    describe "Timesheet edit window" do
        it "isWithinEditWindow allows edits within the window" do
            let today = fromGregorian 2025 6 15
            isWithinEditWindow today (fromGregorian 2025 6 15) 7 `shouldBe` True
            isWithinEditWindow today (fromGregorian 2025 6 8) 7 `shouldBe` True
            isWithinEditWindow today (fromGregorian 2025 6 14) 7 `shouldBe` True

        it "isWithinEditWindow blocks edits outside the window" do
            let today = fromGregorian 2025 6 15
            isWithinEditWindow today (fromGregorian 2025 6 7) 7 `shouldBe` False
            isWithinEditWindow today (fromGregorian 2025 5 1) 7 `shouldBe` False

        it "isWithinEditWindow handles zero-day window (today only)" do
            let today = fromGregorian 2025 6 15
            isWithinEditWindow today (fromGregorian 2025 6 15) 0 `shouldBe` True
            isWithinEditWindow today (fromGregorian 2025 6 14) 0 `shouldBe` False

    describe "Timesheet approval" do
        it "resetApprovalOnEdit clears approval when wasApproved is True" do
            let entry = newRecord @TimesheetEntry
                    |> set #isApproved True
                result = resetApprovalOnEdit True entry
            result.isApproved `shouldBe` False
            result.approvedAt `shouldBe` Nothing
            result.approvedByUserId `shouldBe` Nothing

        it "resetApprovalOnEdit preserves state when wasApproved is False" do
            let entry = newRecord @TimesheetEntry
                result = resetApprovalOnEdit False entry
            result.isApproved `shouldBe` False
            result.approvedAt `shouldBe` Nothing
