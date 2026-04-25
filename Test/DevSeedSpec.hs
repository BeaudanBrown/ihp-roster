module Test.DevSeedSpec where

import Application.Helper.Controller (unsafeEnumFromText)
import Application.Support.Seed.Scenario
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian, toGregorian)
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
tests = beforeAll testContext do
    describe "Dev seed fixtures" do
        it "seeds a busy current-week sandbox venue with multiple roster groups" $ withContext do
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
                map (.email) seededUsers `shouldContain` ["beaudan.brown@gmail.com"]
                length rosterWeeks `shouldBe` 2
                length rosterDays `shouldBe` 14
                length rosterSlots `shouldSatisfy` (> 30)
                sort (map (.isLive) rosterWeeks) `shouldBe` [False, True]
                length (filter (isJust . (.startTime)) rosterSlots) `shouldSatisfy` (> 10)
                length (filter (isJust . (.note)) rosterSlots) `shouldSatisfy` (> 10)
                let noteLengths = map Text.length (mapMaybe (.note) rosterSlots)
                noteLengths `shouldSatisfy` (all (<= 2))
                sort (nub (map (.idealShiftsPerWeek) seededStaff)) `shouldBe` [0, 1, 2, 3, 4, 5]

        it "seeds at least two staffed roster rows for every roster day" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

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

        it "seeds staff applicability, approved leave, pending leave, and cross-group conflicts" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

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
                let (fixtureYear, fixtureMonthNumber, _) = toGregorian defaultWeekEpoch
                let fixtureMonth = (fixtureYear, fixtureMonthNumber)
                let fixtureMonthStart = fromGregorian fixtureYear fixtureMonthNumber 1
                let leaveMonths = map (\leaveRequest -> (\(year, month, _) -> (year, month)) (toGregorian leaveRequest.startDate)) leaveRequests

                map (.rosterGroupId) bobAssignments `shouldMatchList` [unpackId (get #id fixture.frontOfHouseGroup), unpackId (get #id fixture.backOfHouseGroup)]
                length leaveRequests `shouldBe` 15
                approvedLeaveCount `shouldBe` expectedApprovedLeaves
                pendingLeaveCount `shouldBe` get #pendingLeaveCount seededScenario
                deniedLeaveCount `shouldBe` get #deniedLeaveCount seededScenario
                leaveMonths `shouldSatisfy` all (== fixtureMonth)
                length leaveNotes `shouldBe` length leaveRequests
                leaveNotes `shouldSatisfy` all (not . Text.null)
                fmap (.startDate) (head leaveRequests) `shouldBe` Just fixtureMonthStart
                fmap (.startDate) (last leaveRequests) `shouldSatisfy` maybe False (>= addDays 27 fixtureMonthStart)
                length bobMondayAssignments `shouldBe` 2

        it "seeds support access, venue roles, and invitation bootstrap data" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

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

        it "does not seed synthetic FWC MAPD or award-level pay data" $ withContext do
            withCleanDb do
                _ <- seedDevelopmentFixtureForWeek defaultWeekEpoch

                fwcAwardCount <- query @FwcMapdAward |> fetchCount
                fwcClassificationCount <- query @FwcMapdClassification |> fetchCount
                fwcPayRateCount <- query @FwcMapdPayRate |> fetchCount
                fwcPenaltyRateCount <- query @FwcMapdPenaltyRate |> fetchCount
                fwcWageAllowanceCount <- query @FwcMapdWageAllowance |> fetchCount
                awardLevelCount <- query @AwardLevel |> fetchCount
                awardLevelBaseRateCount <- query @AwardLevelBaseRate |> fetchCount
                awardLevelPenaltyRateCount <- query @AwardLevelPenaltyRate |> fetchCount
                awardTimePenaltyAllowanceCount <- query @AwardTimePenaltyAllowance |> fetchCount
                payConfigSnapshotCount <- query @PayConfigSnapshot |> fetchCount

                fwcAwardCount `shouldBe` 0
                fwcClassificationCount `shouldBe` 0
                fwcPayRateCount `shouldBe` 0
                fwcPenaltyRateCount `shouldBe` 0
                fwcWageAllowanceCount `shouldBe` 0
                awardLevelCount `shouldBe` 0
                awardLevelBaseRateCount `shouldBe` 0
                awardLevelPenaltyRateCount `shouldBe` 0
                awardTimePenaltyAllowanceCount `shouldBe` 0
                payConfigSnapshotCount `shouldBe` 0

        it "seeds three times as many sandbox timesheets with break coverage on most entries" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch
                let seededScenario = get #scenario fixture

                timesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch

                let totalTimesheetCount = length timesheetEntries
                let entriesWithBreaks = length (filter (.hadBreak) timesheetEntries)
                let requiredBreakCount = ceiling ((fromIntegral totalTimesheetCount :: Double) * 0.8)

                totalTimesheetCount `shouldBe` (seededScenario.approvedTimesheets + seededScenario.pendingTimesheets)
                entriesWithBreaks `shouldSatisfy` (>= requiredBreakCount)

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

        it "seeds recurring availability, per-staff roster day preferences, duplicate first names, and some preferred names" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

                seededStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                availabilities <-
                    query @StaffAvailability
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
                        [ "beaudan.brown@gmail.com"
                        , "dev-admin@example.com"
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

                length availabilities `shouldSatisfy` (> 5)
                preferenceStaffIds `shouldBe` expectedPreferenceStaffIds
                preferenceStaffIds `shouldSatisfy` all (`elem` staffIds)
                length shiftPreferences `shouldSatisfy` (>= length expectedPreferenceStaffIds)
                length preferredWeekdays `shouldSatisfy` (>= 4)
                duplicateFirstNames `shouldContain` ["Alice"]
                length (filter (isJust . (.preferredName)) seededStaff) `shouldSatisfy` (> 0)

        it "keeps at least 80 percent of seeded assigned shifts aligned with recurring slot preferences" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

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

                let rosterGroupByWeekId = Map.fromList (map (\week -> (unpackId week.id, week.rosterGroupId)) rosterWeeks)
                let rosterDayContextById =
                        Map.fromList
                            (mapMaybe
                                (\rosterDay -> do
                                    rosterGroupId <- Map.lookup rosterDay.rosterWeekId rosterGroupByWeekId
                                    pure (unpackId rosterDay.id, (rosterDay.dayOffset, rosterGroupId))
                                )
                                rosterDays
                            )
                let preferenceKeys =
                        map
                            (\preference -> (preference.staffId, preference.rosterGroupId, preference.weekdayIndex, preference.slotNameId))
                            shiftPreferences
                let assignedPreferenceKeys =
                        mapMaybe
                            (\slot -> do
                                staffId <- slot.staffId
                                (dayOffset, rosterGroupId) <- Map.lookup slot.rosterDayId rosterDayContextById
                                pure (staffId, rosterGroupId, weekdayIndexForDayOffset dayOffset, slot.slotNameId)
                            )
                            assignedSlotsWithStaff
                let matchedAssignedCount = length (filter (`elem` preferenceKeys) assignedPreferenceKeys)
                let requiredPreferredCount = ceiling ((fromIntegral (length assignedPreferenceKeys) :: Double) * 0.8)

                length assignedPreferenceKeys `shouldSatisfy` (> 0)
                matchedAssignedCount `shouldSatisfy` (>= requiredPreferredCount)

weekdayIndexForDayOffset :: Int -> Int
weekdayIndexForDayOffset dayOffset =
    case (dayOffset + 1) `mod` 7 of
        0     -> 0
        index -> index
