module Application.Script.SeedProfile where

import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Clock (getCurrentTime, utctDay)
import IHP.Prelude
import System.Directory (createDirectoryIfMissing)
import qualified System.Environment as Environment
import System.Exit (exitSuccess)
import System.FilePath ((</>))
import qualified Text.Read as TextRead

run :: IO ()
run = do
    options <- parseOptions
    today <- utctDay <$> getCurrentTime
    let currentWeekOffset = currentWeekOffsetForDay today
    createDirectoryIfMissing True options.outputDir
    let plan = buildProfileSeedPlan options currentWeekOffset
    writeProfileSeed options.outputDir plan
    printSummary options plan

data ProfileSeedOptions = ProfileSeedOptions
    { outputDir       :: !FilePath
    , venueCount      :: !Int
    , staffPerVenue   :: !Int
    , managerPerVenue :: !Int
    , weeksHistory    :: !Int
    , weeksFuture     :: !Int
    , rowsPerDay      :: !Int
    , rosterFill      :: !Int
    , seedValue       :: !Int
    , xeroEmployees   :: !Int
    , xeroMappedStaff :: !Int
    }
    deriving (Eq, Show)

defaultOptions :: ProfileSeedOptions
defaultOptions =
    ProfileSeedOptions
        { outputDir = "build/profile-seed/latest"
        , venueCount = 12
        , staffPerVenue = 40
        , managerPerVenue = 3
        , weeksHistory = 156
        , weeksFuture = 8
        , rowsPerDay = 4
        , rosterFill = 86
        , seedValue = 20260424
        , xeroEmployees = 80
        , xeroMappedStaff = 20
        }

data ProfileSeedPlan = ProfileSeedPlan
    { options           :: !ProfileSeedOptions
    , currentWeekOffset :: !Int
    , counts            :: ![(Text, Int)]
    }
    deriving (Eq, Show)

buildProfileSeedPlan :: ProfileSeedOptions -> Int -> ProfileSeedPlan
buildProfileSeedPlan options currentWeekOffset =
    ProfileSeedPlan
        { options
        , currentWeekOffset
        , counts =
            [ ("venues", venueCount options)
            , ("users", userCount)
            , ("staff", staffCount)
            , ("roster_weeks", rosterWeekCount)
            , ("roster_days", rosterDayCount)
            , ("roster_slots", rosterSlotCount)
            , ("timesheet_entries", timesheetEntryCount)
            , ("leave_requests", leaveRequestCount)
            , ("xero_connections", venueCount options)
            , ("xero_employees", venueCount options * xeroEmployees options)
            , ("xero_staff_mappings", venueCount options * mappedXeroStaffCount options)
            ]
        }
    where
        groupsPerVenue = length rosterGroupTemplates
        slotNamesPerGroup = length slotNameTemplates
        weekCount = weeksHistory options + weeksFuture options
        staffCount = venueCount options * (staffPerVenue options + 1)
        userCount = 1 + venueCount options * (staffPerVenue options + 1)
        rosterWeekCount = venueCount options * groupsPerVenue * weekCount
        rosterDayCount = rosterWeekCount * 7
        rosterSlotCount = rosterDayCount * rowsPerDay options * slotNamesPerGroup
        timesheetEntryCount = venueCount options * staffPerVenue options * min 52 (max 1 (weeksHistory options))
        leaveRequestCount = venueCount options * staffPerVenue options * 3

writeProfileSeed :: FilePath -> ProfileSeedPlan -> IO ()
writeProfileSeed dir plan = do
    writeCsv dir "venues.csv" venueColumns (venueRows plan)
    writeCsv dir "users.csv" userColumns (userRows plan)
    writeCsv dir "venue_config.csv" venueConfigColumns (venueConfigRows plan)
    writeCsv dir "venue_memberships.csv" venueMembershipColumns (venueMembershipRows plan)
    writeCsv dir "staff.csv" staffColumns (staffRows plan)
    writeCsv dir "shift_types.csv" shiftTypeColumns (shiftTypeRows plan)
    writeCsv dir "day_names.csv" dayNameColumns (dayNameRows plan)
    writeCsv dir "pay_config_snapshots.csv" payConfigSnapshotColumns (payConfigSnapshotRows plan)
    writeCsv dir "report_definitions.csv" reportDefinitionColumns (reportDefinitionRows plan)
    writeCsv dir "roster_groups.csv" rosterGroupColumns (rosterGroupRows plan)
    writeCsv dir "slot_names.csv" slotNameColumns (slotNameRows plan)
    writeCsv dir "staff_roster_groups.csv" staffRosterGroupColumns (staffRosterGroupRows plan)
    writeCsv dir "staff_availability.csv" staffAvailabilityColumns (staffAvailabilityRows plan)
    writeCsv dir "staff_shift_preferences.csv" staffShiftPreferenceColumns (staffShiftPreferenceRows plan)
    writeCsv dir "roster_weeks.csv" rosterWeekColumns (rosterWeekRows plan)
    writeCsv dir "roster_days.csv" rosterDayColumns (rosterDayRows plan)
    writeCsv dir "roster_slots.csv" rosterSlotColumns (rosterSlotRows plan)
    writeCsv dir "leave_requests.csv" leaveRequestColumns (leaveRequestRows plan)
    writeCsv dir "timesheet_entries.csv" timesheetEntryColumns (timesheetEntryRows plan)
    writeCsv dir "timesheet_entry_versions.csv" timesheetEntryVersionColumns (timesheetEntryVersionRows plan)
    writeCsv dir "xero_connections.csv" xeroConnectionColumns (xeroConnectionRows plan)
    writeCsv dir "xero_sync_runs.csv" xeroSyncRunColumns (xeroSyncRunRows plan)
    writeCsv dir "xero_employees.csv" xeroEmployeeColumns (xeroEmployeeRows plan)
    writeCsv dir "xero_staff_mappings.csv" xeroStaffMappingColumns (xeroStaffMappingRows plan)
    TextIO.writeFile (dir </> "load.sql") (renderLoadSql dir)
    TextIO.writeFile (dir </> "manifest.json") (renderProfileSeedManifest plan)

writeCsv :: FilePath -> FilePath -> [Text] -> [[Maybe Text]] -> IO ()
writeCsv dir fileName _ rows =
    TextIO.writeFile (dir </> fileName) (Text.unlines (map renderCsvRow rows))

renderCsvRow :: [Maybe Text] -> Text
renderCsvRow =
    Text.intercalate "," . map renderCsvCell

renderCsvCell :: Maybe Text -> Text
renderCsvCell Nothing = "\\N"
renderCsvCell (Just "\\N") = "\\N"
renderCsvCell (Just value) =
    "\"" <> Text.concatMap escape value <> "\""
    where
        escape '"'       = "\"\""
        escape character = Text.singleton character

renderLoadSql :: FilePath -> Text
renderLoadSql dir =
    Text.unlines $
        [ "BEGIN;"
        ]
            <> map renderCopy tableLoads
            <> [ "COMMIT;"
               , "ANALYZE;"
               ]
    where
        renderCopy (tableName, columns, fileName) =
            "\\copy "
                <> tableName
                <> " ("
                <> Text.intercalate ", " columns
                <> ") FROM '"
                <> Text.replace "'" "''" (cs (dir </> fileName))
                <> "' WITH (FORMAT csv, NULL '\\N')"

renderProfileSeedManifest :: ProfileSeedPlan -> Text
renderProfileSeedManifest plan =
    Text.unlines
        [ "{"
        , "  \"scenario\": \"large-roster-history\","
        , "  \"seed\": " <> tshow plan.options.seedValue <> ","
        , "  \"currentWeekOffset\": " <> tshow plan.currentWeekOffset <> ","
        , "  \"options\": {"
        , "    \"venues\": " <> tshow plan.options.venueCount <> ","
        , "    \"staffPerVenue\": " <> tshow plan.options.staffPerVenue <> ","
        , "    \"managersPerVenue\": " <> tshow plan.options.managerPerVenue <> ","
        , "    \"weeksHistory\": " <> tshow plan.options.weeksHistory <> ","
        , "    \"weeksFuture\": " <> tshow plan.options.weeksFuture <> ","
        , "    \"rowsPerDay\": " <> tshow plan.options.rowsPerDay <> ","
        , "    \"rosterFill\": " <> tshow plan.options.rosterFill <> ","
        , "    \"xeroEmployees\": " <> tshow plan.options.xeroEmployees <> ","
        , "    \"xeroMappedStaff\": " <> tshow (mappedXeroStaffCount plan.options)
        , "  },"
        , "  \"accounts\": {"
        , "    \"primaryManager\": { \"email\": " <> jsonString (staffEmail 1 1) <> ", \"password\": \"password123\", \"venueId\": " <> jsonString (venueId 1) <> ", \"staffId\": " <> jsonString (staffId 1 1) <> " },"
        , "    \"venueAdmin\": { \"email\": " <> jsonString (adminEmail 1) <> ", \"password\": \"password123\", \"venueId\": " <> jsonString (venueId 1) <> " },"
        , "    \"support\": { \"email\": \"profile-support@example.com\", \"password\": \"password123\" }"
        , "  },"
        , "  \"venues\": ["
        , Text.intercalate ",\n" (map renderVenueManifest (venueIndexes plan))
        , "  ],"
        , "  \"routes\": {"
        , "    \"rosterCurrent\": " <> jsonString (rosterWeekPath plan.currentWeekOffset 1 1) <> ","
        , "    \"rosterHistorical\": " <> jsonString (rosterWeekPath historicalWeekOffset 1 1) <> ","
        , "    \"rosterFuture\": " <> jsonString (rosterWeekPath futureWeekOffset 1 1) <> ","
        , "    \"rosterContentFragment\": " <> jsonString (rosterWeekContentFragmentPath plan.currentWeekOffset 1 1) <> ","
        , "    \"rosterStaffPanelFragment\": " <> jsonString (rosterWeekStaffPanelFragmentPath plan.currentWeekOffset 1 1) <> ","
        , "    \"rosterOverviewFragment\": " <> jsonString (rosterWeekOverviewFragmentPath plan.currentWeekOffset 1 1) <> ","
        , "    \"timesheetsCurrent\": " <> jsonString (timesheetWeekPath plan.currentWeekOffset) <> ","
        , "    \"timesheetDayFragment\": " <> jsonString (timesheetDayFragmentPath plan.currentWeekOffset 0) <> ","
        , "    \"leaveRequests\": \"/LeaveRequests\","
        , "    \"profileLeave\": \"/EditProfile?section=leave\","
        , "    \"admin\": \"/Admin\","
        , "    \"adminXeroFragment\": \"/ShowAdminXeroFragment\""
        , "  },"
        , "  \"xero\": {"
        , "    \"connectionId\": " <> jsonString (xeroConnectionId 1) <> ","
        , "    \"targetStaffId\": " <> jsonString (staffId 1 (xeroProfileTargetStaffIndex plan.options)) <> ","
        , "    \"targetStaffLabel\": " <> jsonString ("Xero employee for " <> staffDisplayName 1 (xeroProfileTargetStaffIndex plan.options)) <> ","
        , "    \"targetEmployeeId\": " <> jsonString (xeroEmployeeRemoteId (xeroProfileTargetStaffIndex plan.options)) <> ","
        , "    \"targetEmployeeLabel\": " <> jsonString (xeroEmployeeDisplayName (xeroProfileTargetStaffIndex plan.options) <> " - " <> xeroEmployeeEmail (xeroProfileTargetStaffIndex plan.options))
        , "  }"
        , "}"
        ]
    where
        historicalWeekOffset =
            plan.currentWeekOffset - min 52 (max 0 (plan.options.weeksHistory - 1))
        futureWeekOffset =
            plan.currentWeekOffset + min 4 (max 0 (plan.options.weeksFuture - 1))
        renderVenueManifest venueIndex =
            Text.intercalate
                "\n"
                [ "    {"
                , "      \"id\": " <> jsonString (venueId venueIndex) <> ","
                , "      \"name\": " <> jsonString ("Profile Venue " <> padded venueIndex) <> ","
                , "      \"adminEmail\": " <> jsonString (adminEmail venueIndex) <> ","
                , "      \"primaryManagerEmail\": " <> jsonString (staffEmail venueIndex 1) <> ","
                , "      \"defaultRosterGroupId\": " <> jsonString (rosterGroupId venueIndex 1) <> ","
                , "      \"rosterGroups\": ["
                , Text.intercalate ",\n" (map (renderRosterGroupManifest venueIndex) rosterGroupTemplates)
                , "      ]"
                , "    }"
                ]
        renderRosterGroupManifest venueIndex (groupIndex, groupName) =
            "        { \"id\": "
                <> jsonString (rosterGroupId venueIndex groupIndex)
                <> ", \"name\": "
                <> jsonString groupName
                <> " }"

rosterWeekPath :: Int -> Int -> Int -> Text
rosterWeekPath weekOffset venueIndex groupIndex =
    "/ShowRosterWeek?weekOffset=" <> tshow weekOffset <> "&rosterGroupId=" <> rosterGroupId venueIndex groupIndex

rosterWeekContentFragmentPath :: Int -> Int -> Int -> Text
rosterWeekContentFragmentPath weekOffset venueIndex groupIndex =
    "/ShowRosterWeekContentFragment?weekOffset=" <> tshow weekOffset <> "&rosterGroupId=" <> rosterGroupId venueIndex groupIndex

rosterWeekStaffPanelFragmentPath :: Int -> Int -> Int -> Text
rosterWeekStaffPanelFragmentPath weekOffset venueIndex groupIndex =
    "/ShowRosterWeekStaffPanelFragment?weekOffset=" <> tshow weekOffset <> "&rosterGroupId=" <> rosterGroupId venueIndex groupIndex

rosterWeekOverviewFragmentPath :: Int -> Int -> Int -> Text
rosterWeekOverviewFragmentPath weekOffset venueIndex groupIndex =
    "/ShowRosterWeekOverviewFragment?weekOffset=" <> tshow weekOffset <> "&rosterGroupId=" <> rosterGroupId venueIndex groupIndex

timesheetWeekPath :: Int -> Text
timesheetWeekPath weekOffset =
    "/ShowTimesheetWeek?weekOffset=" <> tshow weekOffset <> "&showApproved=true&showAllStaff=true"

timesheetDayFragmentPath :: Int -> Int -> Text
timesheetDayFragmentPath weekOffset dayOffset =
    "/ShowTimesheetDaySectionFragment?weekOffset=" <> tshow weekOffset <> "&dayOffset=" <> tshow dayOffset <> "&showApproved=true&showAllStaff=true"

jsonString :: Text -> Text
jsonString value =
    "\"" <> Text.concatMap escapeJsonChar value <> "\""
    where
        escapeJsonChar '"'       = "\\\""
        escapeJsonChar '\\'      = "\\\\"
        escapeJsonChar '\n'      = "\\n"
        escapeJsonChar '\r'      = "\\r"
        escapeJsonChar '\t'      = "\\t"
        escapeJsonChar character = Text.singleton character

tableLoads :: [(Text, [Text], FilePath)]
tableLoads =
    [ ("venues", venueColumns, "venues.csv")
    , ("users", userColumns, "users.csv")
    , ("venue_config", venueConfigColumns, "venue_config.csv")
    , ("venue_memberships", venueMembershipColumns, "venue_memberships.csv")
    , ("staff", staffColumns, "staff.csv")
    , ("shift_types", shiftTypeColumns, "shift_types.csv")
    , ("day_names", dayNameColumns, "day_names.csv")
    , ("pay_config_snapshots", payConfigSnapshotColumns, "pay_config_snapshots.csv")
    , ("report_definitions", reportDefinitionColumns, "report_definitions.csv")
    , ("roster_groups", rosterGroupColumns, "roster_groups.csv")
    , ("slot_names", slotNameColumns, "slot_names.csv")
    , ("staff_roster_groups", staffRosterGroupColumns, "staff_roster_groups.csv")
    , ("staff_availability", staffAvailabilityColumns, "staff_availability.csv")
    , ("staff_shift_preferences", staffShiftPreferenceColumns, "staff_shift_preferences.csv")
    , ("roster_weeks", rosterWeekColumns, "roster_weeks.csv")
    , ("roster_days", rosterDayColumns, "roster_days.csv")
    , ("roster_slots", rosterSlotColumns, "roster_slots.csv")
    , ("leave_requests", leaveRequestColumns, "leave_requests.csv")
    , ("timesheet_entries", timesheetEntryColumns, "timesheet_entries.csv")
    , ("timesheet_entry_versions", timesheetEntryVersionColumns, "timesheet_entry_versions.csv")
    , ("xero_connections", xeroConnectionColumns, "xero_connections.csv")
    , ("xero_sync_runs", xeroSyncRunColumns, "xero_sync_runs.csv")
    , ("xero_employees", xeroEmployeeColumns, "xero_employees.csv")
    , ("xero_staff_mappings", xeroStaffMappingColumns, "xero_staff_mappings.csv")
    ]

venueColumns, userColumns, venueConfigColumns, venueMembershipColumns, staffColumns :: [Text]
venueColumns = ["id", "name", "status"]
userColumns = ["id", "email", "password_hash", "user_role", "platform_role", "is_profile_completed", "email_verified_at", "failed_login_attempts", "locked_at"]
venueConfigColumns = ["id", "venue_id", "timezone", "roster_week_starts_on", "week_offset_epoch", "late_to_early_min_start_gap_minutes", "staff_timesheet_edit_window_days"]
venueMembershipColumns = ["id", "venue_id", "user_id", "venue_role", "is_active"]
staffColumns = ["id", "venue_id", "user_id", "first_name", "last_name", "preferred_name", "phone", "emergency_contact_name", "emergency_contact_phone", "ideal_shifts_per_week", "is_active"]

shiftTypeColumns, dayNameColumns, payConfigSnapshotColumns :: [Text]
shiftTypeColumns = ["id", "venue_id", "name", "sort_order", "override_award_level_id", "is_active"]
dayNameColumns = ["id", "venue_id", "weekday_index", "name", "is_active"]
payConfigSnapshotColumns = ["id", "venue_id", "version_number", "version_label", "created_by_user_id", "snapshot"]

reportDefinitionColumns, rosterGroupColumns, slotNameColumns, staffRosterGroupColumns :: [Text]
reportDefinitionColumns = ["id", "venue_id", "slug", "name", "description", "engine", "sort_order", "is_active"]
rosterGroupColumns = ["id", "venue_id", "name", "sort_order", "is_active", "is_default"]
slotNameColumns = ["id", "venue_id", "roster_group_id", "name", "sort_order", "is_active"]
staffRosterGroupColumns = ["id", "staff_id", "roster_group_id"]

staffAvailabilityColumns, staffShiftPreferenceColumns, rosterWeekColumns, rosterDayColumns, rosterSlotColumns :: [Text]
staffAvailabilityColumns = ["id", "venue_id", "staff_id", "weekday_index", "specific_date", "is_available", "note"]
staffShiftPreferenceColumns = ["id", "venue_id", "staff_id", "roster_group_id", "slot_name_id", "weekday_index"]
rosterWeekColumns = ["id", "venue_id", "roster_group_id", "week_offset", "is_live"]
rosterDayColumns = ["id", "roster_week_id", "day_offset", "is_closed"]
rosterSlotColumns = ["id", "roster_day_id", "staff_id", "slot_name_id", "slot_sort_order", "row_index", "start_time", "duration_minutes", "note"]

leaveRequestColumns, timesheetEntryColumns, timesheetEntryVersionColumns :: [Text]
leaveRequestColumns = ["id", "venue_id", "staff_id", "start_date", "end_date", "status", "notes"]
timesheetEntryColumns = ["id", "venue_id", "staff_id", "shift_type_id", "worked_on", "start_time", "end_time", "had_break", "break_start_time", "break_end_time", "break_minutes", "pay_config_snapshot_id", "is_approved", "approved_at", "approved_by_user_id"]
timesheetEntryVersionColumns = ["id", "venue_id", "timesheet_entry_id", "actor_user_id", "version_action", "snapshot", "payload"]

xeroConnectionColumns, xeroSyncRunColumns, xeroEmployeeColumns, xeroStaffMappingColumns :: [Text]
xeroConnectionColumns = ["id", "venue_id", "tenant_id", "tenant_name", "xero_connection_remote_id", "connection_status", "scopes", "encrypted_refresh_token", "encrypted_access_token", "access_token_expires_at", "last_refreshed_at", "last_sync_at", "connected_by_user_id", "connected_at"]
xeroSyncRunColumns = ["id", "venue_id", "xero_connection_id", "sync_status", "sync_kind", "employees_count", "earnings_rates_count", "payroll_calendars_count", "started_at", "finished_at"]
xeroEmployeeColumns = ["id", "venue_id", "xero_connection_id", "xero_employee_id", "display_name", "email", "status", "raw_payload", "synced_at"]
xeroStaffMappingColumns = ["id", "venue_id", "staff_id", "xero_connection_id", "xero_employee_id", "xero_employee_name", "xero_employee_email", "mapping_status", "last_verified_at", "created_by_user_id", "updated_by_user_id"]

venueRows :: ProfileSeedPlan -> [[Maybe Text]]
venueRows plan =
    [ row [uuidText 1 venueIndex 0 0, "Profile Venue " <> padded venueIndex, "active"]
    | venueIndex <- venueIndexes plan
    ]

userRows :: ProfileSeedPlan -> [[Maybe Text]]
userRows plan =
    supportUser : concatMap usersForVenue (venueIndexes plan)
    where
        supportUser =
            row [supportUserId, "profile-support@example.com", passwordHash, "staff", "super_admin", "true", timestampText, "0"]
                <> [Nothing]
        usersForVenue venueIndex =
            adminUser venueIndex :
            [ row [staffUserId venueIndex staffIndex, staffEmail venueIndex staffIndex, passwordHash, "staff", nullText, "true", timestampText, "0"] <> [Nothing]
            | staffIndex <- staffIndexes plan
            ]
        adminUser venueIndex =
            row [adminUserId venueIndex, adminEmail venueIndex, passwordHash, "admin", nullText, "true", timestampText, "0"] <> [Nothing]

venueConfigRows :: ProfileSeedPlan -> [[Maybe Text]]
venueConfigRows plan =
    [ row [uuidText 2 venueIndex 0 0, venueId venueIndex, "Australia/Melbourne", "1", "2025-01-06", "600", "7"]
    | venueIndex <- venueIndexes plan
    ]

venueMembershipRows :: ProfileSeedPlan -> [[Maybe Text]]
venueMembershipRows plan =
    concatMap membershipsForVenue (venueIndexes plan)
    where
        membershipsForVenue venueIndex =
            row [uuidText 3 venueIndex 0 0, venueId venueIndex, adminUserId venueIndex, "venue_admin", "true"] :
            [ row [uuidText 3 venueIndex staffIndex 1, venueId venueIndex, staffUserId venueIndex staffIndex, venueRoleFor plan staffIndex, "true"]
            | staffIndex <- staffIndexes plan
            ]

staffRows :: ProfileSeedPlan -> [[Maybe Text]]
staffRows plan =
    concatMap staffForVenue (venueIndexes plan)
    where
        staffForVenue venueIndex =
            row
                [ adminStaffId venueIndex
                , venueId venueIndex
                , adminUserId venueIndex
                , "Admin"
                , "Venue" <> padded venueIndex
                , nullText
                , "0400" <> Text.takeEnd 6 ("000000" <> tshow (venueIndex * 1000))
                , "Emergency Contact"
                , "0411111111"
                , "0"
                , "true"
                ] :
            [ row
                [ staffId venueIndex staffIndex
                , venueId venueIndex
                , staffUserId venueIndex staffIndex
                , "Staff" <> padded staffIndex
                , "Venue" <> padded venueIndex
                , if staffIndex `mod` 5 == 0 then "S" <> padded staffIndex else nullText
                , "0400" <> Text.takeEnd 6 ("000000" <> tshow (venueIndex * 1000 + staffIndex))
                , "Emergency Contact"
                , "0411111111"
                , tshow (1 + deterministicIndex plan [venueIndex, staffIndex, 14] 6)
                , "true"
                ]
            | staffIndex <- staffIndexes plan
            ]

payLevelRows :: ProfileSeedPlan -> [[Maybe Text]]
payLevelRows plan =
    [ row [payLevelId venueIndex levelIndex, venueId venueIndex, levelName, baseRate, "1.00", "2.00", "1.000", "1.250", "1.500", "true"]
    | venueIndex <- venueIndexes plan
    , (levelIndex, levelName, baseRate) <- payLevelTemplates
    ]

shiftTypeRows :: ProfileSeedPlan -> [[Maybe Text]]
shiftTypeRows plan =
    [ row [shiftTypeId venueIndex shiftIndex, venueId venueIndex, shiftName, tshow (shiftIndex * 10), nullText, "true"]
    | venueIndex <- venueIndexes plan
    , (shiftIndex, shiftName, _) <- shiftTypeTemplates
    ]

dayNameRows :: ProfileSeedPlan -> [[Maybe Text]]
dayNameRows plan =
    [ row [dayNameId venueIndex weekdayIndex, venueId venueIndex, tshow weekdayIndex, dayName, "true"]
    | venueIndex <- venueIndexes plan
    , (weekdayIndex, dayName) <- dayNameTemplates
    ]

payLevelDayRuleRows :: ProfileSeedPlan -> [[Maybe Text]]
payLevelDayRuleRows plan =
    [ row [uuidText 9 venueIndex shiftIndex weekdayIndex, shiftTypeId venueIndex shiftIndex, dayNameId venueIndex weekdayIndex, payLevelId venueIndex overrideLevel]
    | venueIndex <- venueIndexes plan
    , (shiftIndex, _, _) <- shiftTypeTemplates
    , (weekdayIndex, overrideLevel) <- [(6, 2), (0, 3)]
    ]

payConfigSnapshotRows :: ProfileSeedPlan -> [[Maybe Text]]
payConfigSnapshotRows plan =
    [ row [payConfigSnapshotId venueIndex, venueId venueIndex, "1", "v1", adminUserId venueIndex, "{\"profileSeed\":true,\"version\":1}"]
    | venueIndex <- venueIndexes plan
    ]

reportDefinitionRows :: ProfileSeedPlan -> [[Maybe Text]]
reportDefinitionRows plan =
    [ row [uuidText 11 venueIndex reportIndex 0, venueId venueIndex, slug, name, description, engine, tshow (reportIndex * 10), "true"]
    | venueIndex <- venueIndexes plan
    , (reportIndex, slug, name, description, engine) <- reportDefinitions
    ]

rosterGroupRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterGroupRows plan =
    [ row [rosterGroupId venueIndex groupIndex, venueId venueIndex, groupName, tshow (groupIndex * 10), "true", if groupIndex == 1 then "true" else "false"]
    | venueIndex <- venueIndexes plan
    , (groupIndex, groupName) <- rosterGroupTemplates
    ]

slotNameRows :: ProfileSeedPlan -> [[Maybe Text]]
slotNameRows plan =
    [ row [slotNameId venueIndex groupIndex slotIndex, venueId venueIndex, rosterGroupId venueIndex groupIndex, slotName, tshow slotIndex, "true"]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , (slotIndex, slotName) <- slotNameTemplates
    ]

staffRosterGroupRows :: ProfileSeedPlan -> [[Maybe Text]]
staffRosterGroupRows plan =
    [ row [uuidText 14 venueIndex staffIndex groupIndex, staffId venueIndex staffIndex, rosterGroupId venueIndex groupIndex]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , groupIndex <- eligibleGroupIndexes staffIndex
    ]

staffAvailabilityRows :: ProfileSeedPlan -> [[Maybe Text]]
staffAvailabilityRows plan =
    concat
        [ [ row [uuidText 15 venueIndex staffIndex 1, venueId venueIndex, staffId venueIndex staffIndex, tshow (deterministicIndex plan [venueIndex, staffIndex, 31] 7), nullText, "false", "Recurring unavailable"]
          , row [uuidText 15 venueIndex staffIndex 2, venueId venueIndex, staffId venueIndex staffIndex, nullText, dateText (addDays (toInteger (staffIndex `mod` 7)) (weekStartForOffset (currentWeekOffset plan))), "false", "Profile seed date block"]
          ]
        | venueIndex <- venueIndexes plan
        , staffIndex <- staffIndexes plan
        , staffIndex `mod` 3 == 0
        ]

staffShiftPreferenceRows :: ProfileSeedPlan -> [[Maybe Text]]
staffShiftPreferenceRows plan =
    [ row [uuidText 16 venueIndex staffIndex (groupIndex * 10 + prefIndex), venueId venueIndex, staffId venueIndex staffIndex, rosterGroupId venueIndex groupIndex, slotNameId venueIndex groupIndex slotIndex, tshow weekdayIndex]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , groupIndex <- eligibleGroupIndexes staffIndex
    , prefIndex <- [0 .. 2]
    , let slotIndex = 1 + deterministicIndex plan [venueIndex, staffIndex, groupIndex, prefIndex] (length slotNameTemplates)
    , let weekdayIndex = deterministicIndex plan [venueIndex, staffIndex, groupIndex, prefIndex, 9] 7
    ]

rosterWeekRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterWeekRows plan =
    [ row [rosterWeekId venueIndex groupIndex weekOffset, venueId venueIndex, rosterGroupId venueIndex groupIndex, tshow weekOffset, if weekOffset <= currentWeekOffset plan then "true" else "false"]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , weekOffset <- weekOffsets plan
    ]

rosterDayRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterDayRows plan =
    [ row [rosterDayId venueIndex groupIndex weekOffset dayOffset, rosterWeekId venueIndex groupIndex weekOffset, tshow dayOffset, "false"]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , weekOffset <- weekOffsets plan
    , dayOffset <- [0 .. 6]
    ]

rosterSlotRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterSlotRows plan =
    [ [ Just (rosterSlotId venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex)
      , Just (rosterDayId venueIndex groupIndex weekOffset dayOffset)
      , maybeStaffId
      , Just (slotNameId venueIndex groupIndex slotIndex)
      , Just (tshow slotIndex)
      , Just (tshow rowIndex)
      , if isJust maybeStaffId then Just (timeFor slotIndex dayOffset) else Nothing
      , if isJust maybeStaffId then Just "360" else Nothing
      , if deterministicIndex plan [venueIndex, groupIndex, weekOffset, dayOffset, rowIndex, slotIndex, 22] 9 == 0 then Just "OP" else Nothing
      ]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , weekOffset <- weekOffsets plan
    , dayOffset <- [0 .. 6]
    , rowIndex <- [0 .. rowsPerDay plan.options - 1]
    , (slotIndex, _) <- slotNameTemplates
    , let maybeStaffId = assignedStaffId plan venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex
    ]

leaveRequestRows :: ProfileSeedPlan -> [[Maybe Text]]
leaveRequestRows plan =
    [ row
        [ uuidText 19 venueIndex staffIndex leaveIndex
        , venueId venueIndex
        , staffId venueIndex staffIndex
        , dateText startDate
        , dateText (addDays (toInteger (leaveIndex `mod` 3)) startDate)
        , leaveStatus leaveIndex
        , "Synthetic profiling leave"
        ]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , leaveIndex <- [1 .. 3]
    , let baseWeek = currentWeekOffset plan - deterministicIndex plan [venueIndex, staffIndex, leaveIndex, 55] (max 1 (weeksHistory plan.options))
    , let startDate = addDays (toInteger (deterministicIndex plan [venueIndex, staffIndex, leaveIndex, 56] 7)) (weekStartForOffset baseWeek)
    ]

timesheetEntryRows :: ProfileSeedPlan -> [[Maybe Text]]
timesheetEntryRows plan =
    [ row
        [ timesheetEntryId venueIndex staffIndex weekOrdinal
        , venueId venueIndex
        , staffId venueIndex staffIndex
        , shiftTypeId venueIndex (1 + deterministicIndex plan [venueIndex, staffIndex, weekOrdinal, 70] (length shiftTypeTemplates))
        , dateText workedOn
        , "09:00:00"
        , "17:00:00"
        , "true"
        , "12:00:00"
        , "12:30:00"
        , "30"
        , payConfigSnapshotId venueIndex
        , if isApproved then "true" else "false"
        , if isApproved then timestampText else nullText
        , if isApproved then adminUserId venueIndex else nullText
        ]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , weekOrdinal <- [0 .. min 52 (max 1 (weeksHistory plan.options)) - 1]
    , let weekOffset = currentWeekOffset plan - weekOrdinal
    , let workedOn = addDays (toInteger (staffIndex `mod` 7)) (weekStartForOffset weekOffset)
    , let isApproved = deterministicIndex plan [venueIndex, staffIndex, weekOrdinal, 71] 100 < 82
    ]

timesheetEntryVersionRows :: ProfileSeedPlan -> [[Maybe Text]]
timesheetEntryVersionRows plan =
    [ row
        [ uuidText 21 venueIndex staffIndex weekOrdinal
        , venueId venueIndex
        , timesheetEntryId venueIndex staffIndex weekOrdinal
        , adminUserId venueIndex
        , "created"
        , "{}"
        , "{\"profileSeed\":true}"
        ]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , weekOrdinal <- [0 .. min 52 (max 1 (weeksHistory plan.options)) - 1]
    ]

xeroConnectionRows :: ProfileSeedPlan -> [[Maybe Text]]
xeroConnectionRows plan =
    [ row
        [ xeroConnectionId venueIndex
        , venueId venueIndex
        , "profile-xero-tenant-" <> padded venueIndex
        , "Profile Xero Tenant " <> padded venueIndex
        , "profile-xero-connection-" <> padded venueIndex
        , "active"
        , "openid profile email accounting.settings payroll.employees payroll.payruns offline_access"
        , "profile-refresh-token-" <> padded venueIndex
        , "profile-access-token-" <> padded venueIndex
        , "2027-01-01 00:00:00+00"
        , timestampText
        , timestampText
        , adminUserId venueIndex
        , timestampText
        ]
    | venueIndex <- venueIndexes plan
    ]

xeroSyncRunRows :: ProfileSeedPlan -> [[Maybe Text]]
xeroSyncRunRows plan =
    [ row
        [ xeroSyncRunId venueIndex
        , venueId venueIndex
        , xeroConnectionId venueIndex
        , "succeeded"
        , "payroll_reference_data"
        , tshow plan.options.xeroEmployees
        , "0"
        , "0"
        , timestampText
        , timestampText
        ]
    | venueIndex <- venueIndexes plan
    ]

xeroEmployeeRows :: ProfileSeedPlan -> [[Maybe Text]]
xeroEmployeeRows plan =
    [ row
        [ xeroEmployeeId venueIndex employeeIndex
        , venueId venueIndex
        , xeroConnectionId venueIndex
        , xeroEmployeeRemoteId employeeIndex
        , xeroEmployeeDisplayName employeeIndex
        , xeroEmployeeEmail employeeIndex
        , "ACTIVE"
        , "{\"profileSeed\":true}"
        , timestampText
        ]
    | venueIndex <- venueIndexes plan
    , employeeIndex <- [1 .. xeroEmployees plan.options]
    ]

xeroStaffMappingRows :: ProfileSeedPlan -> [[Maybe Text]]
xeroStaffMappingRows plan =
    [ row
        [ xeroStaffMappingId venueIndex staffIndex
        , venueId venueIndex
        , staffId venueIndex staffIndex
        , xeroConnectionId venueIndex
        , xeroEmployeeRemoteId staffIndex
        , xeroEmployeeDisplayName staffIndex
        , xeroEmployeeEmail staffIndex
        , "verified"
        , timestampText
        , adminUserId venueIndex
        , adminUserId venueIndex
        ]
    | venueIndex <- venueIndexes plan
    , staffIndex <- [1 .. mappedXeroStaffCount plan.options]
    ]

assignedStaffId :: ProfileSeedPlan -> Int -> Int -> Int -> Int -> Int -> Int -> Maybe Text
assignedStaffId plan venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex
    | deterministicIndex plan [venueIndex, groupIndex, weekOffset, dayOffset, rowIndex, slotIndex] 100 >= rosterFill plan.options = Nothing
    | otherwise = Just (staffId venueIndex selectedStaffIndex)
    where
        candidates = eligibleStaffIndexesForGroup plan groupIndex
        selectedStaffIndex = candidates !! deterministicIndex plan [venueIndex, groupIndex, weekOffset, dayOffset, rowIndex, slotIndex, 99] (length candidates)

eligibleStaffIndexesForGroup :: ProfileSeedPlan -> Int -> [Int]
eligibleStaffIndexesForGroup plan groupIndex =
    filter (\staffIndex -> groupIndex `elem` eligibleGroupIndexes staffIndex) (staffIndexes plan)

eligibleGroupIndexes :: Int -> [Int]
eligibleGroupIndexes staffIndex
    | staffIndex <= 4 = [1, 2]
    | staffIndex `mod` 5 == 0 = [1, 2]
    | staffIndex `mod` 2 == 0 = [2]
    | otherwise = [1]

venueRoleFor :: ProfileSeedPlan -> Int -> Text
venueRoleFor plan staffIndex
    | staffIndex <= managerPerVenue plan.options = "manager"
    | otherwise = "worker"

venueIndexes :: ProfileSeedPlan -> [Int]
venueIndexes plan = [1 .. venueCount plan.options]

staffIndexes :: ProfileSeedPlan -> [Int]
staffIndexes plan = [1 .. staffPerVenue plan.options]

mappedXeroStaffCount :: ProfileSeedOptions -> Int
mappedXeroStaffCount options =
    min options.staffPerVenue (min (max 0 (options.xeroEmployees - 1)) options.xeroMappedStaff)

xeroProfileTargetStaffIndex :: ProfileSeedOptions -> Int
xeroProfileTargetStaffIndex options =
    min options.staffPerVenue (min options.xeroEmployees (mappedXeroStaffCount options + 5))

weekOffsets :: ProfileSeedPlan -> [Int]
weekOffsets plan =
    [currentWeekOffset plan - weeksHistory plan.options + 1 .. currentWeekOffset plan + weeksFuture plan.options]

weekStartForOffset :: Int -> Day
weekStartForOffset weekOffset =
    addDays (toInteger (weekOffset * 7)) defaultWeekEpoch

currentWeekOffsetForDay :: Day -> Int
currentWeekOffsetForDay today =
    fromInteger (diffDays today defaultWeekEpoch `div` 7)

defaultWeekEpoch :: Day
defaultWeekEpoch = fromGregorian 2025 1 6

dateText :: Day -> Text
dateText = tshow

timeFor :: Int -> Int -> Text
timeFor slotIndex dayOffset =
    case slotIndex of
        1 -> if even dayOffset then "06:30:00" else "07:00:00"
        2 -> if even dayOffset then "11:00:00" else "11:30:00"
        _ -> if even dayOffset then "16:30:00" else "17:00:00"

leaveStatus :: Int -> Text
leaveStatus leaveIndex =
    case leaveIndex `mod` 4 of
        0 -> "pending"
        1 -> "approved"
        2 -> "approved"
        _ -> "denied"

uuidText :: Int -> Int -> Int -> Int -> Text
uuidText namespace a b c =
    Text.pack (hex8 firstGroup <> "-" <> hex4 secondGroup <> "-4" <> hex3 thirdGroup <> "-8" <> hex3 fourthGroup <> "-" <> hex12 fifthGroup)
    where
        firstGroup = namespace * 1000000 + a
        secondGroup = b
        thirdGroup = c
        fourthGroup = a + b + c
        fifthGroup = namespace * 100000000 + a * 1000000 + b * 1000 + c

hex3 :: Int -> String
hex3 value = padLeft 3 (showHexText value)

hex4 :: Int -> String
hex4 value = padLeft 4 (showHexText value)

hex8 :: Int -> String
hex8 value = padLeft 8 (showHexText value)

hex12 :: Int -> String
hex12 value = padLeft 12 (showHexText value)

showHexText :: Int -> String
showHexText value =
    let digits = "0123456789abcdef"
        go number
            | number < 16 = [digits !! number]
            | otherwise = go (number `div` 16) <> [digits !! (number `mod` 16)]
     in go (abs value)

padLeft :: Int -> String -> String
padLeft width value =
    let trimmed = drop (max 0 (length value - width)) value
     in replicate (max 0 (width - length trimmed)) '0' <> trimmed

venueId :: Int -> Text
venueId venueIndex = uuidText 1 venueIndex 0 0

supportUserId :: Text
supportUserId = uuidText 4 0 0 1

adminUserId :: Int -> Text
adminUserId venueIndex = uuidText 4 venueIndex 0 0

staffUserId :: Int -> Int -> Text
staffUserId venueIndex staffIndex = uuidText 4 venueIndex staffIndex 0

staffId :: Int -> Int -> Text
staffId venueIndex staffIndex = uuidText 5 venueIndex staffIndex 0

adminStaffId :: Int -> Text
adminStaffId venueIndex = uuidText 5 venueIndex 0 0

payLevelId :: Int -> Int -> Text
payLevelId venueIndex levelIndex = uuidText 6 venueIndex levelIndex 0

shiftTypeId :: Int -> Int -> Text
shiftTypeId venueIndex shiftIndex = uuidText 7 venueIndex shiftIndex 0

dayNameId :: Int -> Int -> Text
dayNameId venueIndex weekdayIndex = uuidText 8 venueIndex weekdayIndex 0

payConfigSnapshotId :: Int -> Text
payConfigSnapshotId venueIndex = uuidText 10 venueIndex 0 0

rosterGroupId :: Int -> Int -> Text
rosterGroupId venueIndex groupIndex = uuidText 12 venueIndex groupIndex 0

slotNameId :: Int -> Int -> Int -> Text
slotNameId venueIndex groupIndex slotIndex = uuidText 13 venueIndex groupIndex slotIndex

rosterWeekId :: Int -> Int -> Int -> Text
rosterWeekId venueIndex groupIndex weekOffset = uuidText 17 venueIndex groupIndex (weekOffset + 10000)

rosterDayId :: Int -> Int -> Int -> Int -> Text
rosterDayId venueIndex groupIndex weekOffset dayOffset = uuidText 18 venueIndex groupIndex ((weekOffset + 10000) * 10 + dayOffset)

rosterSlotId :: Int -> Int -> Int -> Int -> Int -> Int -> Text
rosterSlotId venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex =
    uuidText 19 venueIndex groupIndex (((weekOffset + 10000) * 1000) + dayOffset * 100 + rowIndex * 10 + slotIndex)

timesheetEntryId :: Int -> Int -> Int -> Text
timesheetEntryId venueIndex staffIndex weekOrdinal = uuidText 20 venueIndex staffIndex weekOrdinal

xeroConnectionId :: Int -> Text
xeroConnectionId venueIndex = uuidText 22 venueIndex 0 0

xeroSyncRunId :: Int -> Text
xeroSyncRunId venueIndex = uuidText 23 venueIndex 0 0

xeroEmployeeId :: Int -> Int -> Text
xeroEmployeeId venueIndex employeeIndex = uuidText 24 venueIndex employeeIndex 0

xeroStaffMappingId :: Int -> Int -> Text
xeroStaffMappingId venueIndex staffIndex = uuidText 25 venueIndex staffIndex 0

xeroEmployeeRemoteId :: Int -> Text
xeroEmployeeRemoteId employeeIndex =
    "profile-xero-employee-" <> padded employeeIndex

xeroEmployeeDisplayName :: Int -> Text
xeroEmployeeDisplayName employeeIndex =
    "Profile Xero Employee " <> padded employeeIndex

xeroEmployeeEmail :: Int -> Text
xeroEmployeeEmail employeeIndex =
    "profile-xero-employee-" <> padded employeeIndex <> "@example.com"

staffDisplayName :: Int -> Int -> Text
staffDisplayName venueIndex staffIndex =
    "Staff" <> padded staffIndex <> " Venue" <> padded venueIndex

adminEmail :: Int -> Text
adminEmail venueIndex = "profile-manager-" <> padded venueIndex <> "@example.com"

staffEmail :: Int -> Int -> Text
staffEmail venueIndex staffIndex = "profile-staff-" <> padded venueIndex <> "-" <> padded staffIndex <> "@example.com"

padded :: Int -> Text
padded value =
    Text.pack (padLeft 2 (Text.unpack (tshow value)))

row :: [Text] -> [Maybe Text]
row = map Just

nullText :: Text
nullText = "\\N"

passwordHash :: Text
passwordHash = "sha256|17|tZ8jkd+zwREDUkZy1w3iQA==|e9Gf+M+KF5EZCsAZYhmxd2cKy6WJp7b2/3GD98ELUpQ="

timestampText :: Text
timestampText = "2026-04-24 00:00:00+00"

payLevelTemplates :: [(Int, Text, Text)]
payLevelTemplates =
    [ (1, "Level 1", "29.50")
    , (2, "Level 2", "33.00")
    , (3, "Level 3", "38.00")
    ]

shiftTypeTemplates :: [(Int, Text, Int)]
shiftTypeTemplates =
    [ (1, "Floor", 1)
    , (2, "Kitchen", 2)
    , (3, "Bar", 3)
    ]

dayNameTemplates :: [(Int, Text)]
dayNameTemplates =
    [ (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    , (0, "Sunday")
    ]

reportDefinitions :: [(Int, Text, Text, Text, Text)]
reportDefinitions =
    [ (1, "staff_hours", "Staff Hours", "All approved staff hours", "staff_pay_csv")
    , (2, "hourly_breakdown", "Hourly Breakdown", "Hourly ZIP export", "hourly_breakdown_zip")
    ]

rosterGroupTemplates :: [(Int, Text)]
rosterGroupTemplates =
    [ (1, "Front of House")
    , (2, "Back of House")
    ]

slotNameTemplates :: [(Int, Text)]
slotNameTemplates =
    [ (1, "Early")
    , (2, "Mid")
    , (3, "Late")
    ]

deterministicIndex :: ProfileSeedPlan -> [Int] -> Int -> Int
deterministicIndex _ _ 0 = 0
deterministicIndex plan keys modulus =
    abs (foldl' (\acc value -> (acc * 1103515245) + value + 12345) (seedValue plan.options + 17) keys) `mod` modulus

parseOptions :: IO ProfileSeedOptions
parseOptions = do
    args <- Environment.getArgs
    when ("--help" `elem` args || "-h" `elem` args) do
        printUsage
        exitSuccess
    foldM parseArg defaultOptions args

parseArg :: ProfileSeedOptions -> String -> IO ProfileSeedOptions
parseArg options arg
    | "--output-dir=" `List.isPrefixOf` arg = pure options { outputDir = readStringFlag "--output-dir=" arg }
    | "--venues=" `List.isPrefixOf` arg = pure options { venueCount = max 1 (readIntFlag "--venues=" arg) }
    | "--staff-per-venue=" `List.isPrefixOf` arg = pure options { staffPerVenue = max 1 (readIntFlag "--staff-per-venue=" arg) }
    | "--managers-per-venue=" `List.isPrefixOf` arg = pure options { managerPerVenue = max 1 (readIntFlag "--managers-per-venue=" arg) }
    | "--weeks-history=" `List.isPrefixOf` arg = pure options { weeksHistory = max 1 (readIntFlag "--weeks-history=" arg) }
    | "--weeks-future=" `List.isPrefixOf` arg = pure options { weeksFuture = max 0 (readIntFlag "--weeks-future=" arg) }
    | "--rows-per-day=" `List.isPrefixOf` arg = pure options { rowsPerDay = max 1 (readIntFlag "--rows-per-day=" arg) }
    | "--roster-fill=" `List.isPrefixOf` arg = pure options { rosterFill = max 0 (min 100 (readIntFlag "--roster-fill=" arg)) }
    | "--seed=" `List.isPrefixOf` arg = pure options { seedValue = readIntFlag "--seed=" arg }
    | "--xero-employees=" `List.isPrefixOf` arg = pure options { xeroEmployees = max 1 (readIntFlag "--xero-employees=" arg) }
    | "--xero-mapped-staff=" `List.isPrefixOf` arg = pure options { xeroMappedStaff = max 0 (readIntFlag "--xero-mapped-staff=" arg) }
    | "--scenario=large-roster-history" == arg = pure options
    | otherwise = error ("Unsupported seed-profile option: " <> cs arg)

readStringFlag :: String -> String -> FilePath
readStringFlag prefix arg = drop (length prefix) arg

readIntFlag :: String -> String -> Int
readIntFlag prefix arg =
    case TextRead.readMaybe (drop (length prefix) arg) of
        Just value -> value
        Nothing    -> error ("Expected integer for flag: " <> cs arg)

printUsage :: IO ()
printUsage = do
    TextIO.putStrLn "Usage: seed-profile [app_profile] [--scenario=large-roster-history] [options...]"
    TextIO.putStrLn "Options:"
    TextIO.putStrLn "  --output-dir=<path>"
    TextIO.putStrLn "  --venues=<int>"
    TextIO.putStrLn "  --staff-per-venue=<int>"
    TextIO.putStrLn "  --managers-per-venue=<int>"
    TextIO.putStrLn "  --weeks-history=<int>"
    TextIO.putStrLn "  --weeks-future=<int>"
    TextIO.putStrLn "  --rows-per-day=<int>"
    TextIO.putStrLn "  --roster-fill=<0-100>"
    TextIO.putStrLn "  --seed=<int>"
    TextIO.putStrLn "  --xero-employees=<int>"
    TextIO.putStrLn "  --xero-mapped-staff=<int>"

printSummary :: ProfileSeedOptions -> ProfileSeedPlan -> IO ()
printSummary options plan = do
    TextIO.putStrLn "Profile seed generated."
    TextIO.putStrLn ("Output dir: " <> cs options.outputDir)
    TextIO.putStrLn ("Scenario: large-roster-history")
    TextIO.putStrLn ("Seed: " <> tshow options.seedValue)
    TextIO.putStrLn ("Current week offset: " <> tshow plan.currentWeekOffset)
    forM_ plan.counts \(label, count) ->
        TextIO.putStrLn (label <> ": " <> tshow count)
    TextIO.putStrLn ("Primary manager login: " <> staffEmail 1 1)
    TextIO.putStrLn "Primary manager password: password123"
    TextIO.putStrLn ("Venue admin login: " <> adminEmail 1)
    TextIO.putStrLn "Venue admin password: password123"
    TextIO.putStrLn "Support login: profile-support@example.com"
    TextIO.putStrLn "Support password: password123"
