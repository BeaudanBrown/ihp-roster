module Test.SchemaSpec where

import Application.Helper.Controller
import Application.Helper.Export
import Application.Helper.Export.Render (csvCell)
import Application.Helper.ProfileLeave (defaultLeaveRequestForOperationalDay)
import Application.Helper.RosterOffsetCompatibility
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
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (addDays, fromGregorian)
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
        let _ = (Nothing :: Maybe RosterNotificationRun)
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
                , get #minutePrecisionShiftTimesEnabled venueConfig
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
        let _timesheetOperationalDate = get #operationalDate (newRecord @TimesheetEntry)
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
        get #notificationSnapshot billingEvent `shouldBe` Aeson.Null

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
        allExportJobTypeValues `shouldBe` ["approved_timesheets_csv", "staff_pay_csv", "hourly_breakdown_zip", "hourly_wage_totals_zip", "payroll_earnings_csv"]
        allExportJobStatusValues `shouldBe` ["pending", "ready", "expired"]

        parseUserRole ("staff" :: Text) `shouldBe` Just StaffRole
        parseUserRole ("manager" :: Text) `shouldBe` Just ManagerRole
        parseUserRole ("admin" :: Text) `shouldBe` Just AdminRole
        parseUserRole ("owner" :: Text) `shouldBe` Nothing

        parseVenueRole ("worker" :: Text) `shouldBe` Just Worker
        parseVenueRole ("manager" :: Text) `shouldBe` Just Manager
        parseVenueRole ("venue_admin" :: Text) `shouldBe` Just VenueAdmin
        parseVenueRole ("venue_owner" :: Text) `shouldBe` Just VenueOwner
        parseVenueRole ("admin" :: Text) `shouldBe` Nothing

        enumFromText @PlatformRoleEnum "super_admin" `shouldBe` Just SuperAdmin
        enumFromText @PlatformRoleEnum "venue_owner" `shouldBe` Nothing

        enumFromText @LeaveRequestStatusEnum "pending" `shouldBe` Just LeaveRequestStatusEnumPending
        enumFromText @LeaveRequestStatusEnum "approved" `shouldBe` Just LeaveRequestStatusEnumApproved
        enumFromText @LeaveRequestStatusEnum "denied" `shouldBe` Just LeaveRequestStatusEnumDenied
        enumFromText @LeaveRequestStatusEnum "cancelled" `shouldBe` Nothing
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
        map venueRoleToText [Worker, Supervisor, Manager, VenueAdmin, VenueOwner] `shouldBe` allVenueRoleValues
        map venueRoleLabel [Worker, Supervisor, Manager, VenueAdmin, VenueOwner]
            `shouldBe` ["Worker", "Supervisor", "Manager", "Venue Admin", "Venue Owner"]
        map venueRoleMailLabel [Worker, Supervisor, Manager, VenueAdmin, VenueOwner]
            `shouldBe` ["worker", "supervisor", "manager", "venue admin", "venue owner"]
        assignableVenueRolesFor False (Just VenueAdmin)
            `shouldBe` [Worker, Supervisor, Manager, VenueAdmin]
        assignableVenueRolesFor False (Just VenueOwner)
            `shouldBe` [Worker, Supervisor, Manager, VenueAdmin, VenueOwner]
        assignableVenueRolesFor True Nothing
            `shouldBe` [Worker, Supervisor, Manager, VenueAdmin, VenueOwner]
        canAssignVenueRole False (Just VenueAdmin) Worker Manager `shouldBe` True
        canAssignVenueRole False (Just VenueAdmin) Worker VenueOwner `shouldBe` False
        canAssignVenueRole False (Just VenueAdmin) VenueOwner VenueAdmin `shouldBe` False
        canAssignVenueRole False (Just VenueOwner) VenueOwner VenueAdmin `shouldBe` True
        canAssignVenueRole True Nothing VenueOwner VenueAdmin `shouldBe` True
        map exportJobTypeToText [ApprovedTimesheetsCsv, StaffPayCsv, HourlyBreakdownZip, HourlyWageTotalsZip, PayrollEarningsCsv] `shouldBe` allExportJobTypeValues
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
        schemaSqlText `shouldSatisfy` Text.isInfixOf "deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "archived_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION prevent_hard_delete()"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_timesheet_entries BEFORE DELETE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_leave_requests BEFORE DELETE ON leave_requests"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_hard_delete_roster_slots BEFORE DELETE ON roster_slots"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (timesheet_entry_id) REFERENCES timesheet_entries (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (leave_request_id) REFERENCES leave_requests (id) ON DELETE RESTRICT"

    it "types app-owned Xero workflow state while retaining provider vocabulary as text" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        let expectedEnumDeclarations =
                [ "CREATE TYPE xero_sync_status_enum AS ENUM ('running', 'succeeded', 'failed');"
                , "CREATE TYPE xero_sync_kind_enum AS ENUM ('payroll_reference_data');"
                , "CREATE TYPE xero_staff_mapping_status_enum AS ENUM ('verified', 'not_applicable', 'stale');"
                , "CREATE TYPE xero_earnings_rate_mapping_status_enum AS ENUM ('unmapped', 'verified', 'stale');"
                , "CREATE TYPE xero_pay_item_account_code_selection_status_enum AS ENUM ('none', 'verified', 'stale');"
                , "CREATE TYPE xero_pay_item_requirement_status_enum AS ENUM ('proposed', 'matched', 'created', 'ignored', 'stale', 'rate_changed');"
                , "CREATE TYPE xero_submission_source_kind_enum AS ENUM ('approved_timesheets');"
                , "CREATE TYPE xero_submission_run_status_enum AS ENUM ('previewed', 'blocked', 'pending', 'submitted', 'partially_failed', 'failed', 'superseded');"
                , "CREATE TYPE xero_timesheet_preparation_run_status_enum AS ENUM ('started', 'preparing', 'needs_reconnect', 'needs_approval', 'blocked', 'resolved', 'ready_for_preview', 'previewed', 'submitted', 'failed', 'cancelled');"
                , "CREATE TYPE xero_timesheet_preparation_decision_kind_enum AS ENUM ('staff_auto_match', 'staff_manual_mapping', 'staff_not_paid', 'staff_step_approved', 'pay_item_create', 'account_code', 'calendar_selection');"
                , "CREATE TYPE xero_timesheet_preparation_decision_status_enum AS ENUM ('pending', 'proposed', 'applied', 'blocked', 'resolved', 'dismissed');"
                , "CREATE TYPE xero_timesheet_submission_status_enum AS ENUM ('blocked', 'pending', 'submitted', 'failed', 'skipped', 'superseded');"
                ]
        forM_ expectedEnumDeclarations \declaration ->
            schemaSqlText `shouldSatisfy` Text.isInfixOf declaration
        let (_, employeeTableAndAfter) = Text.breakOn "CREATE TABLE xero_employees" schemaSqlText
        Text.takeWhileEnd (/= ';') (Text.takeWhile (/= ';') employeeTableAndAfter)
            `shouldSatisfy` Text.isInfixOf "status TEXT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_pay_run_status TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_timesheet_status TEXT DEFAULT NULL"

    it "validates every live Xero workflow value before converting columns to enums" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1786000000.sql"
        runbookSqlText <- TextIO.readFile "Application/Migration/xero-workflow-enums-334-runbook.md"
        runbookExists <- Directory.doesFileExist "Application/Migration/xero-workflow-enums-334-runbook.md"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "unexpected app-owned Xero workflow value"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "('xero_timesheet_preparation_decisions', 'decision_kind'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "check_spec.table_name"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "check_spec.column_name"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN decision_kind TYPE xero_timesheet_preparation_decision_kind_enum"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN status TYPE xero_timesheet_submission_status_enum"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "DROP INDEX idx_xero_staff_mappings_verified_employee"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "DROP INDEX idx_xero_timesheet_submissions_active_remote_period"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "string_agg"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "LIMIT 1"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE xero_sync_runs ALTER COLUMN sync_kind DROP DEFAULT"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE xero_timesheet_submissions ALTER COLUMN status DROP DEFAULT"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE xero_sync_runs ALTER COLUMN sync_kind SET DEFAULT 'payroll_reference_data'"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE xero_timesheet_submissions ALTER COLUMN status SET DEFAULT 'pending'"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "DROP INDEX idx_xero_staff_mappings_verified_employee"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_staff_mappings_verified_employee"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "DROP INDEX idx_xero_timesheet_submissions_active_remote_period"
        runbookSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_xero_timesheet_submissions_active_remote_period"
        runbookExists `shouldBe` True

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

    it "makes pre-deployment pending Xero submissions recoverable without deleting audit history" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1788000100.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "UPDATE xero_timesheet_submissions"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "WHERE status = 'pending'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "UPDATE xero_submission_runs AS run"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "'outcome', 'uncertain'"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP TABLE"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"

    it "enforces case-insensitive uniqueness for login emails" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy`
            Text.isInfixOf "CREATE UNIQUE INDEX idx_users_email_lower ON users (LOWER(email));"

    it "keeps app_jobs in the canonical schema" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE app_jobs"

    it "retains the roster notification deployment migration" do
        migrationSqlText <- TextIO.readFile "Application/Migration/1785813100.sql"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE roster_notification_runs"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "idx_app_jobs_related ON app_jobs (related_table, related_id)"

    it "adds the date-native roster foundation without retiring rollback authority" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1787001000.sql"
        runbookExists <- Directory.doesFileExist "Application/Migration/date-native-roster-foundation-365-runbook.md"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE roster_day_publication_state_enum AS ENUM ('draft', 'published');"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_calendar_revision INT DEFAULT 1 NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER advance_roster_calendar_revision BEFORE UPDATE ON venue_config"
        schemaSqlText `shouldNotSatisfy` Text.isInfixOf "refresh_legacy_roster_config_day_projections"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "operational_date DATE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "publication_state roster_day_publication_state_enum DEFAULT 'draft' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(roster_group_id, operational_date)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE roster_lanes"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_lane_id UUID NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (roster_lane_id) REFERENCES roster_lanes (id) ON DELETE RESTRICT"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "date-native roster preflight blocked"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "date-native roster equivalence check failed"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "week_offset_epoch + (rw.week_offset * 7) + rd.day_offset"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "rs.starts_at AT TIME ZONE rs.timezone"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "legacy_roster_week_slot_definition_id"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ON CONFLICT (roster_week_id, day_offset) DO NOTHING"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "expected_seven_day_projections"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "CROSS JOIN generate_series(0, 6) AS offsets(day_offset)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_legacy_roster_lane_identity_change BEFORE UPDATE ON roster_lanes"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER prevent_legacy_roster_definition_week_change BEFORE UPDATE ON roster_week_slot_definitions"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP TABLE"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"
        runbookExists `shouldBe` True

    it "makes Timesheet Operational dates explicit without moving authoritative instants" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1787005000.sql"
        let (_, timesheetSchema) = Text.breakOn "CREATE TABLE timesheet_entries" schemaSqlText
        Text.take 3000 timesheetSchema `shouldSatisfy` Text.isInfixOf "operational_date DATE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_timesheet_entries_venue_operational_date ON timesheet_entries (venue_id, operational_date) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "rd.operational_date = NEW.operational_date"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "NEW.operational_date IS DISTINCT FROM OLD.operational_date"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN operational_date DATE"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "rd.operational_date"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "(te.starts_at AT TIME ZONE te.timezone)::DATE"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN operational_date SET NOT NULL"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "UPDATE timesheet_entries\nSET starts_at"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "UPDATE timesheet_entries\nSET ends_at"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"

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
        migrationSqlText `shouldSatisfy` Text.isInfixOf "legacy timesheet break duration does not match break clocks"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "te.break_minutes IS DISTINCT FROM"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "EXTRACT(EPOCH FROM (te.break_ends_at - te.break_starts_at)) / 60"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "legacy roster duration does not match roster clocks"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "rs.duration_minutes IS DISTINCT FROM"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "EXTRACT(EPOCH FROM (rs.ends_at - rs.starts_at)) / 60"
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

    it "enforces current roster preference and timesheet shape constraints" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((weekday_index >= 0) AND (weekday_index <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((roster_week_starts_on >= 0) AND (roster_week_starts_on <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((day_offset >= 0) AND (day_offset <= 6))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((ideal_shifts_per_week >= 0) AND (ideal_shifts_per_week <= 7))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (end_date > start_date)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_slots_active_cell ON roster_slots (roster_day_id, row_index, roster_week_slot_definition_id) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_end_times_enabled BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "auto_timesheet_creation_enabled BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "minute_precision_shift_times_enabled BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "shift_type_id UUID"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (shift_type_id) REFERENCES shift_types (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_roster_slots_shift_type ON roster_slots (shift_type_id) WHERE shift_type_id IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_venue_onboarding_invitations_pending_email_unique ON venue_onboarding_invitations (LOWER(email)) WHERE status = 'pending' AND accepted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "source_roster_slot_id UUID DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (source_roster_slot_id) REFERENCES roster_slots (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_timesheet_entries_source_roster_slot ON timesheet_entries (source_roster_slot_id) WHERE source_roster_slot_id IS NOT NULL AND deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_roster_groups_one_active_default ON roster_groups (venue_id) WHERE is_default = TRUE AND is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_shift_types_active_name ON shift_types (venue_id, name) WHERE is_active = TRUE AND archived_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE feedback_type_enum AS ENUM ('bug', 'suggestion', 'other');"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE shift_type_colour_key_enum AS ENUM ('no_colour', 'palette_1'"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "colour_key shift_type_colour_key_enum DEFAULT 'no_colour' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "feedback_type feedback_type_enum DEFAULT 'bug' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE UNIQUE INDEX idx_staff_shift_preferences_active_unique ON staff_shift_preferences (staff_id, weekday_index) WHERE deleted_at IS NULL;"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((preferred_start_hour >= 5) AND (preferred_start_hour <= 23))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((preferred_end_hour >= 5) AND (preferred_end_hour <= 23))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK ((break_starts_at IS NULL AND break_ends_at IS NULL) OR (break_starts_at IS NOT NULL AND break_ends_at IS NOT NULL AND break_starts_at >= starts_at AND break_ends_at > break_starts_at AND break_ends_at <= ends_at))"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "staff_comment TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "manager_note TEXT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (staff_comment IS NULL OR char_length(staff_comment) <= 1000)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (manager_note IS NULL OR char_length(manager_note) <= 1000)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (((is_approved = FALSE) AND approved_at IS NULL AND approved_by_user_id IS NULL AND staff_pay_version_id IS NULL AND shift_type_pay_version_id IS NULL) OR ((is_approved = TRUE) AND approved_at IS NOT NULL AND approved_by_user_id IS NOT NULL AND staff_pay_version_id IS NOT NULL AND shift_type_pay_version_id IS NOT NULL))"

    it "gives roster template days explicit calendar-weekday identity" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1787004000.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "weekday_index INT DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "idx_roster_template_days_design_weekday"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "(venue_config.roster_week_starts_on + roster_template_days.day_index) % 7"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "roster_template_designs.scale = 'week'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "roster template weekday backfill failed"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "window_end DATE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_week_id UUID DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE roster_notification_runs DISABLE TRIGGER enforce_roster_notification_runs_immutable"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE roster_notification_runs ENABLE TRIGGER enforce_roster_notification_runs_immutable"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN roster_week_id DROP NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN week_offset DROP NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "IF NEW.window_end <> NEW.week_start + 7 THEN"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER validate_roster_notification_window BEFORE INSERT OR UPDATE ON roster_notification_runs"

    it "defines explicit roster-shift assignment state in the fresh schema" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        runbookExists <- Directory.doesFileExist "Application/Migration/explicit-roster-shift-assignment-304-runbook.md"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "assignment_state TEXT NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_slots_assignment_state_check CHECK (assignment_state = 'staff' OR assignment_state = 'open')"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_slots_active_structure_check CHECK"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (staff_id) REFERENCES staff (id) ON DELETE RESTRICT"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster slot staff assignment must stay within roster day venue"
        runbookExists `shouldBe` True

    it "adds and safely backfills explicit pay-assignment modes" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1785280000.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE pay_assignment_mode_enum AS ENUM ('award_rate', 'xero_rate', 'roster_only', 'staff_default', 'legacy_unresolved')"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "staff:both_rate_ids"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "staff:cross_venue_xero"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "staff_pay_version:missing_or_cross_venue_staff"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "shift_type_pay_version:missing_or_cross_venue_shift_type"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ORDER BY kind, id LIMIT 50"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "WHEN user_id IS NULL THEN 'roster_only'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ELSE 'legacy_unresolved'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ELSE 'staff_default'"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE staff_pay_versions ALTER COLUMN pay_assignment_mode SET NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "NEW.default_award_level_id IS DISTINCT FROM OLD.default_award_level_id"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "NEW.override_award_level_id IS DISTINCT FROM OLD.override_award_level_id"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP TABLE"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"

    it "adds customer-data-preserving Xero provider availability" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1785376000.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "provider_available BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CHECK (provider_available = (provider_unavailable_at IS NULL))"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER TABLE xero_imported_pay_items"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "FROM xero_earnings_rates rate"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "rate.provider_available = FALSE"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DELETE FROM"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "archived_at ="

    it "stores immutable approved pay facts without persisted rounded totals" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        migrationSqlText <- TextIO.readFile "Application/Migration/1785240000.sql"
        let (_, ledgerAndFollowing) = Text.breakOn "CREATE TABLE timesheet_pay_calculations" schemaSqlText
            (ledgerSchema, _) = Text.breakOn "CREATE TABLE timesheet_entry_versions" ledgerAndFollowing
        ledgerSchema `shouldSatisfy` Text.isInfixOf "CREATE TABLE timesheet_pay_time_segments"
        ledgerSchema `shouldSatisfy` Text.isInfixOf "CREATE TABLE timesheet_pay_earnings_components"
        ledgerSchema `shouldSatisfy` Text.isInfixOf "exact_amount NUMERIC NOT NULL"
        ledgerSchema `shouldNotSatisfy` Text.isInfixOf "total_amount"
        ledgerSchema `shouldNotSatisfy` Text.isInfixOf "rounded_amount"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ADD COLUMN active_pay_calculation_id UUID DEFAULT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "legacy_pay_backfill_pending BOOLEAN DEFAULT TRUE NOT NULL"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "ALTER COLUMN legacy_pay_backfill_pending SET DEFAULT FALSE"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "legacy pay backfill exemption cannot be granted after migration"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "timesheet approval requires a sealed same-entry active pay calculation"
        migrationSqlText `shouldSatisfy` Text.isInfixOf "enforce_timesheet_pay_child_immutability"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP TABLE"
        migrationSqlText `shouldNotSatisfy` Text.isInfixOf "DROP COLUMN"

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
        runbookExists <- Directory.doesFileExist "Application/Migration/roster-timesheet-suggestion-cutover-runbook.md"
        runbookExists `shouldBe` True
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
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE OR REPLACE FUNCTION enforce_roster_week_venue_integrity()"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_roster_week_venue_integrity BEFORE INSERT OR UPDATE ON roster_weeks"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_staff_roster_group_venue_integrity BEFORE INSERT OR UPDATE ON staff_roster_groups"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_timesheet_entry_venue_integrity BEFORE INSERT OR UPDATE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_roster_derived_timesheet_identity_immutable BEFORE UPDATE ON timesheet_entries"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TRIGGER enforce_xero_staff_mappings_venue_integrity BEFORE INSERT OR UPDATE ON xero_staff_mappings"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster slot shift type must stay within roster day venue"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "timesheet entry source roster slot must match entry venue and Operational date"

    it "stores passkeys as user-owned credential records" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE passkeys"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "credential_id BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(credential_id)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "public_key BYTEA NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE INDEX idx_passkeys_user_id ON passkeys (user_id);"

    it "stores typed personal display preferences and venue roster layout" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
        let preferences = newRecord @UserPreference
        inputValue (get #rosterLayoutMode preferences) `shouldBe` "day_rows"
        get #showShiftTypeHighlights preferences `shouldBe` True
        get #showWageEstimates preferences `shouldBe` False
        get #highlightOwnLiveShifts preferences `shouldBe` True
        get #hideApproved preferences `shouldBe` False
        get #showTimesheetSuggestions preferences `shouldBe` True
        get #showTimesheetWageEstimates preferences `shouldBe` True
        get #timesheetPreferencesInitializedAt preferences `shouldBe` Nothing
        map inputValue (allEnumValues @RosterLayoutModeEnum) `shouldBe` ["day_rows", "day_columns"]
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TYPE roster_layout_mode_enum AS ENUM ('day_rows', 'day_columns');"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE user_preferences"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_layout_mode roster_layout_mode_enum DEFAULT 'day_rows' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_layout_mode roster_layout_mode_enum DEFAULT 'day_columns' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "default_staff_pay_assignment_mode pay_assignment_mode_enum DEFAULT 'roster_only' NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "venue_config_default_staff_award_level_id_fk"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_shift_type_highlights BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_wage_estimates BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_timesheet_wage_estimates BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "highlight_own_live_shifts BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "hide_approved BOOLEAN DEFAULT FALSE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "timesheet_preferences_initialized_at TIMESTAMP WITH TIME ZONE DEFAULT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "show_timesheet_suggestions BOOLEAN DEFAULT TRUE NOT NULL"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "UNIQUE(user_id)"
        schemaSqlText `shouldSatisfy` Text.isInfixOf "FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE"

    it "stores RSA staff document metadata without onboarding-sensitive fields" do
        schemaSqlText <- TextIO.readFile "Application/Schema.sql"
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

    describe "Roster offset rollback compatibility" do
        it "round-trips negative and positive retained week offsets for a non-Monday epoch" do
            let tuesdayEpoch = defaultWeekOffsetEpochForStartDay 2
            let venueConfig =
                    newRecord @VenueConfig
                        |> set #rosterWeekStartsOn 2
                        |> applyLegacyWeekOffsetEpoch 2
            tuesdayEpoch `shouldBe` fromGregorian 2025 1 7
            map (venueWeekStartDate venueConfig) [-2, 0, 5]
                `shouldBe` map (\days -> addDays days tuesdayEpoch) [-14, 0, 35]
            map (venueWeekOffsetForDay venueConfig . venueWeekStartDate venueConfig) [-2, 0, 5]
                `shouldBe` [-2, 0, 5]

        it "derives retained week and day values only from explicit Operational dates" do
            let windowStart = fromGregorian 2025 3 10
            let venueConfig =
                    newRecord @VenueConfig
                        |> applyLegacyWeekOffsetEpochDate (fromGregorian 2025 1 6)
            let rosterWeek =
                    newRecord @RosterWeek
                        |> applyLegacyRosterWeekOffset venueConfig windowStart
            let rosterDay =
                    newRecord @RosterDay
                        |> set #operationalDate (addDays 3 windowStart)
                        |> applyLegacyRosterDayOffset windowStart
            rosterWeek.weekOffset `shouldBe` 9
            legacyRosterWeekStartForRecord venueConfig rosterWeek `shouldBe` windowStart
            rosterDay.dayOffset `shouldBe` 3
            rosterDay.operationalDate `shouldBe` fromGregorian 2025 3 13

    describe "Leave request helpers" do
        it "validates leave date ranges as unavailable-from to available-again" do
            let startDate = fromGregorian 2025 3 10
            let sameDay = fromGregorian 2025 3 10
            let laterDate = fromGregorian 2025 3 12
            let earlierDate = fromGregorian 2025 3 9

            isLeaveDateRangeValid startDate sameDay `shouldBe` False
            isLeaveDateRangeValid startDate laterDate `shouldBe` True
            isLeaveDateRangeValid startDate earlierDate `shouldBe` False

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
            Worker `shouldSatisfy` (< Manager)
            Manager `shouldSatisfy` (< VenueAdmin)
            VenueAdmin `shouldSatisfy` (< VenueOwner)

        it "checks minimum venue role correctly" do
            hasVenueRole Worker Worker `shouldBe` True
            hasVenueRole Worker Manager `shouldBe` False
            hasVenueRole Manager Worker `shouldBe` True
            hasVenueRole Manager VenueAdmin `shouldBe` False
            hasVenueRole VenueAdmin Manager `shouldBe` True
            hasVenueRole VenueOwner VenueAdmin `shouldBe` True

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
                        |> set #venueRole (Worker)

            parseUserRole user.userRole `shouldBe` Just AdminRole
            membership.venueRole `shouldBe` Worker
            hasVenueRole membership.venueRole VenueAdmin `shouldBe` False

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
                , "start_date", "end_date", "status", "notes", "source_roster_slot_id", "operational_date"
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

    describe "Haskell wage-engine cutover" do
        it "retires legacy SQL wage calculation functions from the canonical schema" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldNotSatisfy` Text.isInfixOf "calculate_timesheet_pay"
            schemaSqlText `shouldNotSatisfy` Text.isInfixOf "calculate_timesheet_pay_range"

        it "keeps the immutable approved-pay ledger as the final-pay authority" do
            schemaSqlText <- TextIO.readFile "Application/Schema.sql"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE timesheet_pay_calculations"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE timesheet_pay_time_segments"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "CREATE TABLE timesheet_pay_earnings_components"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "operational_date DATE NOT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_window_start DATE NOT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "roster_week_starts_on INT NOT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "component_date DATE DEFAULT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "resolved_rate_boundary_date DATE DEFAULT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_local_bucket_key TEXT DEFAULT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_earnings_rate_id TEXT DEFAULT NULL"
            schemaSqlText `shouldSatisfy` Text.isInfixOf "xero_mapping_legacy_fallback BOOLEAN DEFAULT FALSE NOT NULL"

        it "defers retirement until the automatic post-migration Haskell cutover" do
            markerSqlText <- TextIO.readFile "Application/Migration/1785242000.sql"
            retirementSqlText <- TextIO.readFile "Application/Deployment/retire-legacy-wage-calculators.sql"
            markerSqlText `shouldSatisfy` Text.isInfixOf "wage-cutover.service"
            markerSqlText `shouldNotSatisfy` Text.isInfixOf "DROP FUNCTION"
            retirementSqlText `shouldSatisfy` Text.isInfixOf "calculation.sealed_at IS NULL"
            retirementSqlText `shouldSatisfy` Text.isInfixOf "calculation.approved_at IS DISTINCT FROM te.approved_at"
            retirementSqlText `shouldSatisfy` Text.isInfixOf "FROM timesheet_pay_time_segments segment"
            retirementSqlText `shouldSatisfy` Text.isInfixOf "FROM timesheet_pay_earnings_components component"
            retirementSqlText `shouldSatisfy` Text.isInfixOf "DROP FUNCTION IF EXISTS calculate_timesheet_pay(UUID)"

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

        it "selects one- or fifteen-minute venue entry policy" do
            let defaultConfig = newRecord @VenueConfig
            venueShiftTimeIntervalMinutes defaultConfig `shouldBe` 15
            venueShiftTimeAllows defaultConfig (TimeOfDay 12 17 0) `shouldBe` False
            let minuteConfig = defaultConfig |> set #minutePrecisionShiftTimesEnabled True
            venueShiftTimeIntervalMinutes minuteConfig `shouldBe` 1
            venueShiftTimeAllows minuteConfig (TimeOfDay 12 17 0) `shouldBe` True

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

    describe "date-native Roster production readiness" do
        it "keeps the reconciliation command read-only, bounded, and operator-gated" do
            command <- TextIO.readFile "bin/date-native-roster-readiness"
            migrationCheck <- TextIO.readFile "bin/date-native-roster-migration-check"
            auditSql <- TextIO.readFile "scripts/operations/date-native-roster-readiness-373.sql"

            command `shouldSatisfy` Text.isInfixOf "DATE_NATIVE_ROSTER_READINESS_APPROVAL must equal read-only-issue-373"
            command `shouldSatisfy` Text.isInfixOf "default_transaction_read_only=on"
            command `shouldSatisfy` Text.isInfixOf "output directory must be outside the Git checkout"
            command `shouldSatisfy` Text.isInfixOf "DATABASE_URL is forbidden"
            command `shouldSatisfy` Text.isInfixOf "PGPASSWORD is forbidden"
            command `shouldSatisfy` Text.isInfixOf "PGPASSFILE must have mode 600"
            command `shouldSatisfy` Text.isInfixOf "(.sampleEntityIds | length) <= 25"
            migrationCheck `shouldSatisfy` Text.isInfixOf "regen-types"
            migrationCheck `shouldSatisfy` Text.isInfixOf "date-native roster foundation migration"
            migrationCheck `shouldSatisfy` Text.isInfixOf "Operational payroll sealing migration"
            auditSql `shouldSatisfy` Text.isInfixOf "BEGIN TRANSACTION READ ONLY"
            auditSql `shouldSatisfy` Text.isInfixOf "LIMIT 25"
            auditSql `shouldSatisfy` Text.isInfixOf "totalViolationCount"
            auditSql `shouldSatisfy` (not . Text.isInfixOf "UPDATE ")
            auditSql `shouldSatisfy` (not . Text.isInfixOf "DELETE ")

        it "covers migration identities, Operational ownership, templates, publication, notifications, and approved ledgers" do
            auditSql <- TextIO.readFile "scripts/operations/date-native-roster-readiness-373.sql"
            let requiredChecks =
                    [ "roster_day_cross_scope"
                    , "roster_day_identity_collision"
                    , "roster_slot_operational_day_contradiction"
                    , "roster_lane_day_mismatch"
                    , "roster_slot_legacy_definition_mismatch"
                    , "legacy_lane_definition_mismatch"
                    , "template_weekday_identity"
                    , "template_weekday_duplicate"
                    , "timesheet_source_operational_day_mismatch"
                    , "approved_entry_active_ledger_mismatch"
                    , "current_publication_window_mixed"
                    , "notification_window_invalid"
                    ]
            forEach requiredChecks (\checkName -> auditSql `shouldSatisfy` Text.isInfixOf checkName)

        it "retains a non-destructive rollback and observation approval boundary" do
            runbook <- TextIO.readFile "Application/Migration/date-native-roster-readiness-373-runbook.md"
            runbook `shouldSatisfy` Text.isInfixOf "Do not reverse migrations"
            runbook `shouldSatisfy` Text.isInfixOf "one complete seven-Operational-day window"
            runbook `shouldSatisfy` Text.isInfixOf "#374 remains blocked"
            runbook `shouldSatisfy` Text.isInfixOf "restoring an old backup is a last-resort incident recovery"

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
                    |> set #legacyPayBackfillPending True
                result = resetApprovalOnEdit True entry
            result.isApproved `shouldBe` False
            result.legacyPayBackfillPending `shouldBe` False
            result.approvedAt `shouldBe` Nothing
            result.approvedByUserId `shouldBe` Nothing

        it "resetApprovalOnEdit preserves state when wasApproved is False" do
            let entry = newRecord @TimesheetEntry
                result = resetApprovalOnEdit False entry
            result.isApproved `shouldBe` False
            result.approvedAt `shouldBe` Nothing
