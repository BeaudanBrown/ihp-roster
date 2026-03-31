module Test.DevSeedSpec where

import Application.Helper.Controller (unsafeEnumFromText)
import Data.List (sort)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.DevFixtures
import Test.Support.PayrollFixtures (ExplorationPayrollFixture (..))

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

                map (.name) rosterGroups `shouldBe` ["Front of House", "Back of House"]
                length rosterWeeks `shouldBe` 2
                length rosterDays `shouldBe` 14
                length rosterSlots `shouldSatisfy` (> 30)
                sort (map (.isLive) rosterWeeks) `shouldBe` [False, True]

        it "seeds staff applicability, approved leave, pending leave, and cross-group conflicts" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch

                bob <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId (get #id fixture.sandboxVenue))
                        |> filterWhere (#firstName, "Bob")
                        |> fetchOne
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

                map (.rosterGroupId) bobAssignments `shouldMatchList` [unpackId (get #id fixture.frontOfHouseGroup), unpackId (get #id fixture.backOfHouseGroup)]
                approvedLeaveCount `shouldBe` 1
                pendingLeaveCount `shouldBe` 1
                deniedLeaveCount `shouldBe` 1
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

                get #platformRole fixture.supportAdmin `shouldBe` Just SuperAdmin
                supportMemberships `shouldBe` []
                inputValue (get #venueRole managerMembership) `shouldBe` ("manager" :: Text)
                inputValue (get #venueRole workerMembership) `shouldBe` ("worker" :: Text)
                get #status fixture.sandboxInvitation `shouldBe` InvitationStatusEnumPending
                get #email fixture.sandboxInvitation `shouldBe` "pending-invite@example.com"

        it "also seeds the payroll parity venue for current-week export testing" $ withContext do
            withCleanDb do
                fixture <- seedDevelopmentFixtureForWeek defaultWeekEpoch
                let ExplorationPayrollFixture { explorationVenue = payrollVenue } = fixture.payrollFixture

                payLevels <-
                    query @PayLevel
                        |> filterWhere (#venueId, unpackId (get #id payrollVenue))
                        |> fetch
                shiftTypes <-
                    query @ShiftType
                        |> filterWhere (#venueId, unpackId (get #id payrollVenue))
                        |> fetch
                snapshots <-
                    query @PayConfigSnapshot
                        |> filterWhere (#venueId, unpackId (get #id payrollVenue))
                        |> fetch
                approvedCount <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId (get #id payrollVenue))
                        |> filterWhere (#isApproved, True)
                        |> fetchCount
                pendingCount <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId (get #id payrollVenue))
                        |> filterWhere (#isApproved, False)
                        |> fetchCount

                map (.name) payLevels `shouldMatchList` ["LVL 1", "LVL 2", "LVL 3"]
                map (.name) shiftTypes `shouldMatchList` ["Bar", "Floor", "Kitchen"]
                length snapshots `shouldBe` 1
                approvedCount `shouldSatisfy` (> pendingCount)
