module Test.DevSeedSpec where

import Application.Fixture.DevFixtures
import Application.Fixture.Seed.Scenario
import Application.Helper.ShiftTypeColours (shiftTypeColourKeyCssValue)
import Application.PayAssignment (EffectivePayAssignment (..),
                                  ShiftPayAssignment (..),
                                  StaffPayAssignment (..), resolvePayAssignment)
import Control.Monad (void)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

data DevSeedOutcome = DevSeedOutcome
    { staffRows      :: ![(Text, Text, Maybe Text, Int)]
    , preferenceRows :: ![(Text, Text, Int, Int, Int)]
    , rosterRows     :: ![(Int, Int, Int, Int, Maybe (Text, Text), Maybe TimeOfDay, Maybe TimeOfDay, Maybe Text)]
    , leaveRows      :: ![(Day, Day, Text, Maybe Text)]
    , timesheetRows  :: ![(Day, TimeOfDay, TimeOfDay, Bool, Bool)]
    }
    deriving (Eq, Show)

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
        it "refreshes preloaded stale holiday provenance before approving seeded timesheets" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                void $ newRecord @PublicHoliday
                    |> set #jurisdiction ("VIC" :: Text)
                    |> set #holidayDate (fromGregorian 2025 1 1)
                    |> set #name ("New Year's Day" :: Text)
                    |> set #isRegional False
                    |> set #source (Just "DataVic")
                    |> set #importedAt (Just (addUTCTime (negate (46 * 86400)) now))
                    |> createRecord
                _ <- seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth defaultScenario defaultWeekEpoch defaultWeekEpoch
                pure ()

        it "can reseed when open-ended synthetic award rates already exist" $ withContext do
            withCleanDb do
                _ <- seedDevelopmentFixtureForWeek defaultWeekEpoch
                _ <- seedDevelopmentFixtureForWeek defaultWeekEpoch
                pure ()

        it "keeps the complete named scenario catalog stable" \_ -> do
            map scenarioContract [RealisticDemo, BusyRoster, ConflictHeavy, PayrollHeavy]
                `shouldBe`
                    [ ("realistic-demo", 16, 2, 1, 78, 15, 4, 2, 27, 12, 20260410)
                    , ("busy-roster", 20, 3, 1, 88, 15, 3, 1, 36, 15, 20260412)
                    , ("conflict-heavy", 14, 2, 1, 62, 15, 5, 3, 21, 15, 20260413)
                    , ("payroll-heavy", 18, 2, 1, 84, 15, 2, 1, 45, 9, 20260411)
                    ]

        it "seeds the complete realistic development fixture contract without deleting preloaded reference data" $ withContext do
            withCleanDb do
                referenceHoliday <- newRecord @PublicHoliday
                    |> set #jurisdiction ("VIC" :: Text)
                    |> set #holidayDate defaultWeekEpoch
                    |> set #name ("Preloaded dev reference holiday" :: Text)
                    |> set #isRegional False
                    |> createRecord
                fixture <- seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth defaultScenario defaultWeekEpoch defaultWeekEpoch
                preservedReferenceHoliday <- fetch referenceHoliday.id

                preservedReferenceHoliday.id `shouldBe` referenceHoliday.id
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
                sort
                    [ (user.email, tshow user.id)
                    | user <- seededUsers
                    , user.email `elem` ["admin@bepis.lol", "manager@bepis.lol", "owner@bepis.lol", "staff@bepis.lol", "venue@bepis.lol"]
                    ]
                    `shouldBe`
                        [ ("admin@bepis.lol", "a1642410-7297-46fd-916f-9d1ce464c388")
                        , ("manager@bepis.lol", "71ced305-dc24-414c-9471-e891468e0120")
                        , ("owner@bepis.lol", "7fe0607d-32aa-4a63-8a02-147b44987b43")
                        , ("staff@bepis.lol", "0342d268-4d58-4c11-b925-124db23b4758")
                        , ("venue@bepis.lol", "c3b1be9d-12de-49d1-9f21-e507af4c14ab")
                        ]
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
                        |> filterWhere (#status, LeaveRequestStatusEnumApproved)
                        |> fetchCount
                pendingLeaveCount <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#status, LeaveRequestStatusEnumPending)
                        |> fetchCount
                deniedLeaveCount <-
                    query @LeaveRequest
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#status, LeaveRequestStatusEnumDenied)
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
                activeSandboxMemberships <-
                    query @VenueMembership
                        |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
                        |> filterWhere (#isActive, True)
                        |> fetch
                let linkedSandboxUserIds = sort (mapMaybe (.userId) seededStaff)
                let activeMembershipUserIds = sort (map (.userId) activeSandboxMemberships)
                linkedSandboxUserIds `shouldSatisfy` all (`elem` activeMembershipUserIds)
                length activeMembershipUserIds `shouldBe` length (nub activeMembershipUserIds)
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

                -- Approved dev timesheets carry a complete deterministic synthetic
                -- rate authority, without pretending a provider award/classification
                -- sync envelope exists.

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
                fwcPayRateCount `shouldBe` 7
                fwcPenaltyRateCount `shouldBe` 7
                fwcWageAllowanceCount `shouldBe` 2
                awardLevelCount `shouldBe` 7
                awardLevelBaseRateCount `shouldBe` 14
                awardLevelPenaltyRateCount `shouldBe` 42
                awardTimePenaltyAllowanceCount `shouldBe` 2
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

                map (\shiftType -> (shiftType.name, shiftTypeColourKeyCssValue shiftType.colourKey, shiftType.payAssignmentMode, tshow <$> shiftType.overrideAwardLevelId, isJust shiftType.importedXeroPayItemId)) shiftTypes
                    `shouldBe` expectedSeedShiftTypesBySortOrder
                map (\version -> (version.payrollLabel, version.payAssignmentMode, tshow <$> version.overrideAwardLevelId, isJust version.importedXeroPayItemId)) shiftTypeVersions
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

                let staffById = Map.fromList [(unpackId staff.id, staff) | staff <- seededStaff]
                let shiftTypeById = Map.fromList [(unpackId shiftType.id, shiftType) | shiftType <- shiftTypes]
                let matrixAssignments =
                        [ (staff, shiftType)
                        | slot <- staffedRosterSlots
                        , staffId <- maybeToList slot.staffId
                        , shiftTypeId <- maybeToList slot.shiftTypeId
                        , staff <- maybeToList (Map.lookup staffId staffById)
                        , shiftType <- maybeToList (Map.lookup shiftTypeId shiftTypeById)
                        ]
                let seededPayModePairs =
                        Set.fromList [(staff.payAssignmentMode, shiftType.payAssignmentMode) | (staff, shiftType) <- matrixAssignments]
                let expectedPayModePairs =
                        Set.fromList
                            [ (staffMode, shiftMode)
                            | staffMode <- [AwardRate, XeroRate, RosterOnly]
                            , shiftMode <- [StaffDefault, AwardRate, XeroRate, RosterOnly]
                            ]
                expectedPayModePairs `Set.isSubsetOf` seededPayModePairs `shouldBe` True
                let matrixOutcomes =
                        [ resolvePayAssignment
                            (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)
                            (ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId)
                        | (staff, shiftType) <- matrixAssignments
                        , (staff.payAssignmentMode, shiftType.payAssignmentMode) `Set.member` expectedPayModePairs
                        ]
                matrixOutcomes `shouldSatisfy` all (\case InvalidPayAssignment {} -> False; _ -> True)
                let outcomeTag = \case
                        EffectiveAwardRate _ -> "award_rate" :: Text
                        EffectiveXeroRate _ -> "xero_rate"
                        EffectiveRosterOnly -> "roster_only"
                        InvalidPayAssignment {} -> "invalid"
                let resolvedModePairs =
                        Set.fromList
                            [ (staff.payAssignmentMode, shiftType.payAssignmentMode, outcomeTag (resolvePayAssignment
                                (StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId)
                                (ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId)))
                            | (staff, shiftType) <- matrixAssignments
                            ]
                let expectedResolvedModePairs =
                        Set.fromList
                            [ (AwardRate, StaffDefault, "award_rate")
                            , (AwardRate, AwardRate, "award_rate")
                            , (AwardRate, XeroRate, "xero_rate")
                            , (AwardRate, RosterOnly, "roster_only")
                            , (XeroRate, StaffDefault, "xero_rate")
                            , (XeroRate, AwardRate, "award_rate")
                            , (XeroRate, XeroRate, "xero_rate")
                            , (XeroRate, RosterOnly, "roster_only")
                            , (RosterOnly, StaffDefault, "roster_only")
                            , (RosterOnly, AwardRate, "roster_only")
                            , (RosterOnly, XeroRate, "roster_only")
                            , (RosterOnly, RosterOnly, "roster_only")
                            ]
                expectedResolvedModePairs `Set.isSubsetOf` resolvedModePairs `shouldBe` True
                map (.payAssignmentMode) seededStaff `shouldSatisfy` all (`elem` [AwardRate, XeroRate, RosterOnly, LegacyUnresolved])
                filter (isNothing . (.userId)) seededStaff `shouldSatisfy` all ((== RosterOnly) . (.payAssignmentMode))
                length (filter ((== LegacyUnresolved) . (.payAssignmentMode)) seededStaff) `shouldBe` 1

                -- Timesheets span the scenario window with realistic break coverage.
                let seededScenario = get #scenario fixture

                timesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> fetch
                xeroMatchedStaff <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhereIn (#lastName, ["Both", "Front", "Garrison", "Green", "Grey", "Lebron", "Martin"])
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
                let expectedApprovalTime = Just (UTCTime (addDays 6 defaultWeekEpoch) (secondsToDiffTime 3600))
                let xeroCalendarTimesheets =
                        filter
                            (\entry ->
                                entry.staffId `elem` xeroMatchedStaffIds
                                    && testWorkedOn entry >= fromGregorian 2026 4 29
                                    && testWorkedOn entry <= fromGregorian 2026 5 26
                            )
                            approvedTimesheets

                length approvedTimesheets `shouldBe` 56
                length xeroCalendarTimesheets `shouldBe` 56
                map (.approvedAt) approvedTimesheets `shouldSatisfy` all (== expectedApprovalTime)
                map (.staffPayVersionId) approvedTimesheets `shouldSatisfy` all isJust
                map (.shiftTypePayVersionId) approvedTimesheets `shouldSatisfy` all isJust
                map (.activePayCalculationId) approvedTimesheets `shouldSatisfy` all isJust
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

                characterizedOutcome <- captureDevSeedOutcome fixture
                take 12 characterizedOutcome.rosterRows
                    `shouldBe`
                        [ (-1, 0, 0, 0, Just ("Luca", "Pass"), Just (TimeOfDay 6 30 0), Just (TimeOfDay 12 0 0), Just "Cellar")
                        , (-1, 0, 0, 0, Just ("Willa", "Worker"), Just (TimeOfDay 6 30 0), Just (TimeOfDay 12 0 0), Just "Bar")
                        , (-1, 0, 0, 1, Just ("Bob", "Both"), Just (TimeOfDay 11 0 0), Just (TimeOfDay 16 30 0), Just "Runner")
                        , (-1, 0, 0, 1, Just ("Taylor", "Trial 1"), Just (TimeOfDay 11 0 0), Just (TimeOfDay 16 30 0), Just "Glassy")
                        , (-1, 0, 0, 2, Just ("Alice", "Front"), Just (TimeOfDay 16 30 0), Just (TimeOfDay 22 0 0), Just "Gaming")
                        , (-1, 0, 0, 2, Just ("Omar", "Floor"), Just (TimeOfDay 16 30 0), Just (TimeOfDay 22 0 0), Just "Functions")
                        , (-1, 0, 1, 2, Just ("Kira", "Cafe"), Just (TimeOfDay 16 30 0), Just (TimeOfDay 22 0 0), Just "Floor")
                        , (-1, 0, 1, 2, Just ("Tracy", "Green"), Just (TimeOfDay 16 30 0), Just (TimeOfDay 22 0 0), Just "Gaming")
                        , (-1, 1, 0, 0, Just ("Tracy", "Green"), Just (TimeOfDay 7 30 0), Just (TimeOfDay 13 0 0), Just "Door")
                        , (-1, 1, 0, 1, Just ("Morgan", "Manager"), Just (TimeOfDay 12 0 0), Just (TimeOfDay 17 30 0), Just "Floor")
                        , (-1, 1, 0, 2, Just ("Noah", "Dish"), Just (TimeOfDay 17 30 0), Just (TimeOfDay 23 0 0), Just "Supervisor")
                        , (-1, 1, 0, 2, Just ("Oliver", "Grey"), Just (TimeOfDay 17 30 0), Just (TimeOfDay 23 0 0), Just "Door")
                        ]

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
                        |> filterWhere (#venueRole, Manager)
                        |> fetchCount

                get #staffCount (get #scenario fixture) `shouldBe` 12
                get #managerCount (get #scenario fixture) `shouldBe` 2
                get #scenarioSeed (get #scenario fixture) `shouldBe` 12345
                seededStaffCount `shouldSatisfy` (>= 12)
                managerMembershipCount `shouldBe` 3

                firstOutcome <- captureDevSeedOutcome fixture
                repeatedFixture <- seedDevelopmentFixtureWithScenarioForWeek scenario defaultWeekEpoch
                repeatedOutcome <- captureDevSeedOutcome repeatedFixture
                repeatedOutcome `shouldBe` firstOutcome

captureDevSeedOutcome :: (?modelContext :: ModelContext) => DevSeedFixture -> IO DevSeedOutcome
captureDevSeedOutcome fixture = do
    staff <-
        query @Staff
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    preferences <-
        query @StaffShiftPreference
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    rosterWeeks <-
        query @RosterWeek
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    rosterDays <-
        query @RosterDay
            |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
            |> fetch
    rosterSlots <-
        query @RosterSlot
            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    leaveRequests <-
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    timesheets <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId fixture.sandboxVenue.id)
            |> fetch
    let staffById = Map.fromList [(unpackId row.id, (row.firstName, row.lastName)) | row <- staff]
    let rosterWeekById = Map.fromList [(unpackId row.id, row.weekOffset) | row <- rosterWeeks]
    let rosterDayById =
            Map.fromList
                [ (unpackId row.id, (Map.lookup row.rosterWeekId rosterWeekById, row.dayOffset))
                | row <- rosterDays
                ]
    let shiftTypeById = Map.fromList [(unpackId row.id, row.name) | row <- shiftTypes]
    pure
        DevSeedOutcome
            { staffRows =
                sort
                    [ (row.firstName, row.lastName, row.preferredName, row.idealShiftsPerWeek)
                    | row <- staff
                    ]
            , preferenceRows =
                sort
                    [ (firstName, lastName, row.weekdayIndex, row.preferredStartHour, row.preferredEndHour)
                    | row <- preferences
                    , Just (firstName, lastName) <- [Map.lookup row.staffId staffById]
                    ]
            , rosterRows =
                sort
                    [ ( weekOffset
                      , dayOffset
                      , row.rowIndex
                      , row.slotSortOrder
                      , row.staffId >>= (`Map.lookup` staffById)
                      , testStartTime row
                      , testEndTime row
                      , row.shiftTypeId >>= (`Map.lookup` shiftTypeById)
                      )
                    | row <- rosterSlots
                    , Just (Just weekOffset, dayOffset) <- [Map.lookup row.rosterDayId rosterDayById]
                    ]
            , leaveRows =
                sort
                    [ (row.startDate, row.endDate, inputValue row.status, row.notes)
                    | row <- leaveRequests
                    ]
            , timesheetRows =
                sort
                    [ (testWorkedOn row, testStartTime row, testEndTime row, testHadBreak row, row.isApproved)
                    | row <- timesheets
                    ]
            }

scenarioContract :: SeedScenarioName -> (Text, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)
scenarioContract scenarioName =
    let scenario = scenarioByName scenarioName
     in ( scenario.scenarioLabel
        , scenario.staffCount
        , scenario.managerCount
        , scenario.trialStaffCount
        , scenario.rosterFillPercent
        , scenario.leaveRequestCount
        , scenario.pendingLeaveCount
        , scenario.deniedLeaveCount
        , scenario.approvedTimesheets
        , scenario.pendingTimesheets
        , scenario.scenarioSeed
        )

expectedSeedShiftTypesBySortOrder :: [(Text, Text, PayAssignmentModeEnum, Maybe Text, Bool)]
expectedSeedShiftTypesBySortOrder =
    [ ("Floor", "palette-1", StaffDefault, Nothing, False)
    , ("Kitchen", "palette-2", AwardRate, Just kitchenAwardLevelIdText, False)
    , ("Bar", "", XeroRate, Nothing, True)
    , ("Gaming", "", RosterOnly, Nothing, False)
    , ("Glassy", "", AwardRate, Just floorAwardLevelIdText, False)
    , ("Cellar", "", AwardRate, Just floorAwardLevelIdText, False)
    , ("Functions", "", AwardRate, Just floorAwardLevelIdText, False)
    , ("Runner", "", AwardRate, Just floorAwardLevelIdText, False)
    , ("Door", "", AwardRate, Just kitchenAwardLevelIdText, False)
    , ("Supervisor", "", AwardRate, Just kitchenAwardLevelIdText, False)
    ]

expectedSeedShiftTypeVersionsByLabel :: [(Text, PayAssignmentModeEnum, Maybe Text, Bool)]
expectedSeedShiftTypeVersionsByLabel =
    sort (map (\(name, _colourKey, mode, awardLevelId, hasXero) -> (name, mode, awardLevelId, hasXero)) expectedSeedShiftTypesBySortOrder)

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
