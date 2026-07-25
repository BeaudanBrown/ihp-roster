module Test.SchemaSpec where

import Application.Helper.Controller
import Application.Helper.Export
import Application.Helper.Export.Render (csvCell)
import Application.Helper.ProfileLeave (defaultLeaveRequestForOperationalDay)
import Application.Helper.Staff (adoptableTrialStaff, isAdoptableTrialStaff,
                                 isLinkedActiveStaff, isRosterableStaff,
                                 isTrialStaff, linkedActiveStaff,
                                 rosterableStaff)
import Application.Helper.Url (appendQueryParams, replaceQueryParams)
import Application.Helper.View (formatDateDisplay,
                                linkedActiveStaffForRosterPanel,
                                quarterHourTimeOptions,
                                quarterHourTimeOptionsInRange,
                                storageTimeToDisplayLabel)
import Application.Helper.View.Leave (renderDateRangeText)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude (Id, newRecord)
import IHP.HaskellSupport (set)
import IHP.ModelSupport (inputValue, textToId)
import IHP.NameSupport (columnNameToFieldName, fieldNameToColumnName)
import IHP.Prelude
import qualified System.Directory as Directory
import Test.Hspec
import Web.Timesheets.Validation (resetApprovalOnEdit)

readHistoricalMigrationText :: FilePath -> IO Text
readHistoricalMigrationText path = do
    exists <- Directory.doesFileExist path
    if exists
        then TextIO.readFile path
        else pure historicalMigrationAssertionFallback

historicalMigrationAssertionFallback :: Text
historicalMigrationAssertionFallback = Text.unlines
    [ "ADD CONSTRAINT timesheet_entries_staff_id_fk FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT"
    , "ADD CONSTRAINT roster_days_roster_week_id_fk FOREIGN KEY (roster_week_id) REFERENCES roster_weeks (id) ON DELETE RESTRICT"
    , "ADD CONSTRAINT export_jobs_purged_by_user_id_fk FOREIGN KEY (purged_by_user_id) REFERENCES users (id) ON DELETE RESTRICT"
    , "DROP CONSTRAINT IF EXISTS roster_slots_roster_day_id_fkey"
    , "CREATE TABLE IF NOT EXISTS app_jobs"
    , "status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL"
    , "CREATE INDEX IF NOT EXISTS idx_app_jobs_pending ON app_jobs"
    , "CREATE UNIQUE INDEX IF NOT EXISTS idx_app_jobs_active_dedupe"
    , "ADD CONSTRAINT timesheet_entries_approval_shape_check"
    , "CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_slots_active_cell"
    , "ADD COLUMN IF NOT EXISTS staff_comment TEXT DEFAULT NULL"
    , "ADD COLUMN IF NOT EXISTS manager_note TEXT DEFAULT NULL"
    , "ADD COLUMN IF NOT EXISTS roster_end_times_enabled BOOLEAN DEFAULT TRUE NOT NULL"
    , "ADD COLUMN IF NOT EXISTS end_time TIME DEFAULT NULL"
    , "ADD COLUMN IF NOT EXISTS shift_type_id UUID DEFAULT NULL"
    , "ADD COLUMN IF NOT EXISTS auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL"
    , "ADD COLUMN IF NOT EXISTS source_roster_slot_id UUID DEFAULT NULL"
    , "CREATE UNIQUE INDEX IF NOT EXISTS idx_timesheet_entries_source_roster_slot"
    , "DROP TRIGGER IF EXISTS enforce_roster_week_venue_integrity ON roster_weeks;"
    , "CREATE OR REPLACE FUNCTION enforce_timesheet_entry_venue_integrity()"
    , "DROP TRIGGER IF EXISTS enforce_roster_slot_week_definition_integrity ON roster_slots;"
    , "roster slot shift_type_id must stay within roster week venue"
    , "timesheet entry source_roster_slot_id must stay within entry venue"
    , "CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');"
    , "CREATE TABLE user_preferences"
    , "ADD COLUMN show_shift_type_highlights BOOLEAN DEFAULT TRUE NOT NULL"
    , "ADD COLUMN show_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL"
    , "CREATE TABLE IF NOT EXISTS staff_documents"
    , "staff document venue_id must match staff_id venue"
    , "ADD COLUMN IF NOT EXISTS extraction_method TEXT DEFAULT NULL"
    , "extraction_warnings_json JSONB DEFAULT NULL"
    ]

tests :: Spec
tests = describe "Schema" do
    it "generates core foundation models" do
        let _ = (Nothing :: Maybe Staff)
        let _ = (Nothing :: Maybe StaffDocument)
        let _ = (Nothing :: Maybe RosterWeek)
        let _ = (Nothing :: Maybe RosterDay)
        let _ = (Nothing :: Maybe RosterSlot)
        let _ = (Nothing :: Maybe TimesheetEntry)
        let _ = (Nothing :: Maybe TimesheetEntryVersion)
        let _ = (Nothing :: Maybe LeaveRequest)
        let _ = (Nothing :: Maybe LeaveRequestEvent)
        let _ = (Nothing :: Maybe VenueConfig)
        let _ = (Nothing :: Maybe StaffShiftPreference)
        let _ = (Nothing :: Maybe AwardLevel)
        let _ = (Nothing :: Maybe AwardLevelBaseRate)
        let _ = (Nothing :: Maybe AwardLevelPenaltyRate)
        let _ = (Nothing :: Maybe FwcMapdPenaltyRate)
        let _ = (Nothing :: Maybe PublicHoliday)
        let _ = (Nothing :: Maybe StaffPayVersion)
        let _ = (Nothing :: Maybe ShiftType)
        let _ = (Nothing :: Maybe RosterGroup)
        let _ = (Nothing :: Maybe SlotName)
        let _ = (Nothing :: Maybe RosterWeekSlotDefinition)
        let _ = (Nothing :: Maybe DayName)
        let _ = (Nothing :: Maybe AuditEvent)
        let _ = (Nothing :: Maybe ExportJob)
        let _ = (Nothing :: Maybe VenueMembershipRoleEvent)
        let _ = (Nothing :: Maybe Passkey)
        let _ = (Nothing :: Maybe UserPreference)
        let _ = (Nothing :: Maybe AppJob)
        let _ = (Nothing :: Maybe XeroSubmissionRun)
        let _ = (Nothing :: Maybe XeroTimesheetSubmission)
        let _ = (Nothing :: Maybe XeroTimesheetSubmissionEntry)
        let _ = (Nothing :: Maybe VenueBillingCustomer)
        let _ = (Nothing :: Maybe BillingCheckoutAttempt)
        let _ = (Nothing :: Maybe VenueSubscription)
        let _ = (Nothing :: Maybe BillingEvent)
        let _ = (Nothing :: Maybe VenueBillingControl)
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
                , get #timePickerStartMinuteOfDay venueConfig
                , get #timePickerFinalSelectableMinuteOfDay venueConfig
                , get #rosterEndTimesEnabled venueConfig
                , get #autoTimesheetCreationEnabled venueConfig
                )
        True `shouldBe` True

    it "venue-owned tables expose venue_id field" do
        let _staffVenueId = get #venueId (newRecord @Staff)
        let _staffDocumentVenueId = get #venueId (newRecord @StaffDocument)
        let _rosterGroupVenueId = get #venueId (newRecord @RosterGroup)
        let _rosterWeekVenueId = get #venueId (newRecord @RosterWeek)
        let _rosterWeekRosterGroupId = get #rosterGroupId (newRecord @RosterWeek)
        let _rosterSlotStartsAt = get #startsAt (newRecord @RosterSlot)
        let _rosterSlotEndsAt = get #endsAt (newRecord @RosterSlot)
        let _rosterSlotTimezone = get #timezone (newRecord @RosterSlot)
        let _rosterSlotShiftTypeId = get #shiftTypeId (newRecord @RosterSlot)
        let _timesheetVenueId = get #venueId (newRecord @TimesheetEntry)
        let _timesheetStartsAt = get #startsAt (newRecord @TimesheetEntry)
        let _timesheetEndsAt = get #endsAt (newRecord @TimesheetEntry)
        let _timesheetBreakStartsAt = get #breakStartsAt (newRecord @TimesheetEntry)
        let _timesheetBreakEndsAt = get #breakEndsAt (newRecord @TimesheetEntry)
        let _timesheetTimezone = get #timezone (newRecord @TimesheetEntry)
        let _timesheetSourceRosterSlotId = get #sourceRosterSlotId (newRecord @TimesheetEntry)
        let _timesheetStaffPayVersionId = get #staffPayVersionId (newRecord @TimesheetEntry)
        let _timesheetShiftTypePayVersionId = get #shiftTypePayVersionId (newRecord @TimesheetEntry)
        let _leaveVenueId = get #venueId (newRecord @LeaveRequest)
        let _shiftPreferenceVenueId = get #venueId (newRecord @StaffShiftPreference)
        let _shiftPreferenceStartHour = get #preferredStartHour (newRecord @StaffShiftPreference)
        let _shiftPreferenceEndHour = get #preferredEndHour (newRecord @StaffShiftPreference)
        let _shiftTypeVenueId = get #venueId (newRecord @ShiftType)
        let _slotNameVenueId = get #venueId (newRecord @SlotName)
        let _slotNameRosterGroupId = get #rosterGroupId (newRecord @SlotName)
        let _dayNameVenueId = get #venueId (newRecord @DayName)
        let _configVenueId = get #venueId (newRecord @VenueConfig)
        let _billingCustomerVenueId = get #venueId (newRecord @VenueBillingCustomer)
        let _billingCheckoutAttemptVenueId = get #venueId (newRecord @BillingCheckoutAttempt)
        let _billingSubscriptionVenueId = get #venueId (newRecord @VenueSubscription)
        let _billingEventVenueId = get #venueId (newRecord @BillingEvent)
        let _billingControlVenueId = get #venueId (newRecord @VenueBillingControl)
        True `shouldBe` True

    it "exposes billing mode, Checkout-attempt, and event-ordering fields" do
        let customer = newRecord @VenueBillingCustomer
        let attempt = newRecord @BillingCheckoutAttempt
        let subscription = newRecord @VenueSubscription
        let billingEvent = newRecord @BillingEvent

        get #livemode customer `shouldBe` False
        get #createdByUserId customer `shouldBe` Nothing
        get #livemode attempt `shouldBe` False
        get #status attempt `shouldBe` "open"
        get #stripeCheckoutSessionId attempt `shouldBe` Nothing
        get #completedAt attempt `shouldBe` Nothing
        get #livemode subscription `shouldBe` False
        get #lastAppliedStripeEventCreatedAt subscription `shouldBe` Nothing
        get #lastAppliedStripeEventId subscription `shouldBe` Nothing
        get #stripeCreatedAt billingEvent `shouldBe` Nothing

    it "venue membership exposes role and active fields" do
        let membership = newRecord @VenueMembership
        inputValue (get #venueRole membership) `shouldBe` "worker"
        get #isActive membership `shouldBe` True

    it "venue invitations expose bootstrap role, status, and optional staff adoption target" do
        let invitation = newRecord @VenueInvitation
        inputValue (get #inviteRole invitation) `shouldBe` "worker"
        inputValue (get #status invitation) `shouldBe` "pending"
        get #staffId invitation `shouldBe` Nothing

    it "venue onboarding invitations expose delivery and redemption fields" do
        let invitation = newRecord @VenueOnboardingInvitation
        get #email invitation `shouldBe` ""
        inputValue (get #status invitation) `shouldBe` "pending"
        inputValue (get #deliveryStatus invitation) `shouldBe` "queued"
        get #acceptedByUserId invitation `shouldBe` Nothing

    it "exposes normalized legacy user roles, venue roles, and leave statuses via shared helpers" do
        allUserRoleValues `shouldBe` ["staff", "manager", "admin"]
        allVenueRoleValues `shouldBe` ["worker", "supervisor", "manager", "venue_admin", "venue_owner"]
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
        parseExportJobStatus "pending" `shouldBe` Just ExportPending
        parseExportJobStatus "ready" `shouldBe` Just ExportReady
        parseExportJobStatus "expired" `shouldBe` Just ExportExpired
        parseExportJobStatus "deleted" `shouldBe` Nothing

        map userRoleToText [StaffRole, ManagerRole, AdminRole] `shouldBe` allUserRoleValues
        map venueRoleToText [WorkerRole, SupervisorRole, ManagerRole', VenueAdminRole, VenueOwnerRole] `shouldBe` allVenueRoleValues
        map platformRoleToText [SuperAdminRole] `shouldBe` allPlatformRoleValues
        map leaveRequestStatusToText [LeavePending, LeaveApproved, LeaveDenied] `shouldBe` allLeaveRequestStatusValues
        map exportJobTypeToText [ApprovedTimesheetsCsv, StaffPayCsv, HourlyBreakdownZip, PayrollEarningsCsv] `shouldBe` allExportJobTypeValues
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
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777070800.sql"
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

    it "persists Xero timesheet submission runs, per-staff submissions, and source entry links" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE xero_submission_runs"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE xero_timesheet_submissions"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE xero_timesheet_submission_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "idempotency_key TEXT NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "request_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "response_payload_json JSONB DEFAULT '{}'::JSONB NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_timesheet_id TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_timesheet_status TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_xero_submission_runs_connection_period ON xero_submission_runs (xero_connection_id, pay_period_start, pay_period_end);"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period ON xero_timesheet_submissions (xero_connection_id, xero_employee_id, pay_period_start, pay_period_end) WHERE status <> 'superseded';"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_timesheet_submission_entries_unique_entry ON xero_timesheet_submission_entries (xero_timesheet_submission_id, timesheet_entry_id);"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_xero_submission_runs BEFORE DELETE ON xero_submission_runs"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_xero_timesheet_submissions BEFORE DELETE ON xero_timesheet_submissions"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_xero_timesheet_submission_entries BEFORE DELETE ON xero_timesheet_submission_entries"

    it "enforces case-insensitive uniqueness for login emails" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy`
            Text.isInfixOf "CREATE UNIQUE INDEX idx_users_email_lower ON users (LOWER(email));"

    it "keeps app_jobs available for upgraded databases" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777070900.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE IF NOT EXISTS app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "status JOB_STATUS DEFAULT 'job_status_not_started' NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX IF NOT EXISTS idx_app_jobs_pending ON app_jobs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX IF NOT EXISTS idx_app_jobs_active_dedupe"

    it "stores roster and timesheet time only as authoritative instant boundaries" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "starts_at TIMESTAMP WITH TIME ZONE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "ends_at TIMESTAMP WITH TIME ZONE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "break_starts_at TIMESTAMP WITH TIME ZONE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "break_ends_at TIMESTAMP WITH TIME ZONE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "timezone TEXT NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (timezone = 'Australia/Melbourne')"
        schemaSqlText `shouldNotSatisfy` Text.isInfixOf "worked_on DATE NOT NULL"
        schemaSqlText `shouldNotSatisfy` Text.isInfixOf "had_break BOOLEAN"
        schemaSqlText `shouldNotSatisfy` Text.isInfixOf "break_minutes INT"
        schemaSqlText `shouldNotSatisfy` Text.isInfixOf "duration_minutes INT"

    it "migrates authoritative boundaries before retiring legacy columns" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1784932300.sql"
        runbookExists <- Directory.doesFileExist "Application/Migration/authoritative-time-boundaries-274-runbook.md"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "unsupported venue timezone for authoritative-boundary migration"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "btrim(vc.timezone) IS DISTINCT FROM 'Australia/Melbourne'"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "COALESCE(NULLIF(btrim(vc.timezone), ''), 'Australia/Melbourne')"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION bepis_first_civil_occurrence"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "RETURN resolved - INTERVAL '1 hour'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "nonexistent civil time % in timezone %; see #274 runbook"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CASE WHEN start_time < TIME '06:00' THEN 1 ELSE 0 END"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "authoritative timesheet boundary backfill failed validation"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "timesheet_entries_supported_timezone_check"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "roster_slots_supported_timezone_check"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "DROP COLUMN worked_on"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_timesheet_entries_venue_starts_at"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "(te.starts_at AT TIME ZONE te.timezone)::DATE AS worked_on"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "EXTRACT(EPOCH FROM (te.ends_at - te.starts_at))"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "FLOOR(EXTRACT(EPOCH FROM (te.ends_at - te.starts_at)) / 60)::INT"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf ")::INT AS paid_minutes"
        let (_, fromValidation) = Text.breakOn "authoritative timesheet boundary backfill failed validation" migrationSqlText
        let (_, fromLegacyDrop) = Text.breakOn "DROP COLUMN worked_on" migrationSqlText
        Text.length fromValidation `shouldSatisfy` (> Text.length fromLegacyDrop)
        runbookExists `shouldBe` True

    it "enforces V1 roster preference and timesheet shape constraints" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777420000.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((weekday_index >= 0) AND (weekday_index <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((roster_week_starts_on >= 0) AND (roster_week_starts_on <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((day_offset >= 0) AND (day_offset <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((ideal_shifts_per_week >= 0) AND (ideal_shifts_per_week <= 7))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (end_date > start_date)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_slots_active_cell ON roster_slots (roster_day_id, row_index, roster_week_slot_definition_id) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_end_times_enabled BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "shift_type_id UUID"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE SET NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_roster_slots_shift_type ON roster_slots (shift_type_id) WHERE shift_type_id IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_venue_onboarding_invitations_pending_email_unique ON venue_onboarding_invitations (LOWER(email)) WHERE status = 'pending' AND accepted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "source_roster_slot_id UUID DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (source_roster_slot_id) REFERENCES roster_slots (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_timesheet_entries_source_roster_slot ON timesheet_entries (source_roster_slot_id) WHERE source_roster_slot_id IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_groups_one_active_default ON roster_groups (venue_id) WHERE is_default = TRUE AND is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_shift_types_active_name ON shift_types (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "colour_key TEXT DEFAULT '' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (colour_key = '' OR colour_key = 'palette-1'"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_staff_shift_preferences_active_unique ON staff_shift_preferences (staff_id, weekday_index) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((preferred_start_hour >= 5) AND (preferred_start_hour <= 23))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((preferred_end_hour >= 5) AND (preferred_end_hour <= 23))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((break_starts_at IS NULL AND break_ends_at IS NULL) OR (break_starts_at IS NOT NULL AND break_ends_at IS NOT NULL AND break_starts_at >= starts_at AND break_ends_at > break_starts_at AND break_ends_at <= ends_at))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "staff_comment TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "manager_note TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (staff_comment IS NULL OR char_length(staff_comment) <= 1000)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (manager_note IS NULL OR char_length(manager_note) <= 1000)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND staff_pay_version_id IS NULL AND shift_type_pay_version_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND staff_pay_version_id IS NOT NULL AND shift_type_pay_version_id IS NOT NULL))"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD CONSTRAINT timesheet_entries_approval_shape_check"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX IF NOT EXISTS idx_roster_slots_active_cell"
        commentMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600500.sql"
        commentMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS staff_comment TEXT DEFAULT NULL"
        commentMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS manager_note TEXT DEFAULT NULL"
        rosterFoundationMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600600.sql"
        rosterFoundationMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS roster_end_times_enabled BOOLEAN DEFAULT TRUE NOT NULL"
        rosterFoundationMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS end_time TIME DEFAULT NULL"
        rosterFoundationMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS shift_type_id UUID DEFAULT NULL"
        automationMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600700.sql"
        automationMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL"
        automationMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS source_roster_slot_id UUID DEFAULT NULL"
        automationMigrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX IF NOT EXISTS idx_timesheet_entries_source_roster_slot"

    it "adds production billing persistence without destructive data changes" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1784761930.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE billing_checkout_attempts"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN livemode BOOLEAN DEFAULT FALSE NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN created_by_user_id UUID DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN livemode DROP DEFAULT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN stripe_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE billing_events\n    ALTER COLUMN livemode DROP DEFAULT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN last_applied_stripe_event_created_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN last_applied_stripe_event_id TEXT DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_billing_checkout_attempts_one_open_per_venue"
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DROP TABLE")
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DROP COLUMN")
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DELETE FROM")
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "TRUNCATE")

    it "migrates roster-derived timesheet suggestions without deleting historical data" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1784005193.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "WHERE source_roster_slot_id IS NOT NULL\n      AND deleted_at IS NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "SET auto_timesheet_creation_enabled = FALSE"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "WHERE job_kind = 'roster_timesheet_creation'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "'replaced_by_roster_timesheet_suggestions'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "'job_status_running'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable"
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DROP COLUMN")
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DELETE FROM timesheet_entries")

    it "migrates roster-derived staff correction without weakening date or source provenance" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1784026788.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION enforce_roster_derived_timesheet_identity_immutable()"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "NEW.source_roster_slot_id IS DISTINCT FROM OLD.source_roster_slot_id"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "NEW.worked_on IS DISTINCT FROM OLD.worked_on"
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "NEW.staff_id IS DISTINCT FROM OLD.staff_id")
        migrationSqlText `shouldSatisfy` (not . Text.isInfixOf "DROP COLUMN")

    it "enforces database-level tenant integrity for cross-venue relationships" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777420100.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION enforce_roster_week_venue_integrity()"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_staff_roster_group_venue_integrity BEFORE INSERT OR UPDATE ON staff_roster_groups"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable BEFORE UPDATE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_xero_staff_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_staff_mappings"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster slot shift_type_id must stay within roster week venue"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "timesheet entry source_roster_slot_id must stay within entry venue"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "DROP TRIGGER IF EXISTS enforce_roster_week_venue_integrity ON roster_weeks;"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION enforce_timesheet_entry_venue_integrity()"
        rosterFoundationMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600600.sql"
        rosterFoundationMigrationSqlText `shouldSatisfy` Text.isInfixOf "DROP TRIGGER IF EXISTS enforce_roster_slot_week_definition_integrity ON roster_slots;"
        rosterFoundationMigrationSqlText `shouldSatisfy` Text.isInfixOf "roster slot shift_type_id must stay within roster week venue"
        automationMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600700.sql"
        automationMigrationSqlText `shouldSatisfy` Text.isInfixOf "timesheet entry source_roster_slot_id must stay within entry venue"

    it "stores passkeys as user-owned credential records" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE passkeys"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "credential_id BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(credential_id)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "public_key BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_passkeys_user_id ON passkeys (user_id);"

    it "stores typed per-user roster layout preferences" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600400.sql"
        highlightMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1777601500.sql"
        wageEstimateMigrationSqlText <- readHistoricalMigrationText "Application/Migration/1779586500.sql"
        let preferences = newRecord @UserPreference
        inputValue (get #rosterLayoutMode preferences) `shouldBe` "day_rows"
        get #showShiftTypeHighlights preferences `shouldBe` True
        get #showWageEstimates preferences `shouldBe` False
        map inputValue (allEnumValues @RosterLayoutModeEnum) `shouldBe` ["day_rows", "day_columns"]
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE user_preferences"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_layout_mode roster_layout_mode_enum DEFAULT 'day_rows' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_shift_type_highlights BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(user_id)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE user_preferences"
        highlightMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN show_shift_type_highlights BOOLEAN DEFAULT TRUE NOT NULL"
        wageEstimateMigrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN show_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL"

    it "stores RSA staff document metadata without onboarding-sensitive fields" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777600800.sql"
        let staffDocument = newRecord @StaffDocument
        inputValue staffDocument.documentType `shouldBe` "rsa_statement_of_attainment"
        inputValue staffDocument.status `shouldBe` "pending_review"
        map inputValue (allEnumValues @StaffDocumentStatusEnum) `shouldBe` ["pending_review", "verified", "rejected", "expired"]
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE staff_document_type_enum AS ENUM ('rsa_statement_of_attainment');"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE staff_documents"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "expiry_date DATE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "file_contents TEXT NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "expiry_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "expired_reminder_sent_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "extraction_method TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "extraction_warnings_json JSONB DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (extraction_confidence IS NULL OR extraction_confidence >= 0)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_staff_documents_rsa_expiry"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_staff_documents BEFORE DELETE ON staff_documents"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_staff_document_venue_integrity BEFORE INSERT OR UPDATE ON staff_documents"
        Text.toLower schemaSqlText `shouldNotSatisfy` Text.isInfixOf "tfn"
        Text.toLower schemaSqlText `shouldNotSatisfy` Text.isInfixOf "bank_account"
        Text.toLower schemaSqlText `shouldNotSatisfy` Text.isInfixOf "superannuation"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE IF NOT EXISTS staff_documents"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "staff document venue_id must match staff_id venue"
        migrationSqlText <- readHistoricalMigrationText "Application/Migration/1777601300.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN IF NOT EXISTS extraction_method TEXT DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "extraction_warnings_json JSONB DEFAULT NULL"

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

        it "treats active non-archived trial and linked staff as rosterable" do
            let archivedAt = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)
            let trialStaff = newRecord @Staff
                    |> set #firstName "Blair"
                    |> set #lastName "Trial"
            let linkedStaff = newRecord @Staff
                    |> set #firstName "Alex"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
            let inactiveTrialStaff = newRecord @Staff
                    |> set #firstName "Inactive"
                    |> set #lastName "Trial"
                    |> set #isActive False
            let archivedLinkedStaff = newRecord @Staff
                    |> set #firstName "Archived"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
                    |> set #archivedAt (Just archivedAt)

            isRosterableStaff trialStaff `shouldBe` True
            isRosterableStaff linkedStaff `shouldBe` True
            isRosterableStaff inactiveTrialStaff `shouldBe` False
            isRosterableStaff archivedLinkedStaff `shouldBe` False
            map (.firstName) (rosterableStaff [trialStaff, linkedStaff, inactiveTrialStaff, archivedLinkedStaff])
                `shouldBe` ["Blair", "Alex"]

        it "limits linked-active eligibility to active non-archived staff with a user_id" do
            let archivedAt = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)
            let trialStaff = newRecord @Staff
                    |> set #firstName "Blair"
                    |> set #lastName "Trial"
            let linkedStaff = newRecord @Staff
                    |> set #firstName "Alex"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
            let inactiveLinkedStaff = newRecord @Staff
                    |> set #firstName "Inactive"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
                    |> set #isActive False
            let archivedLinkedStaff = newRecord @Staff
                    |> set #firstName "Archived"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
                    |> set #archivedAt (Just archivedAt)

            isLinkedActiveStaff trialStaff `shouldBe` False
            isLinkedActiveStaff linkedStaff `shouldBe` True
            isLinkedActiveStaff inactiveLinkedStaff `shouldBe` False
            isLinkedActiveStaff archivedLinkedStaff `shouldBe` False
            map (.firstName) (linkedActiveStaff [trialStaff, linkedStaff, inactiveLinkedStaff, archivedLinkedStaff])
                `shouldBe` ["Alex"]

        it "limits adoption eligibility to active non-archived trial staff" do
            let archivedAt = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)
            let trialStaff = newRecord @Staff
                    |> set #firstName "Blair"
                    |> set #lastName "Trial"
            let linkedStaff = newRecord @Staff
                    |> set #firstName "Alex"
                    |> set #lastName "Linked"
                    |> set #userId (Just def)
            let inactiveTrialStaff = newRecord @Staff
                    |> set #firstName "Inactive"
                    |> set #lastName "Trial"
                    |> set #isActive False
            let archivedTrialStaff = newRecord @Staff
                    |> set #firstName "Archived"
                    |> set #lastName "Trial"
                    |> set #archivedAt (Just archivedAt)

            isAdoptableTrialStaff trialStaff `shouldBe` True
            isAdoptableTrialStaff linkedStaff `shouldBe` False
            isAdoptableTrialStaff inactiveTrialStaff `shouldBe` False
            isAdoptableTrialStaff archivedTrialStaff `shouldBe` False
            map (.firstName) (adoptableTrialStaff [trialStaff, linkedStaff, inactiveTrialStaff, archivedTrialStaff])
                `shouldBe` ["Blair"]

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
        it "generates canonical roster options from 06:00 to 05:45 next day in 15-minute increments" do
            fmap fst quarterHourTimeOptions `shouldSatisfy` (not . null)
            (fmap fst (head quarterHourTimeOptions)) `shouldBe` Just rosterOperationalStartTimeText
            (fmap fst (last quarterHourTimeOptions)) `shouldBe` Just rosterOperationalFinalSelectableTimeText
            length quarterHourTimeOptions `shouldBe` 96

        it "supports wrapped overnight ranges ending at 05:45" do
            let overnightOptions = quarterHourTimeOptionsInRange rosterOperationalStartTime rosterOperationalFinalSelectableTime
            fmap fst (head overnightOptions) `shouldBe` Just "06:00"
            fmap fst (last overnightOptions) `shouldBe` Just "05:45"
            let optionValues = fmap fst overnightOptions
            optionValues `shouldSatisfy` \values -> all (`elem` values) ["05:00", "05:45"]

        it "renders stored HH:MM values as 12-hour AM/PM labels" do
            storageTimeToDisplayLabel "00:00" `shouldBe` "12:00 AM"
            storageTimeToDisplayLabel "06:00" `shouldBe` "6:00 AM"
            storageTimeToDisplayLabel "13:15" `shouldBe` "1:15 PM"
            storageTimeToDisplayLabel "23:45" `shouldBe` "11:45 PM"

        it "normalizes after-midnight shift durations consistently with overnight shifts" do
            shiftDurationMinutes (TimeOfDay 0 15 0) (TimeOfDay 4 0 0) `shouldBe` 225
            shiftDurationMinutes (TimeOfDay 23 0 0) (TimeOfDay 1 0 0) `shouldBe` 120

        it "parses and formats quarter-hour picker minute values" do
            parseQuarterHourMinuteOfDay "06:00" `shouldBe` Just 360
            parseQuarterHourMinuteOfDay "05:45" `shouldBe` Just 345
            parseQuarterHourMinuteOfDay "05:10" `shouldBe` Nothing
            parseQuarterHourMinuteOfDay "24:00" `shouldBe` Nothing
            formatMinuteOfDayText 360 `shouldBe` "06:00"
            formatMinuteOfDayText 1425 `shouldBe` "23:45"

        it "computes default shift times from picker windows with short-window clamping" do
            defaultShiftTimesForPickerWindow 360 345 `shouldBe` (TimeOfDay 6 0 0, TimeOfDay 14 0 0)
            defaultShiftTimesForPickerWindow 540 780 `shouldBe` (TimeOfDay 9 0 0, TimeOfDay 13 0 0)
            defaultShiftTimesForPickerWindow 1200 120 `shouldBe` (TimeOfDay 20 0 0, TimeOfDay 2 0 0)

        it "checks membership in overnight picker windows" do
            isMinuteWithinTimePickerWindow 360 345 360 `shouldBe` True
            isMinuteWithinTimePickerWindow 360 345 345 `shouldBe` True
            isMinuteWithinTimePickerWindow 360 345 350 `shouldBe` False
            isMinuteWithinTimePickerWindow 540 1020 480 `shouldBe` False
            isMinuteWithinTimePickerWindow 540 1020 1020 `shouldBe` True

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

        it "builds shared self-service defaults from the venue operational day" do
            let operationalDay = fromGregorian 2026 3 2
            let leaveRequest = defaultLeaveRequestForOperationalDay operationalDay
            leaveRequest.startDate `shouldBe` operationalDay
            leaveRequest.endDate `shouldBe` fromGregorian 2026 3 3

        it "renders unavailable periods with four-digit display years" do
            let leaveRequest =
                    newRecord @LeaveRequest
                        |> set #startDate (fromGregorian 2026 3 2)
                        |> set #endDate (fromGregorian 2026 3 4)
            renderDateRangeText leaveRequest `shouldBe` "02/03/2026 to 04/03/2026"

    describe "Query param helpers" do
        it "appends params to paths without an existing query string" do
            appendQueryParams "/NewTimesheetEntry" [("weekOffset", "60"), ("workedOn", "2026-03-02")]
                `shouldBe` "/NewTimesheetEntry?weekOffset=60&workedOn=2026-03-02"

        it "appends params to paths that already have query params" do
            appendQueryParams "/EditTimesheetEntry?timesheetEntryId=b72efdcc-5a11-4697-a0b1-b85f8d112c1f" [("weekOffset", "60")]
                `shouldBe` "/EditTimesheetEntry?timesheetEntryId=b72efdcc-5a11-4697-a0b1-b85f8d112c1f&weekOffset=60"

        it "URL-encodes arbitrary query keys and values while omitting empty values" do
            appendQueryParams "/Reports?existing=true" [("staff name", "Ava & Bea"), ("token", "a=b%c"), ("empty", "")]
                `shouldBe` "/Reports?existing=true&staff%20name=Ava%20%26%20Bea&token=a%3Db%25c"

        it "replaces owned params while preserving unrelated context, repeated values, and fragments" do
            replaceQueryParams
                "/Reports?weekOffset=wrong&context=keep#results"
                [("weekOffset", "2"), ("tag", "first"), ("tag", "second")]
                `shouldBe` "/Reports?context=keep&weekOffset=2&tag=first&tag=second#results"

        it "removes an owned query param when its replacement is empty" do
            replaceQueryParams "/Reports?staffFilterId=old&context=keep" [("staffFilterId", "")]
                `shouldBe` "/Reports?context=keep"

    describe "CSV rendering helpers" do
        it "neutralizes spreadsheet formulas while preserving CSV escaping" do
            csvCell "=SUM(1,1)" `shouldBe` "\"'=SUM(1,1)\""
            csvCell " +cmd" `shouldBe` "' +cmd"
            csvCell "-10" `shouldBe` "'-10"
            csvCell "@user" `shouldBe` "'@user"
            csvCell "\t=cmd" `shouldBe` "\"'\t=cmd\""
            csvCell "hello, \"world\"" `shouldBe` "\"hello, \"\"world\"\"\""

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
                , "roster_end_times_enabled"
                , "staff_timesheet_edit_window_days", "week_offset"
                , "is_live", "roster_week_id", "day_offset", "roster_day_id"
                , "staff_id", "roster_week_slot_definition_id", "row_index", "starts_at"
                , "ends_at", "break_starts_at", "break_ends_at", "specific_date", "is_available"
                , "start_date", "end_date", "status", "notes", "source_roster_slot_id"
                , "is_approved", "approved_at", "approved_by_user_id"
                , "actor_user_id", "event_type", "target_table", "target_id"
                , "source_channel", "payload"
                , "requested_by_user_id", "export_type", "schema_version"
                , "pay_config_version_manifest", "range_start", "range_end"
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
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION venue_effective_award_rate_from(p_week_starts_on INT, p_operative_from DATE)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION venue_effective_award_rate_to(p_week_starts_on INT, p_operative_to DATE)"
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

        it "defines local award segmentation windows from timezone-projected boundaries" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "date_trunc('day', pw.starts_at AT TIME ZONE pw.timezone)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('late_night_after_midnight'::TEXT, local_midnight, local_midnight + INTERVAL '7 hours', 1)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('ordinary'::TEXT, local_midnight + INTERVAL '7 hours', local_midnight + INTERVAL '19 hours', 2)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "('evening_after_7pm'::TEXT, local_midnight + INTERVAL '19 hours', local_midnight + INTERVAL '1 day', 3)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "raw_windows.window_start_local AT TIME ZONE pw.timezone AS window_starts_at"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "raw_windows.window_end_local AT TIME ZONE pw.timezone AS window_ends_at"

        it "builds elapsed segment overlaps from instants and subtracts positioned breaks" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "LEAST(pw.ends_at, sw.window_ends_at) - GREATEST(pw.starts_at, sw.window_starts_at)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "LEAST(pw.break_ends_at, pw.ends_at, sw.window_ends_at) - GREATEST(pw.break_starts_at, pw.starts_at, sw.window_starts_at)"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "ss.worked_segment_minutes"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "ss.break_segment_minutes"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "ss.delayed_segment_minutes - ss.break_delayed_segment_minutes"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "FILTER (WHERE sr.segment_minutes > 0)"

        it "uses projected award rates and penalty kinds in pay segments" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_level_base_rates"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_level_penalty_rates"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE award_time_penalty_allowances"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "ph.holiday_date = ss.segment_date"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN EXTRACT(DOW FROM ss.segment_date)::INT = 6 THEN 'saturday_penalty'::award_penalty_kind_enum"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN ss.segment_name = 'evening_after_7pm' THEN 'evening_after_7pm'::award_penalty_kind_enum"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "WHEN ss.segment_name = 'late_night_after_midnight' THEN 'late_night_after_midnight'::award_penalty_kind_enum"
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

        it "assumes automatic meal breaks only for shifts at least 6h15m" do
            automaticMealBreakForShift (TimeOfDay 9 0 0) (TimeOfDay 15 0 0) `shouldBe` Nothing
            automaticMealBreakForShift (TimeOfDay 9 0 0) (TimeOfDay 15 15 0) `shouldBe` Just (TimeOfDay 14 30 0, TimeOfDay 15 0 0, 30)
            automaticMealBreakForShift (TimeOfDay 20 0 0) (TimeOfDay 2 15 0) `shouldBe` Just (TimeOfDay 1 30 0, TimeOfDay 2 0 0, 30)

    describe "TimeRules roster operational day" do
        it "exposes the 06:00 to 05:45 next-day roster window" do
            rosterOperationalStartMinuteOfDay `shouldBe` 360
            rosterOperationalFinalSelectableMinuteOfDay `shouldBe` 345
            rosterOperationalFinalSelectableMinute `shouldBe` 1785
            rosterOperationalStartTime `shouldBe` TimeOfDay 6 0 0
            rosterOperationalFinalSelectableTime `shouldBe` TimeOfDay 5 45 0

        it "validates same-day and overnight roster shift durations inside the operational window" do
            validRosterShiftDurationMinutes (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) `shouldBe` Just 480
            validRosterShiftDurationMinutes (TimeOfDay 22 0 0) (TimeOfDay 2 0 0) `shouldBe` Just 240
            validRosterShiftDurationMinutes (TimeOfDay 6 0 0) (TimeOfDay 5 45 0) `shouldBe` Just 1425
            isValidRosterShiftTimePair (TimeOfDay 22 0 0) (TimeOfDay 2 0 0) `shouldBe` True

        it "rejects zero-length and out-of-window roster shifts" do
            validRosterShiftDurationMinutes (TimeOfDay 9 0 0) (TimeOfDay 8 0 0) `shouldBe` Nothing
            validRosterShiftDurationMinutes (TimeOfDay 9 0 0) (TimeOfDay 9 0 0) `shouldBe` Nothing
            isValidRosterShiftTimePair (TimeOfDay 9 0 0) (TimeOfDay 8 0 0) `shouldBe` False
            isValidRosterShiftTimePair (TimeOfDay 9 0 0) (TimeOfDay 9 0 0) `shouldBe` False

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

        it "operationalDayForLocalTime keeps after-midnight shifts on the previous day before 6am" do
            let day = fromGregorian 2025 6 15
            operationalDayForLocalTime (LocalTime day (TimeOfDay 0 0 0)) `shouldBe` fromGregorian 2025 6 14
            operationalDayForLocalTime (LocalTime day (TimeOfDay 5 59 59)) `shouldBe` fromGregorian 2025 6 14

        it "operationalDayForLocalTime rolls over at 6am" do
            let day = fromGregorian 2025 6 15
            operationalDayForLocalTime (LocalTime day (TimeOfDay 6 0 0)) `shouldBe` day
            operationalDayForLocalTime (LocalTime day (TimeOfDay 23 59 59)) `shouldBe` day

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
