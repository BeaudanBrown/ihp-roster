module Test.DevSeedSpec where

import Application.Helper.Controller (unsafeEnumFromText)
import Application.Support.Seed.Scenario
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.DevFixtures

profileSummary :: Staff -> (Text, Text, Text, Text, Text)
profileSummary staff =
    ( staff.firstName
    , staff.lastName
    , staff.phone
    , staff.emergencyContactName
    , staff.emergencyContactPhone
    )

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Dev seed fixtures" do
        it "seeds the complete realistic development fixture contract" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

                rosterGroups <-
                    query @RosterGroup
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #sortOrder
                        |> fetch
                rosterWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#weekOffset, fixture.currentWeekOffset)
                        |> fetch
                allRosterWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #weekOffset
                        |> fetch
                rosterDays <-
                    query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
                        |> fetch
                rosterSlots <-
                    query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> fetch
                seededStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #firstName
                        |> fetch
                seededVenues <-
                    query @Venue
                        |> orderByAsc #name
                        |> fetch
                seededUsers <-
                    query @User
                        |> orderByAsc #email
                        |> fetch

                map (.name) rosterGroups `shouldBe` ["Front of House", "Back of House"]
                map (.name) seededVenues `shouldBe` ["Development Sandbox Venue"]
                map (.email) seededUsers `shouldContain` ["venue2@bepis.lol"]
                map (.email) seededUsers `shouldNotContain` ["beaudan.brown@gmail.com"]
                length rosterWeeks `shouldBe` 2
                map (.weekOffset) allRosterWeeks `shouldBe` concatMap (replicate 2) [fixture.currentWeekOffset - 1, fixture.currentWeekOffset, fixture.currentWeekOffset + 1]
                length rosterDays `shouldBe` 14
                length rosterSlots `shouldSatisfy` (> 30)
                sort (map (.isLive) rosterWeeks) `shouldBe` [False, True]
                length (filter (isJust . testStartTime) rosterSlots) `shouldSatisfy` (> 10)
                length (filter (isJust . testEndTime) rosterSlots) `shouldBe` length (filter (isJust . testStartTime) rosterSlots)
                sort (nub (map (.idealShiftsPerWeek) seededStaff)) `shouldBe` [0, 1, 2, 3, 4, 5]
                let seededStaffNames = map (\staff -> (staff.firstName, staff.lastName)) seededStaff
                let expectedSeededStaffNames =
                        [ ("James", "Lebron")
                        , ("Oliver", "Grey")
                        , ("Odette", "Garrison")
                        , ("Sally", "Martin")
                        , ("Sonia", "Michaels")
                        , ("Tracy", "Green")
                        ]
                expectedSeededStaffNames `shouldSatisfy` all (`elem` seededStaffNames)

                -- Every roster day retains enough staffed rows for realistic UI exercise.

                rosterWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#weekOffset, fixture.currentWeekOffset)
                        |> fetch
                rosterDays <-
                    query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
                        |> fetch
                rosterSlots <-
                    query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> fetch

                let staffedRowIndexesByDayId =
                        Map.fromListWith (<>)
                            [ (slot.rosterDayId, [slot.rowIndex])
                            | slot <- rosterSlots
                            , isJust slot.staffId
                            ]

                forM_ rosterDays \rosterDay -> do
                    let staffedRowCount =
                            staffedRowIndexesByDayId
                                |> Map.findWithDefault [] (unpackId (get #id rosterDay))
                                |> nub
                                |> length
                    staffedRowCount `shouldSatisfy` (>= 2)

                -- Staff applicability, leave states, and cross-group conflicts remain represented.

                bob <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#firstName, "Bob")
                        |> fetchOne
                leaveRequests <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #startDate
                        |> fetch
                bobAssignments <-
                    query @StaffRosterGroup
                        |> filterWhere (#staffId, unpackId (get #id bob))
                        |> fetch
                approvedLeaveCount <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#status, unsafeEnumFromText @LeaveRequestStatusEnum "approved")
                        |> fetchCount
                pendingLeaveCount <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#status, unsafeEnumFromText @LeaveRequestStatusEnum "pending")
                        |> fetchCount
                deniedLeaveCount <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#status, unsafeEnumFromText @LeaveRequestStatusEnum "denied")
                        |> fetchCount
                mondayWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#weekOffset, fixture.currentWeekOffset)
                        |> fetch
                mondayDays <-
                    query @RosterDay
                        |> filterWhere (#dayOffset, 0)
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) mondayWeeks)
                        |> fetch
                bobMondayAssignments <-
                    query @RosterSlot
                        |> filterWhere (#staffId, Just (unpackId (get #id bob)))
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) mondayDays)
                        |> fetch
                let leaveNotes =
                        mapMaybe (.notes) leaveRequests
                let seededScenario = get #scenario fixture
                let expectedApprovedLeaves = get #leaveRequestCount seededScenario - get #pendingLeaveCount seededScenario - get #deniedLeaveCount seededScenario
                let leaveWeekOffsets =
                        sort
                            (nub
                                [ testWeekOffsetForDay day
                                | leaveRequest <- leaveRequests
                                , day <- [leaveRequest.startDate, addDays (-1) leaveRequest.endDate]
                                ])

                map (.rosterGroupId) bobAssignments `shouldMatchList` [unpackId (get #id fixture.frontOfHouseGroup), unpackId (get #id fixture.backOfHouseGroup)]
                length leaveRequests `shouldBe` 15
                approvedLeaveCount `shouldBe` expectedApprovedLeaves
                pendingLeaveCount `shouldBe` get #pendingLeaveCount seededScenario
                deniedLeaveCount `shouldBe` get #deniedLeaveCount seededScenario
                leaveWeekOffsets `shouldSatisfy` all (`elem` [fixture.currentWeekOffset - 1, fixture.currentWeekOffset, fixture.currentWeekOffset + 1])
                [fixture.currentWeekOffset - 1, fixture.currentWeekOffset, fixture.currentWeekOffset + 1] `shouldSatisfy` all (`elem` leaveWeekOffsets)
                length leaveNotes `shouldBe` length leaveRequests
                leaveNotes `shouldSatisfy` all (not . Text.null)
                fmap (.startDate) (head leaveRequests) `shouldBe` Just (addDays (-7) defaultWeekEpoch)
                fmap (.startDate) (last leaveRequests) `shouldSatisfy` maybe False (>= addDays 12 defaultWeekEpoch)
                length bobMondayAssignments `shouldSatisfy` (>= 1)

                -- Support access, venue roles, and invitation bootstrap data remain represented.

                supportMemberships <-
                    query @VenueMembership
                        |> filterWhere (#userId, unpackId (get #id fixture.supportAdmin))
                        |> fetch
                managerMembership <-
                    query @VenueMembership
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#userId, unpackId (get #id fixture.sandboxManager))
                        |> fetchOne
                workerMembership <-
                    query @VenueMembership
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#userId, unpackId (get #id fixture.sandboxWorker))
                        |> fetchOne
                dummyUsers <-
                    query @User
                        |> filterWhereIn (#email, ["manager@bepis.lol", "owner@bepis.lol", "staff@bepis.lol", "venue@bepis.lol"])
                        |> fetch
                dummyMemberships <-
                    query @VenueMembership
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhereIn (#userId, map (unpackId . (.id)) dummyUsers)
                        |> fetch
                dummyStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhereIn (#userId, map (Just . unpackId . (.id)) dummyUsers)
                        |> fetch
                let dummyRoleByEmail =
                        Map.fromList
                            [ ( user.email
                              , membership.venueRole
                              )
                            | user <- dummyUsers
                            , membership <- dummyMemberships
                            , membership.userId == unpackId user.id
                            ]
                let dummyStaffByEmail =
                        Map.fromList
                            [ ( user.email
                              , staff
                              )
                            | user <- dummyUsers
                            , staff <- dummyStaff
                            , staff.userId == Just (unpackId user.id)
                            ]

                get #platformRole fixture.supportAdmin `shouldBe` Just SuperAdmin
                supportMemberships `shouldBe` []
                inputValue (get #venueRole managerMembership) `shouldBe` ("manager" :: Text)
                inputValue (get #venueRole workerMembership) `shouldBe` ("worker" :: Text)
                sort (map (.email) dummyUsers) `shouldBe` ["manager@bepis.lol", "owner@bepis.lol", "staff@bepis.lol", "venue@bepis.lol"]
                map (.isProfileCompleted) dummyUsers `shouldBe` replicate 4 True
                fmap inputValue (Map.lookup "staff@bepis.lol" dummyRoleByEmail) `shouldBe` Just ("worker" :: Text)
                fmap inputValue (Map.lookup "manager@bepis.lol" dummyRoleByEmail) `shouldBe` Just ("manager" :: Text)
                fmap inputValue (Map.lookup "venue@bepis.lol" dummyRoleByEmail) `shouldBe` Just ("venue_admin" :: Text)
                fmap inputValue (Map.lookup "owner@bepis.lol" dummyRoleByEmail) `shouldBe` Just ("venue_owner" :: Text)
                fmap profileSummary (Map.lookup "staff@bepis.lol" dummyStaffByEmail) `shouldBe` Just ("staff", "bepis", "0400000000", "Emergency Contact", "0411111111")
                fmap profileSummary (Map.lookup "manager@bepis.lol" dummyStaffByEmail) `shouldBe` Just ("manager", "bepis", "0400000000", "Emergency Contact", "0411111111")
                fmap profileSummary (Map.lookup "venue@bepis.lol" dummyStaffByEmail) `shouldBe` Just ("venue", "bepis", "0400000000", "Emergency Contact", "0411111111")
                fmap profileSummary (Map.lookup "owner@bepis.lol" dummyStaffByEmail) `shouldBe` Just ("owner", "bepis", "0400000000", "Emergency Contact", "0411111111")
                get #status fixture.sandboxInvitation `shouldBe` InvitationStatusEnumPending
                get #email fixture.sandboxInvitation `shouldBe` "pending-invite@example.com"

                -- Seed data must not fabricate synced FWC MAPD or award-rate rows.

                fwcAwardCount <- query @FwcMapdAward |> fetchCount
                fwcClassificationCount <- query @FwcMapdClassification |> fetchCount
                fwcPayRateCount <- query @FwcMapdPayRate |> fetchCount
                fwcPenaltyRateCount <- query @FwcMapdPenaltyRate |> fetchCount
                fwcWageAllowanceCount <- query @FwcMapdWageAllowance |> fetchCount
                awardLevelCount <- query @AwardLevel |> fetchCount
                awardLevelBaseRateCount <- query @AwardLevelBaseRate |> fetchCount
                awardLevelPenaltyRateCount <- query @AwardLevelPenaltyRate |> fetchCount
                awardTimePenaltyAllowanceCount <- query @AwardTimePenaltyAllowance |> fetchCount
                staffPayVersionCount <- query @StaffPayVersion |> fetchCount
                shiftTypePayVersionCount <- query @ShiftTypePayVersion |> fetchCount

                fwcAwardCount `shouldBe` 0
                fwcClassificationCount `shouldBe` 0
                fwcPayRateCount `shouldBe` 0
                fwcPenaltyRateCount `shouldBe` 0
                fwcWageAllowanceCount `shouldBe` 0
                awardLevelCount `shouldBe` 2
                awardLevelBaseRateCount `shouldBe` 0
                awardLevelPenaltyRateCount `shouldBe` 0
                awardTimePenaltyAllowanceCount `shouldBe` 0
                staffPayVersionCount `shouldSatisfy` (> 0)
                shiftTypePayVersionCount `shouldSatisfy` (> 0)

                -- Shift types stay mapped to the current hospitality award levels.

                shiftTypes <-
                    query @ShiftType
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #sortOrder
                        |> fetch
                shiftTypeVersions <-
                    query @ShiftTypePayVersion
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> orderByAsc #payrollLabel
                        |> fetch

                map (\shiftType -> (shiftType.name, shiftType.colourKey, tshow <$> shiftType.overrideAwardLevelId)) shiftTypes
                    `shouldBe` expectedSeedShiftTypesBySortOrder
                map (\version -> (version.payrollLabel, tshow <$> version.overrideAwardLevelId)) shiftTypeVersions
                    `shouldBe` expectedSeedShiftTypeVersionsByLabel

                rosterWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#weekOffset, fixture.currentWeekOffset)
                        |> fetch
                rosterDays <-
                    query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
                        |> fetch
                rosterSlots <-
                    query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> fetch
                let staffedRosterSlots = filter (isJust . (.staffId)) rosterSlots
                let seededShiftTypeIds = map (unpackId . (.id)) shiftTypes
                let assignedShiftTypeIds = mapMaybe (.shiftTypeId) staffedRosterSlots

                length staffedRosterSlots `shouldSatisfy` (> 0)
                assignedShiftTypeIds `shouldSatisfy` all (`elem` seededShiftTypeIds)
                length assignedShiftTypeIds `shouldBe` length staffedRosterSlots
                length (nub assignedShiftTypeIds) `shouldSatisfy` (> 2)

                -- Timesheets span the scenario window with realistic break coverage.
                let seededScenario = get #scenario fixture

                timesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                xeroMatchedStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhereIn (#lastName, ["Both", "Front", "Garrison", "Grey", "Lebron", "Martin"])
                        |> fetch

                let totalTimesheetCount = length timesheetEntries
                let entriesWithBreaks = length (filter testHadBreak timesheetEntries)
                let scenarioTimesheetCount = seededScenario.approvedTimesheets + seededScenario.pendingTimesheets
                let requiredBreakCount = ceiling ((fromIntegral scenarioTimesheetCount :: Double) * 0.8)
                let timesheetWeekOffsets = sort (nub (map (testWeekOffsetForDay . testWorkedOn) timesheetEntries))
                let xeroMatchedStaffIds = map (unpackId . (.id)) xeroMatchedStaff
                let approvedTimesheets = filter (.isApproved) timesheetEntries
                let pendingTimesheetCount = length timesheetEntries - length approvedTimesheets
                let xeroMatchedApprovedCount = length (filter (\entry -> entry.staffId `elem` xeroMatchedStaffIds) approvedTimesheets)
                let otherApprovedCount = length approvedTimesheets - xeroMatchedApprovedCount

                length approvedTimesheets `shouldSatisfy` (>= seededScenario.approvedTimesheets)
                pendingTimesheetCount `shouldBe` seededScenario.pendingTimesheets
                totalTimesheetCount `shouldBe` (length approvedTimesheets + seededScenario.pendingTimesheets)
                entriesWithBreaks `shouldSatisfy` (>= requiredBreakCount)
                timesheetWeekOffsets `shouldSatisfy` \offsets ->
                    all (`elem` offsets) [fixture.currentWeekOffset - 1, fixture.currentWeekOffset, fixture.currentWeekOffset + 1]
                xeroMatchedApprovedCount `shouldSatisfy` (> otherApprovedCount)

                -- Staff preferences include realistic names and recurring availability.

                seededStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                shiftPreferences <-
                    query @StaffShiftPreference
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                linkedUsers <-
                    query @User
                        |> filterWhereIn (#id, nub (mapMaybe (fmap Id . (.userId)) seededStaff))
                        |> fetch
                let firstNames = map (.firstName) seededStaff
                let duplicateFirstNames = map head (filter (\names -> length names > 1) (group (sort firstNames)))
                let staffIds = sort (map (unpackId . (.id)) seededStaff)
                let preferenceStaffIds = sort (nub (map (.staffId) shiftPreferences))
                let linkedUserEmailById = Map.fromList (map (\user -> (unpackId user.id, user.email)) linkedUsers)
                let exemptPreferenceEmails =
                        [ "venue2@bepis.lol"
                        , "admin@bepis.lol"
                        , "staff@bepis.lol"
                        , "manager@bepis.lol"
                        , "venue@bepis.lol"
                        , "owner@bepis.lol"
                        ]
                let expectedPreferenceStaffIds =
                        sort
                            [ unpackId staff.id
                            | staff <- seededStaff
                            , maybe True (`notElem` exemptPreferenceEmails) (staff.userId >>= (`Map.lookup` linkedUserEmailById))
                            ]
                let preferredWeekdays = nub (map (.weekdayIndex) shiftPreferences)

                preferenceStaffIds `shouldBe` expectedPreferenceStaffIds
                preferenceStaffIds `shouldSatisfy` all (`elem` staffIds)
                length shiftPreferences `shouldSatisfy` (>= length expectedPreferenceStaffIds)
                length preferredWeekdays `shouldSatisfy` (>= 4)
                duplicateFirstNames `shouldContain` ["Alice"]
                length (filter (isJust . (.preferredName)) seededStaff) `shouldSatisfy` (> 0)

                -- Most assigned shifts align with recurring day preferences.

                rosterWeeks <-
                    query @RosterWeek
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#weekOffset, fixture.currentWeekOffset)
                        |> fetch
                rosterDays <-
                    query @RosterDay
                        |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
                        |> fetch
                assignedSlots <-
                    query @RosterSlot
                        |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
                        |> fetch
                shiftPreferences <-
                    query @StaffShiftPreference
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                let assignedSlotsWithStaff = filter (isJust . (.staffId)) assignedSlots

                let rosterDayContextById =
                        Map.fromList
                            (map
                                (\rosterDay -> (unpackId rosterDay.id, rosterDay.dayOffset))
                                rosterDays
                            )
                let preferenceKeys =
                        map
                            (\preference -> (preference.staffId, preference.weekdayIndex))
                            shiftPreferences
                let assignedPreferenceKeys =
                        mapMaybe
                            (\slot -> do
                                staffId <- slot.staffId
                                dayOffset <- Map.lookup slot.rosterDayId rosterDayContextById
                                pure (staffId, weekdayIndexForDayOffset dayOffset)
                            )
                            assignedSlotsWithStaff
                let matchedAssignedCount = length (filter (`elem` preferenceKeys) assignedPreferenceKeys)
                let requiredPreferredCount = ceiling ((fromIntegral (length assignedPreferenceKeys) :: Double) * 0.8)

                length assignedPreferenceKeys `shouldSatisfy` (> 0)
                matchedAssignedCount `shouldSatisfy` (>= requiredPreferredCount)

        it "supports deterministic scenario overrides for realistic demo seeding" $ withContext do
            withCleanDb do
                let scenario =
                        applyOverrides
                            defaultScenarioOverrides
                                { overrideStaffCount = Just 12
                                , overrideManagerCount = Just 2
                                , overrideRosterFill = Just 65
                                , overrideScenarioSeed = Just 12345
                                }
                            defaultScenario
                fixture <- seedDevelopmentFixtureWithScenarioForWeek scenario defaultWeekEpoch

                seededStaffCount <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetchCount
                managerMembershipCount <-
                    query @VenueMembership
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#venueRole, unsafeEnumFromText @VenueRoleEnum "manager")
                        |> fetchCount

                get #staffCount (get #scenario fixture) `shouldBe` 12
                get #managerCount (get #scenario fixture) `shouldBe` 2
                get #scenarioSeed (get #scenario fixture) `shouldBe` 12345
                seededStaffCount `shouldSatisfy` (>= 12)
                managerMembershipCount `shouldBe` 3

expectedSeedShiftTypesBySortOrder :: [(Text, Text, Maybe Text)]
expectedSeedShiftTypesBySortOrder =
    [ ("Floor", "palette-1", Just floorAwardLevelIdText)
    , ("Kitchen", "palette-2", Just kitchenAwardLevelIdText)
    , ("Bar", "", Just floorAwardLevelIdText)
    , ("Gaming", "", Just floorAwardLevelIdText)
    , ("Glassy", "", Just floorAwardLevelIdText)
    , ("Cellar", "", Just floorAwardLevelIdText)
    , ("Functions", "", Just floorAwardLevelIdText)
    , ("Runner", "", Just floorAwardLevelIdText)
    , ("Door", "", Just kitchenAwardLevelIdText)
    , ("Supervisor", "", Just kitchenAwardLevelIdText)
    ]

expectedSeedShiftTypeVersionsByLabel :: [(Text, Maybe Text)]
expectedSeedShiftTypeVersionsByLabel =
    sort (map (\(name, _colourKey, awardLevelId) -> (name, awardLevelId)) expectedSeedShiftTypesBySortOrder)

floorAwardLevelIdText :: Text
floorAwardLevelIdText = "2cba4998-4691-4eeb-9bd3-e79263c54769"

kitchenAwardLevelIdText :: Text
kitchenAwardLevelIdText = "8a53b7c8-574c-49f8-abd4-0caf3b46a22f"

weekdayIndexForDayOffset :: Int -> Int
weekdayIndexForDayOffset dayOffset =
    case (dayOffset + 1) `mod` 7 of
        0     -> 0
        index -> index

testWeekOffsetForDay :: Day -> Int
testWeekOffsetForDay day =
    fromInteger (diffDays day defaultWeekEpoch `div` 7)
