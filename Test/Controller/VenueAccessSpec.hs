{-# LANGUAGE TypeApplications #-}

module Test.Controller.VenueAccessSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      currentVenueSessionKey)
import Config
import qualified Data.ByteString.Char8 as BS
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.Admin ()
import Web.Controller.LeaveRequests ()
import Web.Controller.RosterWeeks ()
import Web.Controller.Sessions ()
import Web.Controller.Staff ()
import Web.Controller.Support ()
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "Venue-scoped access control" do
        it "denies editing a staff record from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-a@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                foreignStaff <- createStaffRecord venueB Nothing "Brie" "Foreign"

                response <- withUser manager do
                    callActionWithParams (EditStaffAction foreignStaff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status403

        it "denies approving a timesheet entry from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-timesheet@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                foreignStaff <- createStaffRecord venueB Nothing "Tia" "Outside"
                foreignEntry <- createTimesheetEntryRecord venueB foreignStaff defaultWeekEpoch

                response <- withUser manager do
                    callAction ApproveTimesheetEntryAction { timesheetEntryId = foreignEntry.id }

                response `responseStatusShouldBe` status403

        it "denies approving a leave request from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-leave@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                foreignStaff <- createStaffRecord venueB Nothing "Lea" "Outside"
                foreignLeave <- createLeaveRequestRecord venueB foreignStaff defaultWeekEpoch (fromGregorian 2025 1 8) "pending"

                response <- withUser manager do
                    callAction ApproveLeaveRequestAction { leaveRequestId = foreignLeave.id }

                response `responseStatusShouldBe` status403

        it "denies toggling a roster week from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-roster@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                foreignWeek <- createRosterWeekRecord venueB 0 False

                response <- withUser manager do
                    callAction ToggleRosterWeekLiveStatusAction { rosterWeekId = foreignWeek.id }

                response `responseStatusShouldBe` status403

        it "denies updating a roster slot from another venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-slot@example.com" "admin" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                foreignWeek <- createRosterWeekRecord venueB 0 False
                foreignDay <- createRosterDayRecord foreignWeek 0
                foreignSlotName <- fetchSlotNameRecord venueB "Late"
                foreignSlot <- createRosterSlotRecord foreignDay foreignSlotName Nothing 0

                response <- withUser manager do
                    callActionWithParams (UpdateRosterSlotAction foreignSlot.id) [("note", "Denied")]

                response `responseStatusShouldBe` status403

    describe "Venue membership authority" do
        it "does not let users.user_role bypass admin access checks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUser user do
                    callAction AdminAction

                response `responseStatusShouldBe` status403

        it "does not let users.user_role bypass manager-only roster actions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "worker-manager-bypass@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "worker"
                rosterWeek <- createRosterWeekRecord venue 0 False

                response <- withUser user do
                    callAction ToggleRosterWeekLiveStatusAction { rosterWeekId = rosterWeek.id }

                response `responseStatusShouldBe` status403

        it "lets super-admin bypass venue membership for admin screens in another active venue" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                supportVenue <- createVenueWithConfig "Support Venue"
                founder <- createUserRecordWithPlatformRole "founder-support@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord homeVenue founder "venue_owner"

                response <- withUserAndCurrentVenue founder supportVenue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Schedule Groups"

        it "denies the support page to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUser admin do
                    callAction SupportAction

                response `responseStatusShouldBe` status403

        it "lets super-admin open the support page and see active venues" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-support-page@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord venueA founder "venue_owner"

                response <- withUser founder do
                    callAction SupportAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Switch Venue"
                response `responseBodyShouldContain` "Create Venue"
                response `responseBodyShouldContain` "Alpha Venue"
                response `responseBodyShouldContain` "Beta Venue"

        it "lets super-admin create a bootstrapped venue without creating an invitation" $ withContext do
            withCleanDb do
                homeVenue <- createVenueWithConfig "Home Venue"
                founder <- createUserRecordWithPlatformRole "founder-create-venue@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord homeVenue founder "venue_owner"

                response <- withUser founder do
                    callActionWithParams CreateSupportVenueAction
                        [ ("name", "Fresh Venue")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldSatisfy` maybe False ("createdVenueId=" `BS.isInfixOf`)

                venue <- query @Venue |> filterWhere (#name, "Fresh Venue") |> fetchOne
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                slotCount <- query @SlotName |> filterWhere (#rosterGroupId, unpackId rosterGroup.id) |> fetchCount
                invitationCount <- query @VenueInvitation |> filterWhere (#venueId, unpackId venue.id) |> fetchCount
                auditEvent <- query @AuditEvent |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                venueConfig.timezone `shouldBe` "Australia/Melbourne"
                slotCount `shouldBe` 3
                invitationCount `shouldBe` 0
                auditEvent.eventType `shouldBe` "venue_bootstrapped"
                auditEvent.targetTable `shouldBe` "venues"
                auditEvent.targetId `shouldBe` unpackId venue.id

        it "denies venue creation to ordinary venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "venue-admin-create@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withUser admin do
                    callActionWithParams CreateSupportVenueAction
                        [ ("name", "Blocked Venue")
                        ]

                response `responseStatusShouldBe` status403
                venueCount <- query @Venue |> filterWhere (#name, "Blocked Venue") |> fetchCount
                venueCount `shouldBe` 0

    describe "Current venue selection" do
        it "stores the earliest active membership venue during beforeLogin" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-login@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user "worker"
                _ <- createVenueMembershipRecord venueB user "worker"

                selectedVenueId <- withControllerTestContext do
                    Sessions.beforeLogin @User user
                    getSession @(Id Venue) currentVenueSessionKey

                selectedVenueId `shouldBe` Just venueA.id

        it "stores the requested active venue during beforeLogin for a super-admin without memberships" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-login@example.com" "staff" (Just SuperAdminRole) True

                selectedVenueId <- withControllerTestContext do
                    Sessions.beforeLogin @User founder
                    getSession @(Id Venue) currentVenueSessionKey

                selectedVenueId `shouldBe` Just venueA.id

        it "uses the earliest active membership when no current venue session exists" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-request@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user "manager"
                _ <- createVenueMembershipRecord venueB user "manager"
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) "pending"
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) "pending"

                response <- withUser user do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Alpha Person"
                response `responseBodyShouldNotContain` "Beta Person"

        it "honors the current venue session when resolving request context" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                user <- createUserRecord "multi-session@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA user "manager"
                _ <- createVenueMembershipRecord venueB user "manager"
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) "pending"
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) "pending"

                response <- withUserAndCurrentVenue user venueB.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Beta Person"
                response `responseBodyShouldNotContain` "Alpha Person"

        it "allows the support switch action for super-admin and redirects back to support" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord venueA founder "venue_owner"

                response <- withUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "/LeaveRequests")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/LeaveRequests"

        it "falls back to support when given an unsafe redirect target" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-switch-unsafe@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord venueA founder "venue_owner"

                response <- withUserAndCurrentVenue founder venueA.id do
                    callActionWithParams SwitchSupportVenueAction
                        [ ("venueId", cs (tshow venueB.id))
                        , ("next", "https://evil.example.com/")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/Support"

        it "honors a foreign current venue session for super-admin without requiring a membership" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Alpha Venue"
                venueB <- createVenueWithConfig "Beta Venue"
                founder <- createUserRecordWithPlatformRole "founder-session@example.com" "staff" (Just SuperAdminRole) True
                _ <- createVenueMembershipRecord venueA founder "venue_owner"
                staffA <- createStaffRecord venueA Nothing "Alpha" "Person"
                staffB <- createStaffRecord venueB Nothing "Beta" "Person"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) "pending"
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) "pending"

                response <- withUserAndCurrentVenue founder venueB.id do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Beta Person"
                response `responseBodyShouldNotContain` "Alpha Person"

    describe "Venue-scoped manager queries" do
        it "shows only current-venue leave requests on the leave requests page" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-leave-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                staffA <- createStaffRecord venueA Nothing "Ava" "Leave"
                staffB <- createStaffRecord venueB Nothing "Bea" "Leave"
                _ <- createLeaveRequestRecord venueA staffA defaultWeekEpoch (fromGregorian 2025 1 8) "pending"
                _ <- createLeaveRequestRecord venueB staffB defaultWeekEpoch (fromGregorian 2025 1 8) "pending"

                response <- withUser manager do
                    callAction LeaveRequestsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Leave"
                response `responseBodyShouldNotContain` "Bea Leave"

        it "shows only current-venue timesheet entries on the weekly timesheets page" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-timesheet-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                staffA <- createStaffRecord venueA Nothing "Ava" "Hours"
                staffB <- createStaffRecord venueB Nothing "Bea" "Hours"
                _ <- createTimesheetEntryRecord venueA staffA defaultWeekEpoch
                _ <- createTimesheetEntryRecord venueB staffB defaultWeekEpoch

                response <- withUser manager do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Hours"
                response `responseBodyShouldNotContain` "Bea Hours"

        it "shows only current-venue staff in the roster staff panel" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-roster-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                _ <- createVenueMembershipRecord venueB manager "manager"
                _ <- createRosterWeekRecord venueA 0 False
                _ <- createRosterWeekRecord venueB 0 False
                linkedUserA <- createUserRecord "alpha-staff@example.com" "staff" True
                linkedUserB <- createUserRecord "beta-staff@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA linkedUserA "worker"
                _ <- createVenueMembershipRecord venueB linkedUserB "worker"
                _ <- createStaffRecord venueA (Just linkedUserA) "Alpha" "Crew"
                _ <- createStaffRecord venueB (Just linkedUserB) "Beta" "Crew"

                response <- withUser manager do
                    callAction ShowRosterWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldNotContain` "data-roster-staff-name=\"Beta\""

        it "uses only current-venue slot names when creating a roster week" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                manager <- createUserRecord "manager-slot-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA manager "manager"
                slotNamesA <- forM ["Early", "Mid", "Late"] (fetchSlotNameRecord venueA)
                slotNamesB <- forM ["Early", "Mid", "Late"] (fetchSlotNameRecord venueB)

                response <- withUser manager do
                    callAction CreateRosterWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status302

                rosterWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venueA.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetchOne
                rosterDays <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> fetch
                slots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . get #id) rosterDays)
                    |> fetch

                let venueASlotIds = map (unpackId . get #id) slotNamesA
                let venueBSlotIds = map (unpackId . get #id) slotNamesB

                length slots `shouldBe` 84
                map (.slotNameId) slots `shouldSatisfy` all (`elem` venueASlotIds)
                map (.slotNameId) slots `shouldSatisfy` all (`notElem` venueBSlotIds)
