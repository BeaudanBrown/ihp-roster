module Application.Script.SeedProfile where

import Application.Fixture.Seed.Calendar (currentWeekOffsetForDay,
                                          weekStartForOffset)
import Application.Helper.Url (appendQueryParams, replaceQueryParams)
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model (resolveBoundaryInstant)
import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import Data.Time.LocalTime (TimeOfDay (..))
import IHP.ControllerPrelude (pathTo)
import IHP.Prelude
import System.Directory (createDirectoryIfMissing)
import qualified System.Environment as Environment
import System.Exit (exitSuccess)
import System.FilePath ((</>))
import qualified Text.Read as TextRead
import Web.Routes ()
import Web.Types (AdminController (AdminAction, ShowadminInvitesLiveFragmentAction, ShowadminRosterGroupsLiveFragmentAction, ShowadminShiftTypesLiveFragmentAction, ShowadminXeroShellLiveFragmentAction, XeroAction),
                  LeaveRequestsController (LeaveRequestsAction, ShowleaveRequestsContentLiveFragmentAction),
                  ProfilesController (EditProfileAction, ShowprofileContentLiveFragmentAction),
                  RosterWeeksController (ShowRosterWeekAction, ShowRosterWeekContentFragmentAction, ShowRosterWeekOverviewFragmentAction, ShowRosterWeekStaffPanelFragmentAction, ShowRosterWindowAction),
                  TimesheetsController (ShowTimesheetDaySectionFragmentAction, ShowTimesheetWeekAction, ShowTimesheetWindowAction, TimesheetsAction))

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
            , ("staff_pay_versions", venueCount options * staffPerVenue options)
            , ("shift_type_pay_versions", venueCount options * length shiftTypeTemplates)
            , ("roster_weeks", rosterWeekCount)
            , ("roster_days", rosterDayCount)
            , ("roster_week_slot_definitions", rosterWeekCount * slotNamesPerGroup)
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
    either (fail . cs . tshow) pure (validateProfileTableDescriptors plan profileTableDescriptors)
    forM_ profileTableDescriptors (writeProfileTable dir plan)
    TextIO.writeFile (dir </> "load.sql") (renderLoadSql dir)
    TextIO.writeFile (dir </> "manifest.json") (renderProfileSeedManifest plan)

writeProfileTable :: FilePath -> ProfileSeedPlan -> ProfileTableDescriptor -> IO ()
writeProfileTable dir plan descriptor =
    TextIO.writeFile
        (dir </> descriptor.descriptorFileName)
        (Text.unlines (map renderCsvRow (descriptor.descriptorRows plan)))

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
            <> concatMap renderDescriptorLoad profileTableDescriptors
            <> [ "COMMIT;"
               , "ANALYZE;"
               ]
    where
        renderDescriptorLoad descriptor
            | descriptor.descriptorTable == ProfileTimesheetEntries = renderTimesheetEntryLoad descriptor
            | otherwise = [renderCopy descriptor.descriptorTableName descriptor]

        renderCopy targetTable descriptor =
            "\\copy "
                <> targetTable
                <> " ("
                <> Text.intercalate ", " descriptor.descriptorColumns
                <> ") FROM '"
                <> Text.replace "'" "''" (cs (dir </> descriptor.descriptorFileName))
                <> "' WITH (FORMAT csv, NULL '\\N')"

        renderTimesheetEntryLoad descriptor =
            [ "CREATE TEMP TABLE profile_seed_timesheet_entries (LIKE timesheet_entries INCLUDING DEFAULTS);"
            , renderCopy "profile_seed_timesheet_entries" descriptor
            , "INSERT INTO timesheet_entries (id, venue_id, staff_id, shift_type_id, starts_at, ends_at, break_starts_at, break_ends_at, timezone, is_approved) SELECT id, venue_id, staff_id, shift_type_id, starts_at, ends_at, break_starts_at, break_ends_at, timezone, FALSE FROM profile_seed_timesheet_entries;"
            , "INSERT INTO timesheet_pay_calculations (id, timesheet_entry_id, calculation_version, calculation_source, venue_timezone, holiday_jurisdiction, staff_pay_version_id, shift_type_pay_version_id, approved_at, approved_by_user_id, sealed_at, created_at) SELECT uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || id::text), id, 'profile-seed-v1', 'hospitality_award', timezone, 'VIC', staff_pay_version_id, shift_type_pay_version_id, approved_at, approved_by_user_id, NULL, approved_at FROM profile_seed_timesheet_entries WHERE is_approved;"
            , "INSERT INTO timesheet_pay_time_segments (id, timesheet_pay_calculation_id, ordinal, paid_time_kind, starts_at, ends_at, local_date, source_condition, created_at) SELECT uuid_generate_v5(uuid_ns_url(), 'bepis-profile-segment-a:' || id::text), uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || id::text), 0, 'worked', starts_at, break_starts_at, (starts_at AT TIME ZONE timezone)::date, 'ordinary', approved_at FROM profile_seed_timesheet_entries WHERE is_approved;"
            , "INSERT INTO timesheet_pay_time_segments (id, timesheet_pay_calculation_id, ordinal, paid_time_kind, starts_at, ends_at, local_date, source_condition, created_at) SELECT uuid_generate_v5(uuid_ns_url(), 'bepis-profile-segment-b:' || id::text), uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || id::text), 1, 'worked', break_ends_at, ends_at, (break_ends_at AT TIME ZONE timezone)::date, 'ordinary', approved_at FROM profile_seed_timesheet_entries WHERE is_approved;"
            , "INSERT INTO timesheet_pay_earnings_components (id, timesheet_pay_calculation_id, ordinal, quantity, unit_type, rate_per_unit, exact_amount, source_condition, calculation_source, source_rate_identity, created_at) SELECT uuid_generate_v5(uuid_ns_url(), 'bepis-profile-earning:' || id::text), uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || id::text), 0, 7.5, 'hours', 30, 225, 'ordinary', 'hospitality_award', 'profile-seed-v1', approved_at FROM profile_seed_timesheet_entries WHERE is_approved;"
            , "UPDATE timesheet_pay_calculations calculation SET sealed_at = calculation.approved_at WHERE calculation.id IN (SELECT uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || id::text) FROM profile_seed_timesheet_entries WHERE is_approved);"
            , "UPDATE timesheet_entries entry SET active_pay_calculation_id = uuid_generate_v5(uuid_ns_url(), 'bepis-profile-pay:' || staged.id::text), staff_pay_version_id = staged.staff_pay_version_id, shift_type_pay_version_id = staged.shift_type_pay_version_id, is_approved = TRUE, approved_at = staged.approved_at, approved_by_user_id = staged.approved_by_user_id FROM profile_seed_timesheet_entries staged WHERE entry.id = staged.id AND staged.is_approved;"
            ]

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
        , "    \"timesheetsReset\": " <> jsonString (timesheetResetPath plan.currentWeekOffset) <> ","
        , "    \"timesheetsStaffFilter\": " <> jsonString (timesheetStaffFilterPath plan.currentWeekOffset (staffId 1 1)) <> ","
        , "    \"timesheetDayFragment\": " <> jsonString (timesheetDayFragmentPath plan.currentWeekOffset 0) <> ","
        , "    \"leaveRequests\": " <> jsonString (pathTo LeaveRequestsAction) <> ","
        , "    \"leaveRequestsFragment\": " <> jsonString (pathTo ShowleaveRequestsContentLiveFragmentAction) <> ","
        , "    \"editProfile\": " <> jsonString (pathTo EditProfileAction) <> ","
        , "    \"profileSecurity\": " <> jsonString (profileSectionPath "security") <> ","
        , "    \"profileLeave\": " <> jsonString (profileSectionPath "leave") <> ","
        , "    \"profileLeaveSectionFragment\": " <> jsonString profileLeaveSectionFragmentPath <> ","
        , "    \"admin\": " <> jsonString (pathTo AdminAction) <> ","
        , "    \"adminExports\": " <> jsonString (pathTo AdminAction <> "#exports") <> ","
        , "    \"adminInvitesFragment\": " <> jsonString (adminInvitesFragmentPath 1 1) <> ","
        , "    \"adminShiftTypesFragment\": " <> jsonString (pathTo ShowadminShiftTypesLiveFragmentAction) <> ","
        , "    \"adminRosterGroupsFragment\": " <> jsonString (pathTo ShowadminRosterGroupsLiveFragmentAction) <> ","
        , "    \"xero\": " <> jsonString (pathTo XeroAction) <> ","
        , "    \"adminXeroFragment\": " <> jsonString (pathTo ShowadminXeroShellLiveFragmentAction)
        , "  },"
        , "  \"exports\": {"
        , "    \"rangeStart\": " <> jsonString (dateText currentWeekStart) <> ","
        , "    \"rangeEnd\": " <> jsonString (dateText currentWeekEnd)
        , "  }"
        , "}"
        ]
    where
        currentWeekStart = weekStartForOffset plan.currentWeekOffset
        currentWeekEnd = addDays 6 currentWeekStart
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

profileLeaveSectionFragmentPath :: Text
profileLeaveSectionFragmentPath =
    appendQueryParams (pathTo ShowprofileContentLiveFragmentAction) [("section", "leave")]

profileSectionPath :: Text -> Text
profileSectionPath section =
    appendQueryParams (pathTo EditProfileAction) [("section", section)]

rosterWeekPath :: Int -> Int -> Int -> Text
rosterWeekPath weekOffset venueIndex groupIndex =
    replaceQueryParams
        (pathTo (ShowRosterWindowAction anchorDate))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", rosterGroupId venueIndex groupIndex)]
  where
    anchorDate = weekStartForOffset weekOffset

rosterWeekContentFragmentPath :: Int -> Int -> Int -> Text
rosterWeekContentFragmentPath weekOffset venueIndex groupIndex =
    replaceQueryParams
        (pathTo (ShowRosterWeekContentFragmentAction anchorDate))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", rosterGroupId venueIndex groupIndex)]
  where
    anchorDate = weekStartForOffset weekOffset

rosterWeekStaffPanelFragmentPath :: Int -> Int -> Int -> Text
rosterWeekStaffPanelFragmentPath weekOffset venueIndex groupIndex =
    replaceQueryParams
        (pathTo (ShowRosterWeekStaffPanelFragmentAction anchorDate))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", rosterGroupId venueIndex groupIndex)]
  where
    anchorDate = weekStartForOffset weekOffset

rosterWeekOverviewFragmentPath :: Int -> Int -> Int -> Text
rosterWeekOverviewFragmentPath weekOffset venueIndex groupIndex =
    replaceQueryParams
        (pathTo (ShowRosterWeekOverviewFragmentAction anchorDate))
        [("anchorDate", tshow anchorDate), ("rosterGroupId", rosterGroupId venueIndex groupIndex)]
  where
    anchorDate = weekStartForOffset weekOffset

timesheetWeekPath :: Int -> Text
timesheetWeekPath weekOffset =
    replaceQueryParams
        (pathTo (ShowTimesheetWindowAction anchorDate))
        [("anchorDate", tshow anchorDate)]
  where
    anchorDate = weekStartForOffset weekOffset

timesheetResetPath :: Int -> Text
timesheetResetPath _weekOffset =
    pathTo TimesheetsAction

timesheetStaffFilterPath :: Int -> Text -> Text
timesheetStaffFilterPath weekOffset staffUuid =
    appendQueryParams (timesheetWeekPath weekOffset) [("staffFilterId", staffUuid)]

timesheetDayFragmentPath :: Int -> Int -> Text
timesheetDayFragmentPath weekOffset dayOffset =
    let windowStart = weekStartForOffset weekOffset
     in pathTo (ShowTimesheetDaySectionFragmentAction windowStart (addDays (toInteger dayOffset) windowStart))

adminInvitesFragmentPath :: Int -> Int -> Text
adminInvitesFragmentPath venueIndex groupIndex =
    appendQueryParams
        (pathTo ShowadminInvitesLiveFragmentAction)
        [("rosterGroupId", rosterGroupId venueIndex groupIndex)]

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

data ProfileTable
    = ProfileVenues
    | ProfileUsers
    | ProfilePasskeys
    | ProfileVenueConfig
    | ProfileVenueMemberships
    | ProfileStaff
    | ProfileShiftTypes
    | ProfileDayNames
    | ProfileStaffPayVersions
    | ProfileShiftTypePayVersions
    | ProfileRosterGroups
    | ProfileSlotNames
    | ProfileStaffRosterGroups
    | ProfileStaffShiftPreferences
    | ProfileRosterWeeks
    | ProfileRosterDays
    | ProfileRosterWeekSlotDefinitions
    | ProfileRosterSlots
    | ProfileLeaveRequests
    | ProfileTimesheetEntries
    | ProfileTimesheetEntryVersions
    | ProfileXeroConnections
    | ProfileXeroSyncRuns
    | ProfileXeroEmployees
    | ProfileXeroStaffMappings
    deriving (Bounded, Enum, Eq, Ord, Show)

data ProfileTableDescriptor = ProfileTableDescriptor
    { descriptorTable     :: !ProfileTable
    , descriptorTableName :: !Text
    , descriptorFileName  :: !FilePath
    , descriptorColumns   :: ![Text]
    , descriptorRows      :: ProfileSeedPlan -> [[Maybe Text]]
    }

data ProfileTableValidationError
    = MissingProfileTable !ProfileTable
    | DuplicateProfileTable !ProfileTable
    | DuplicateProfileTableName !Text
    | DuplicateProfileFileName !FilePath
    | ProfileRowWidthMismatch !ProfileTable !Int !Int !Int
    deriving (Eq, Show)

profileTableDescriptors :: [ProfileTableDescriptor]
profileTableDescriptors = map profileTableDescriptor [minBound .. maxBound]

profileTableDescriptor :: ProfileTable -> ProfileTableDescriptor
profileTableDescriptor profileTable =
    case profileTable of
        ProfileVenues -> descriptor "venues" "venues.csv" venueColumns venueRows
        ProfileUsers -> descriptor "users" "users.csv" userColumns userRows
        ProfilePasskeys -> descriptor "passkeys" "passkeys.csv" passkeyColumns passkeyRows
        ProfileVenueConfig -> descriptor "venue_config" "venue_config.csv" venueConfigColumns venueConfigRows
        ProfileVenueMemberships -> descriptor "venue_memberships" "venue_memberships.csv" venueMembershipColumns venueMembershipRows
        ProfileStaff -> descriptor "staff" "staff.csv" staffColumns staffRows
        ProfileShiftTypes -> descriptor "shift_types" "shift_types.csv" shiftTypeColumns shiftTypeRows
        ProfileDayNames -> descriptor "day_names" "day_names.csv" dayNameColumns dayNameRows
        ProfileStaffPayVersions -> descriptor "staff_pay_versions" "staff_pay_versions.csv" staffPayVersionColumns staffPayVersionRows
        ProfileShiftTypePayVersions -> descriptor "shift_type_pay_versions" "shift_type_pay_versions.csv" shiftTypePayVersionColumns shiftTypePayVersionRows
        ProfileRosterGroups -> descriptor "roster_groups" "roster_groups.csv" rosterGroupColumns rosterGroupRows
        ProfileSlotNames -> descriptor "slot_names" "slot_names.csv" slotNameColumns slotNameRows
        ProfileStaffRosterGroups -> descriptor "staff_roster_groups" "staff_roster_groups.csv" staffRosterGroupColumns staffRosterGroupRows
        ProfileStaffShiftPreferences -> descriptor "staff_shift_preferences" "staff_shift_preferences.csv" staffShiftPreferenceColumns staffShiftPreferenceRows
        ProfileRosterWeeks -> descriptor "roster_weeks" "roster_weeks.csv" rosterWeekColumns rosterWeekRows
        ProfileRosterDays -> descriptor "roster_days" "roster_days.csv" rosterDayColumns rosterDayRows
        ProfileRosterWeekSlotDefinitions -> descriptor "roster_week_slot_definitions" "roster_week_slot_definitions.csv" rosterWeekSlotDefinitionColumns rosterWeekSlotDefinitionRows
        ProfileRosterSlots -> descriptor "roster_slots" "roster_slots.csv" rosterSlotColumns rosterSlotRows
        ProfileLeaveRequests -> descriptor "leave_requests" "leave_requests.csv" leaveRequestColumns leaveRequestRows
        ProfileTimesheetEntries -> descriptor "timesheet_entries" "timesheet_entries.csv" timesheetEntryColumns timesheetEntryRows
        ProfileTimesheetEntryVersions -> descriptor "timesheet_entry_versions" "timesheet_entry_versions.csv" timesheetEntryVersionColumns timesheetEntryVersionRows
        ProfileXeroConnections -> descriptor "xero_connections" "xero_connections.csv" xeroConnectionColumns xeroConnectionRows
        ProfileXeroSyncRuns -> descriptor "xero_sync_runs" "xero_sync_runs.csv" xeroSyncRunColumns xeroSyncRunRows
        ProfileXeroEmployees -> descriptor "xero_employees" "xero_employees.csv" xeroEmployeeColumns xeroEmployeeRows
        ProfileXeroStaffMappings -> descriptor "xero_staff_mappings" "xero_staff_mappings.csv" xeroStaffMappingColumns xeroStaffMappingRows
    where
        descriptor descriptorTableName descriptorFileName descriptorColumns descriptorRows =
            ProfileTableDescriptor { descriptorTable = profileTable, .. }

validateProfileTableDescriptors :: ProfileSeedPlan -> [ProfileTableDescriptor] -> Either [ProfileTableValidationError] ()
validateProfileTableDescriptors plan descriptors = do
    validateProfileTableRegistry descriptors
    mapM_ (\descriptor -> validateProfileTableRows descriptor (descriptor.descriptorRows plan)) descriptors

validateProfileTableRegistry :: [ProfileTableDescriptor] -> Either [ProfileTableValidationError] ()
validateProfileTableRegistry descriptors =
    case errors of
        [] -> Right ()
        _  -> Left errors
    where
        descriptorTables = map (.descriptorTable) descriptors
        errors =
            map MissingProfileTable (filter (`notElem` descriptorTables) [minBound .. maxBound])
                <> map DuplicateProfileTable (duplicateValues descriptorTables)
                <> map DuplicateProfileTableName (duplicateValues (map (.descriptorTableName) descriptors))
                <> map DuplicateProfileFileName (duplicateValues (map (.descriptorFileName) descriptors))

validateProfileTableRows :: ProfileTableDescriptor -> [[Maybe Text]] -> Either [ProfileTableValidationError] ()
validateProfileTableRows descriptor rows =
    case errors of
        [] -> Right ()
        _  -> Left errors
    where
        expectedWidth = length descriptor.descriptorColumns
        errors =
            [ ProfileRowWidthMismatch descriptor.descriptorTable rowIndex expectedWidth (length values)
            | (rowIndex, values) <- zip [1 ..] rows
            , length values /= expectedWidth
            ]

duplicateValues :: Ord a => [a] -> [a]
duplicateValues = mapMaybe listToMaybe . filter ((> 1) . length) . List.group . List.sort

venueColumns, userColumns, passkeyColumns, venueConfigColumns, venueMembershipColumns, staffColumns :: [Text]
venueColumns = ["id", "name", "status"]
userColumns = ["id", "email", "password_hash", "user_role", "platform_role", "is_profile_completed", "email_verified_at", "failed_login_attempts", "locked_at"]
passkeyColumns = ["id", "user_id", "credential_id", "public_key", "sign_count", "name", "created_at", "last_used_at", "updated_at"]
venueConfigColumns = ["id", "venue_id", "timezone", "roster_week_starts_on", "week_offset_epoch", "late_to_early_min_start_gap_minutes", "staff_timesheet_edit_window_days"]
venueMembershipColumns = ["id", "venue_id", "user_id", "venue_role", "is_active"]
staffColumns = ["id", "venue_id", "user_id", "first_name", "last_name", "preferred_name", "phone", "emergency_contact_name", "emergency_contact_phone", "ideal_shifts_per_week", "is_active"]

shiftTypeColumns, dayNameColumns, staffPayVersionColumns, shiftTypePayVersionColumns :: [Text]
shiftTypeColumns = ["id", "venue_id", "name", "sort_order", "override_award_level_id", "is_active"]
dayNameColumns = ["id", "venue_id", "weekday_index", "name", "is_active"]
staffPayVersionColumns = ["id", "venue_id", "staff_id", "default_award_level_id", "employment_basis", "effective_from", "created_by_user_id", "locked_at", "locked_by_user_id"]
shiftTypePayVersionColumns = ["id", "venue_id", "shift_type_id", "override_award_level_id", "payroll_label", "effective_from", "created_by_user_id", "locked_at", "locked_by_user_id"]

rosterGroupColumns, slotNameColumns, staffRosterGroupColumns :: [Text]
rosterGroupColumns = ["id", "venue_id", "name", "sort_order", "is_active", "is_default"]
slotNameColumns = ["id", "venue_id", "roster_group_id", "name", "sort_order", "is_active"]
staffRosterGroupColumns = ["id", "staff_id", "roster_group_id"]

staffShiftPreferenceColumns, rosterWeekColumns, rosterDayColumns, rosterWeekSlotDefinitionColumns, rosterSlotColumns :: [Text]
staffShiftPreferenceColumns = ["id", "venue_id", "staff_id", "weekday_index", "preferred_start_hour", "preferred_end_hour"]
rosterWeekColumns = ["id", "venue_id", "roster_group_id", "week_offset", "is_live"]
rosterDayColumns = ["id", "roster_week_id", "day_offset", "is_closed"]
rosterWeekSlotDefinitionColumns = ["id", "roster_week_id", "name", "sort_order"]
rosterSlotColumns = ["id", "roster_day_id", "staff_id", "roster_week_slot_definition_id", "slot_sort_order", "row_index", "starts_at", "ends_at", "timezone"]

leaveRequestColumns, timesheetEntryColumns, timesheetEntryVersionColumns :: [Text]
leaveRequestColumns = ["id", "venue_id", "staff_id", "start_date", "end_date", "status", "notes"]
timesheetEntryColumns = ["id", "venue_id", "staff_id", "shift_type_id", "starts_at", "ends_at", "break_starts_at", "break_ends_at", "timezone", "staff_pay_version_id", "shift_type_pay_version_id", "is_approved", "approved_at", "approved_by_user_id"]
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

passkeyRows :: ProfileSeedPlan -> [[Maybe Text]]
passkeyRows plan =
    supportPasskey : map adminPasskey (venueIndexes plan)
    where
        supportPasskey =
            passkeyRow (uuidText 29 0 0 0) supportUserId "Profile support passkey"
        adminPasskey venueIndex =
            passkeyRow (uuidText 29 venueIndex 0 0) (adminUserId venueIndex) "Profile admin passkey"

passkeyRow :: Text -> Text -> Text -> [Maybe Text]
passkeyRow passkeyId userId passkeyName =
    row
        [ passkeyId
        , userId
        , byteaHex passkeyId
        , byteaHex (passkeyId <> passkeyId)
        , "0"
        , passkeyName
        , timestampText
        , nullText
        , timestampText
        ]

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


staffPayVersionRows :: ProfileSeedPlan -> [[Maybe Text]]
staffPayVersionRows plan =
    [ row [staffPayVersionId venueIndex staffIndex, venueId venueIndex, staffId venueIndex staffIndex, nullText, "permanent", dateText (weekStartForOffset (minimum (weekOffsets plan))), adminUserId venueIndex, timestampText, adminUserId venueIndex]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    ]

shiftTypePayVersionRows :: ProfileSeedPlan -> [[Maybe Text]]
shiftTypePayVersionRows plan =
    [ row [shiftTypePayVersionId venueIndex shiftIndex, venueId venueIndex, shiftTypeId venueIndex shiftIndex, nullText, shiftName, dateText (weekStartForOffset (minimum (weekOffsets plan))), adminUserId venueIndex, timestampText, adminUserId venueIndex]
    | venueIndex <- venueIndexes plan
    , (shiftIndex, shiftName, _) <- shiftTypeTemplates
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

staffShiftPreferenceRows :: ProfileSeedPlan -> [[Maybe Text]]
staffShiftPreferenceRows plan =
    [ row [uuidText 16 venueIndex staffIndex prefIndex, venueId venueIndex, staffId venueIndex staffIndex, tshow weekdayIndex, "5", "23"]
    | venueIndex <- venueIndexes plan
    , staffIndex <- staffIndexes plan
    , prefIndex <- [0 .. 4]
    , let weekdayIndex = (prefIndex + deterministicIndex plan [venueIndex, staffIndex, 9] 7) `mod` 7
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

rosterWeekSlotDefinitionRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterWeekSlotDefinitionRows plan =
    [ row [rosterWeekSlotDefinitionId venueIndex groupIndex weekOffset slotIndex, rosterWeekId venueIndex groupIndex weekOffset, slotName, tshow slotIndex]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , weekOffset <- weekOffsets plan
    , (slotIndex, slotName) <- slotNameTemplates
    ]

rosterSlotRows :: ProfileSeedPlan -> [[Maybe Text]]
rosterSlotRows plan =
    [ [ Just (rosterSlotId venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex)
      , Just (rosterDayId venueIndex groupIndex weekOffset dayOffset)
      , maybeStaffId
      , Just (rosterWeekSlotDefinitionId venueIndex groupIndex weekOffset slotIndex)
      , Just (tshow slotIndex)
      , Just (tshow rowIndex)
      , if isJust maybeStaffId then Just (instantText rosterDate startTime) else Nothing
      , if isJust maybeStaffId then Just (instantText rosterDate (addTimeMinutes startTime 360)) else Nothing
      , Just melbourneTimeZoneName
      ]
    | venueIndex <- venueIndexes plan
    , (groupIndex, _) <- rosterGroupTemplates
    , weekOffset <- weekOffsets plan
    , dayOffset <- [0 .. 6]
    , rowIndex <- [0 .. rowsPerDay plan.options - 1]
    , (slotIndex, _) <- slotNameTemplates
    , let maybeStaffId = assignedStaffId plan venueIndex groupIndex weekOffset dayOffset rowIndex slotIndex
    , let rosterDate = addDays (toInteger dayOffset) (weekStartForOffset weekOffset)
    , let startTime = timeFor slotIndex dayOffset
    ]

leaveRequestRows :: ProfileSeedPlan -> [[Maybe Text]]
leaveRequestRows plan =
    [ row
        [ uuidText 19 venueIndex staffIndex leaveIndex
        , venueId venueIndex
        , staffId venueIndex staffIndex
        , dateText startDate
        , dateText (addDays (toInteger (1 + leaveIndex `mod` 3)) startDate)
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
        , instantText workedOn (TimeOfDay 9 0 0)
        , instantText workedOn (TimeOfDay 17 0 0)
        , instantText workedOn (TimeOfDay 12 0 0)
        , instantText workedOn (TimeOfDay 12 30 0)
        , melbourneTimeZoneName
        , if isApproved then staffPayVersionId venueIndex staffIndex else nullText, if isApproved then shiftTypePayVersionId venueIndex (1 + deterministicIndex plan [venueIndex, staffIndex, weekOrdinal, 70] (length shiftTypeTemplates)) else nullText
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

weekOffsets :: ProfileSeedPlan -> [Int]
weekOffsets plan =
    [currentWeekOffset plan - weeksHistory plan.options + 1 .. currentWeekOffset plan + weeksFuture plan.options]


dateText :: Day -> Text
dateText = tshow

timeFor :: Int -> Int -> TimeOfDay
timeFor slotIndex dayOffset =
    case slotIndex of
        1 -> if even dayOffset then TimeOfDay 6 30 0 else TimeOfDay 7 0 0
        2 -> if even dayOffset then TimeOfDay 11 0 0 else TimeOfDay 11 30 0
        _ -> if even dayOffset then TimeOfDay 16 30 0 else TimeOfDay 17 0 0

addTimeMinutes :: TimeOfDay -> Int -> TimeOfDay
addTimeMinutes (TimeOfDay hour minute _) addedMinutes =
    let totalMinutes = hour * 60 + minute + addedMinutes
     in TimeOfDay (totalMinutes `div` 60) (totalMinutes `mod` 60) 0

instantText :: Day -> TimeOfDay -> Text
instantText day timeOfDay =
    either (error . ("Invalid profile-seed boundary: " <>) . show) tshow $
        resolveBoundaryInstant melbourneTimeZoneName day timeOfDay Nothing

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

byteaHex :: Text -> Text
byteaHex value =
    "\\x" <> Text.take 64 (Text.filter isHexDigit value <> Text.replicate 64 "0")
    where
        isHexDigit character =
            (character >= '0' && character <= '9')
                || (character >= 'a' && character <= 'f')
                || (character >= 'A' && character <= 'F')

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


shiftTypeId :: Int -> Int -> Text
shiftTypeId venueIndex shiftIndex = uuidText 7 venueIndex shiftIndex 0

dayNameId :: Int -> Int -> Text
dayNameId venueIndex weekdayIndex = uuidText 8 venueIndex weekdayIndex 0

staffPayVersionId :: Int -> Int -> Text
staffPayVersionId venueIndex staffIndex = uuidText 26 venueIndex staffIndex 0

shiftTypePayVersionId :: Int -> Int -> Text
shiftTypePayVersionId venueIndex shiftIndex = uuidText 27 venueIndex shiftIndex 0

rosterGroupId :: Int -> Int -> Text
rosterGroupId venueIndex groupIndex = uuidText 12 venueIndex groupIndex 0

slotNameId :: Int -> Int -> Int -> Text
slotNameId venueIndex groupIndex slotIndex = uuidText 13 venueIndex groupIndex slotIndex

rosterWeekId :: Int -> Int -> Int -> Text
rosterWeekId venueIndex groupIndex weekOffset = uuidText 17 venueIndex groupIndex (weekOffset + 10000)

rosterDayId :: Int -> Int -> Int -> Int -> Text
rosterDayId venueIndex groupIndex weekOffset dayOffset = uuidText 18 venueIndex groupIndex ((weekOffset + 10000) * 10 + dayOffset)

rosterWeekSlotDefinitionId :: Int -> Int -> Int -> Int -> Text
rosterWeekSlotDefinitionId venueIndex groupIndex weekOffset slotIndex =
    uuidText 28 venueIndex groupIndex (((weekOffset + 10000) * 10) + slotIndex)

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
