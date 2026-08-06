module Test.ProfileSeedSpec where

import Application.Script.SeedProfile
import Data.Either (isLeft)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import IHP.Prelude
import Test.Hspec

smallOptions :: ProfileSeedOptions
smallOptions =
    defaultOptions
        { outputDir = "ignored"
        , venueCount = 1
        , staffPerVenue = 2
        , managerPerVenue = 1
        , weeksHistory = 1
        , weeksFuture = 1
        , rowsPerDay = 1
        , rosterFill = 50
        , seedValue = 42
        , xeroEmployees = 2
        , xeroMappedStaff = 1
        }

smallPlan :: ProfileSeedPlan
smallPlan = buildProfileSeedPlan smallOptions 9

tests :: Spec
tests = do
    describe "ProfileSeed planning" do
        it "keeps deterministic small-plan counts and rows" do
            counts smallPlan
                `shouldBe`
                    [ ("venues", 1)
                    , ("users", 4)
                    , ("staff", 3)
                    , ("staff_pay_versions", 2)
                    , ("shift_type_pay_versions", 3)
                    , ("roster_weeks", 4)
                    , ("roster_days", 28)
                    , ("roster_week_slot_definitions", 12)
                    , ("roster_slots", 84)
                    , ("timesheet_entries", 2)
                    , ("leave_requests", 6)
                    , ("xero_connections", 1)
                    , ("xero_employees", 2)
                    , ("xero_staff_mappings", 1)
                    ]
            venueRows smallPlan
                `shouldBe`
                    [ [ Just "000f4241-0000-4000-8001-000006052340"
                      , Just "Profile Venue 01"
                      , Just "active"
                      ]
                    ]

        it "keeps CSV null, quoting, comma, and newline bytes stable" do
            renderCsvRow [Nothing, Just "\\N", Just "comma, quote \" and\nnewline"]
                `shouldBe` "\\N,\\N,\"comma, quote \"\" and\nnewline\""

        it "matches every fixed small-plan CSV and complete manifest byte-for-byte" do
            forM_ profileTableDescriptors \descriptor -> do
                expected <- TextIO.readFile ("Test/Fixtures/profile-seed/" <> descriptor.descriptorFileName)
                let actual = Text.unlines (map renderCsvRow (descriptor.descriptorRows smallPlan))
                actual `shouldBe` expected
            expectedManifest <- TextIO.readFile "Test/Fixtures/profile-seed/manifest.json"
            renderProfileSeedManifest smallPlan `shouldBe` expectedManifest

    describe "ProfileSeed table manifest" do
        it "rejects omitted, duplicated, and width-mismatched descriptors" do
            validateProfileTableDescriptors smallPlan profileTableDescriptors `shouldBe` Right ()
            validateProfileTableDescriptors smallPlan (drop 1 profileTableDescriptors)
                `shouldBe` Left [MissingProfileTable ProfileVenues]
            let firstDescriptor = fromMaybe (error "missing profile table descriptors") (listToMaybe profileTableDescriptors)
            validateProfileTableDescriptors smallPlan (firstDescriptor : profileTableDescriptors)
                `shouldSatisfy` isLeft
            let malformedDescriptor = firstDescriptor { descriptorRows = const [[Just "too", Just "wide"]], descriptorColumns = ["one"] }
            validateProfileTableDescriptors smallPlan (malformedDescriptor : drop 1 profileTableDescriptors)
                `shouldBe` Left [ProfileRowWidthMismatch ProfileVenues 1 1 2]

    describe "ProfileSeed table load contract" do
        it "keeps every CSV file in canonical load order" do
            map (.descriptorFileName) profileTableDescriptors
                `shouldBe`
                    [ "venues.csv"
                    , "users.csv"
                    , "passkeys.csv"
                    , "venue_config.csv"
                    , "venue_memberships.csv"
                    , "staff.csv"
                    , "shift_types.csv"
                    , "day_names.csv"
                    , "staff_pay_versions.csv"
                    , "shift_type_pay_versions.csv"
                    , "roster_groups.csv"
                    , "slot_names.csv"
                    , "staff_roster_groups.csv"
                    , "staff_shift_preferences.csv"
                    , "roster_weeks.csv"
                    , "roster_days.csv"
                    , "roster_week_slot_definitions.csv"
                    , "roster_slots.csv"
                    , "leave_requests.csv"
                    , "timesheet_entries.csv"
                    , "timesheet_entry_versions.csv"
                    , "xero_connections.csv"
                    , "xero_sync_runs.csv"
                    , "xero_employees.csv"
                    , "xero_staff_mappings.csv"
                    ]

        it "keeps load SQL shape, escaping, and boundary statements stable" do
            let loadLines = Text.lines (renderLoadSql "/tmp/profile seed's")
            length loadLines `shouldBe` 36
            head loadLines `shouldBe` "BEGIN;"
            loadLines !! 1
                `shouldBe` "\\copy venues (id, name, status) FROM '/tmp/profile seed''s/venues.csv' WITH (FORMAT csv, NULL '\\N')"
            loadLines `shouldContain` ["CREATE TEMP TABLE profile_seed_timesheet_entries (LIKE timesheet_entries INCLUDING DEFAULTS);"]
            loadLines `shouldSatisfy` any (Text.isPrefixOf "UPDATE timesheet_pay_calculations calculation SET sealed_at")
            loadLines `shouldSatisfy` any (Text.isPrefixOf "UPDATE timesheet_entries entry SET active_pay_calculation_id")
            drop 34 loadLines `shouldBe` ["COMMIT;", "ANALYZE;"]

    describe "ProfileSeed application routes" do
        it "keeps typed-route target bytes stable" do
            rosterWeekPath 9 1 1
                `shouldBe` "/ShowRosterWeek?weekOffset=9&rosterGroupId=00b71b01-0001-4000-8002-00004795d228"
            rosterWeekContentFragmentPath 9 1 1
                `shouldBe` "/ShowRosterWeekContentFragment?weekOffset=9&rosterGroupId=00b71b01-0001-4000-8002-00004795d228"
            rosterWeekStaffPanelFragmentPath 9 1 1
                `shouldBe` "/ShowRosterWeekStaffPanelFragment?weekOffset=9&rosterGroupId=00b71b01-0001-4000-8002-00004795d228"
            rosterWeekOverviewFragmentPath 9 1 1
                `shouldBe` "/ShowRosterWeekOverviewFragment?weekOffset=9&rosterGroupId=00b71b01-0001-4000-8002-00004795d228"
            timesheetWeekPath 9
                `shouldBe` "/ShowTimesheetWeek?weekOffset=9"
            timesheetResetPath 9
                `shouldBe` "/Timesheets"
            timesheetStaffFilterPath 9 "004c4b41-0001-4000-8002-00001ddcab28"
                `shouldBe` "/ShowTimesheetWeek?weekOffset=9&staffFilterId=004c4b41-0001-4000-8002-00001ddcab28"
            timesheetDayFragmentPath 9 0
                `shouldBe` "/ShowTimesheetDaySectionFragment?weekOffset=9&dayOffset=0"
            profileLeaveSectionFragmentPath
                `shouldBe` "/ShowprofileContentLiveFragment?section=leave"
            adminInvitesFragmentPath 1 1
                `shouldBe` "/ShowadminInvitesLiveFragment?rosterGroupId=00b71b01-0001-4000-8002-00004795d228"

        it "keeps manifest account and static route strings stable" do
            let manifestLines = Text.lines (renderProfileSeedManifest smallPlan)
            let expectedLines =
                    [ "    \"primaryManager\": { \"email\": \"profile-staff-01-01@example.com\", \"password\": \"password123\", \"venueId\": \"000f4241-0000-4000-8001-000006052340\", \"staffId\": \"004c4b41-0001-4000-8002-00001ddcab28\" },"
                    , "    \"venueAdmin\": { \"email\": \"profile-manager-01@example.com\", \"password\": \"password123\", \"venueId\": \"000f4241-0000-4000-8001-000006052340\" },"
                    , "    \"support\": { \"email\": \"profile-support@example.com\", \"password\": \"password123\" }"
                    , "    \"leaveRequests\": \"/LeaveRequests\","
                    , "    \"leaveRequestsFragment\": \"/ShowleaveRequestsContentLiveFragment\","
                    , "    \"editProfile\": \"/EditProfile\","
                    , "    \"profileSecurity\": \"/EditProfile?section=security\","
                    , "    \"profileLeave\": \"/EditProfile?section=leave\","
                    , "    \"admin\": \"/Admin\","
                    , "    \"adminExports\": \"/Admin#exports\","
                    , "    \"adminShiftTypesFragment\": \"/ShowadminShiftTypesLiveFragment\","
                    , "    \"adminRosterGroupsFragment\": \"/ShowadminRosterGroupsLiveFragment\","
                    , "    \"xero\": \"/Xero\","
                    , "    \"adminXeroFragment\": \"/ShowadminXeroShellLiveFragment\""
                    ]
            expectedLines `shouldSatisfy` all (`elem` manifestLines)
