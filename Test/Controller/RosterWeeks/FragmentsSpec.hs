module Test.Controller.RosterWeeks.FragmentsSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Config
import qualified Data.ByteString.Char8 as ByteString
import Data.Maybe (fromJust)
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.RosterWeeks.Dom (rosterContentFragmentId, rosterDaySectionDomId,
                            rosterRowDomIdText, rosterStaffPanelFragmentId)
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "RosterWeeksController" do
        it "returns fragment refresh instructions when a slot assignment changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-update@example.com" "staff" True
                staffUserA <- createUserRecord "roster-staff-a@example.com" "staff" True
                staffUserB <- createUserRecord "roster-staff-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUserA "worker"
                _ <- createVenueMembershipRecord venue staffUserB "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffA <- createStaffRecord venue (Just staffUserA) "Alpha" "Crew"
                staffB <- createStaffRecord venue (Just staffUserB) "Bravo" "Crew"
                _ <- updateRecord (staffA |> set #idealShiftsPerWeek 5)
                _ <- updateRecord (staffB |> set #idealShiftsPerWeek 7)
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffA) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", ByteString.pack (cs (tshow staffB.id)))]

                response `responseStatusShouldBe` status200

                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldBe` ""

                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                let contentTarget = cs rosterContentFragmentId :: String
                let staffPanelTarget = cs rosterStaffPanelFragmentId :: String
                let updatedRowTarget = cs (rosterRowDomIdText rosterDay.id 0) :: String
                fromJust triggerHeader `shouldContain` "app-roster-fragments-refresh"
                fromJust triggerHeader `shouldContain` contentTarget
                fromJust triggerHeader `shouldContain` staffPanelTarget
                fromJust triggerHeader `shouldContain` updatedRowTarget
                fromJust triggerHeader `shouldContain` "ShowRosterWeekContentFragment"
                fromJust triggerHeader `shouldContain` "ShowRosterWeekStaffPanelFragment"
                fromJust triggerHeader `shouldContain` "ShowRosterWeekRowFragment"
                fromJust triggerHeader `shouldContain` ("\"targetId\":\"" <> contentTarget <> "\"")
                fromJust triggerHeader `shouldContain` ("\"targetId\":\"" <> updatedRowTarget <> "\"")
                fromJust triggerHeader `shouldContain` "\"deferUntilBlur\":true"
                fromJust triggerHeader `shouldContain` "\"deferUntilBlur\":false"

        it "does not include rows from other weeks when refreshing related assignment rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-update-current-week@example.com" "staff" True
                staffUserA <- createUserRecord "roster-staff-current-week-a@example.com" "staff" True
                staffUserB <- createUserRecord "roster-staff-current-week-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUserA "worker"
                _ <- createVenueMembershipRecord venue staffUserB "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffA <- createStaffRecord venue (Just staffUserA) "Alpha" "Crew"
                staffB <- createStaffRecord venue (Just staffUserB) "Bravo" "Crew"
                currentWeek <- createRosterWeekRecord venue 0 False
                currentDay <- createRosterDayRecord currentWeek 0
                currentSlot <- createRosterSlotRecord currentDay slotName (Just staffA) 0
                relatedCurrentSlot <- createRosterSlotRecord currentDay slotName (Just staffA) 1
                otherWeek <- createRosterWeekRecord venue 1 False
                otherDay <- createRosterDayRecord otherWeek 0
                _ <- createRosterSlotRecord otherDay slotName (Just staffA) 2

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction currentSlot.id) [("staffId", ByteString.pack (cs (tshow staffB.id)))]

                response `responseStatusShouldBe` status200
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                let editedRowTarget = cs (rosterRowDomIdText currentDay.id 0) :: String
                let relatedCurrentRowTarget = cs (rosterRowDomIdText currentDay.id 1) :: String
                let otherWeekRowTarget = cs (rosterRowDomIdText otherDay.id 2) :: String
                fromJust triggerHeader `shouldContain` editedRowTarget
                fromJust triggerHeader `shouldContain` relatedCurrentRowTarget
                fromJust triggerHeader `shouldNotContain` otherWeekRowTarget

        it "keeps selected staff labels plain when ideal-shift filters hide them" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-plain-labels@example.com" "staff" True
                staffUser <- createUserRecord "roster-staff-plain-labels@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just staffUser) "Alpha" "Crew"
                _ <- updateRecord (staffMember |> set #idealShiftsPerWeek 1)
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffAtIdealShifts", "true")]
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "selected=\"selected\">Alpha</option>"
                response `responseBodyShouldNotContain` "ideal reached"

        it "hides staff with no preferred shifts on that day when the unavailable filter is active" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-unavailable-filter@example.com" "staff" True
                selectedUser <- createUserRecord "roster-selected-sunday@example.com" "staff" True
                unavailableUser <- createUserRecord "roster-unavailable-sunday@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue selectedUser "worker"
                _ <- createVenueMembershipRecord venue unavailableUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                selectedStaff <- createStaffRecord venue (Just selectedUser) "Selected" "Crew"
                unavailableStaff <- createStaffRecord venue (Just unavailableUser) "Unavailable" "Crew"
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId unavailableStaff.id)
                        |> set #weekdayIndex 2
                        |> set #preferredStartHour 9
                        |> set #preferredEndHour 17
                        |> createRecord
                rosterWeek <- createRosterWeekRecord venue 0 False
                mondayRosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord mondayRosterDay slotName (Just selectedStaff) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffUnavailable", "true")]
                    callAction (ShowRosterWeekRowFragmentAction 0 mondayRosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "selected=\"selected\">Selected</option>"
                response `responseBodyShouldNotContain` ">Unavailable</option>"

        it "counts global shift preferences across roster groups" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-cross-group-preference@example.com" "staff" True
                staffUser <- createUserRecord "roster-cross-group-preference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                frontSlotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                staffMember <- createStaffRecord venue (Just staffUser) "CrossGroup" "Preference"
                _ <- createStaffRosterGroupRecord staffMember frontOfHouse
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staffMember.id)
                        |> set #weekdayIndex 1
                        |> set #preferredStartHour 9
                        |> set #preferredEndHour 17
                        |> createRecord
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                mondayRosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord mondayRosterDay frontSlotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffUnavailable", "true")]
                    callAction (ShowRosterWeekRowFragmentAction 0 mondayRosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">CrossGroup</option>"

        it "only hides staff for approved leave overlapping the roster week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-leave-filter@example.com" "staff" True
                overlapUser <- createUserRecord "roster-overlap-leave@example.com" "staff" True
                pendingUser <- createUserRecord "roster-pending-leave@example.com" "staff" True
                endedUser <- createUserRecord "roster-ended-leave@example.com" "staff" True
                futureUser <- createUserRecord "roster-future-leave@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue overlapUser "worker"
                _ <- createVenueMembershipRecord venue pendingUser "worker"
                _ <- createVenueMembershipRecord venue endedUser "worker"
                _ <- createVenueMembershipRecord venue futureUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                overlappingStaff <- createStaffRecord venue (Just overlapUser) "Approved" "Overlap"
                pendingStaff <- createStaffRecord venue (Just pendingUser) "Pending" "Leave"
                endedStaff <- createStaffRecord venue (Just endedUser) "Ended" "Before"
                futureStaff <- createStaffRecord venue (Just futureUser) "Future" "After"
                _ <- createLeaveRequestRecord venue overlappingStaff (addDays (-1) defaultWeekEpoch) (addDays 1 defaultWeekEpoch) "approved"
                _ <- createLeaveRequestRecord venue pendingStaff defaultWeekEpoch (addDays 1 defaultWeekEpoch) "pending"
                _ <- createLeaveRequestRecord venue endedStaff (addDays (-2) defaultWeekEpoch) defaultWeekEpoch "approved"
                _ <- createLeaveRequestRecord venue futureStaff (addDays 7 defaultWeekEpoch) (addDays 8 defaultWeekEpoch) "approved"
                rosterWeek <- createRosterWeekRecord venue 0 False
                mondayRosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord mondayRosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffOnApprovedLeave", "true")]
                    callAction (ShowRosterWeekRowFragmentAction 0 mondayRosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` ">Approved</option>"
                response `responseBodyShouldContain` ">Pending</option>"
                response `responseBodyShouldContain` ">Ended</option>"
                response `responseBodyShouldContain` ">Future</option>"

        it "renders unique roster field keys for each editable control in a multi-slot row fragment" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-field-keys@example.com" "staff" True
                staffUser <- createUserRecord "roster-staff-field-keys@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                staffMember <- createStaffRecord venue (Just staffUser) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                firstSlot <- createRosterSlotRecord rosterDay early (Just staffMember) 0
                secondSlot <- createRosterSlotRecord rosterDay late Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow firstSlot.id) <> ":startTime\"")
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow firstSlot.id) <> ":staffId\"")
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow firstSlot.id) <> ":note\"")
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow secondSlot.id) <> ":startTime\"")
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow secondSlot.id) <> ":staffId\"")
                bodyText `shouldContain` ("data-roster-field-key=\"" <> cs (tshow secondSlot.id) <> ":note\"")

        it "allows assigning staff who are applicable to the slot's roster group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-assign@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-group-assign@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                slotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                _ <- createStaffRosterGroupRecord alpha frontOfHouse
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", ByteString.pack (cs (tshow alpha.id)))]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch slot.id
                updatedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "rejects adding rows to a live week via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-add-row@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (AddRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Live roster weeks are read-only. Move it back to draft to make changes."
                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> fetch
                length slotsForDay `shouldBe` 1

        it "rejects updating slot assignments on a live week via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-update@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-live-update@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-live-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", ByteString.pack (cs (tshow bravo.id)))]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Live roster weeks are read-only. Move it back to draft to make changes."
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "rejects overlong slot flags via HTMX and leaves the saved value unchanged" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-flag-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName Nothing 0 >>= updateRecord . set #note (Just "OP")

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterSlotAction slot.id) [("note", "LONG")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Flags can only be 1 or 2 characters."
                unchangedSlot <- fetch slot.id
                unchangedSlot.note `shouldBe` Just "OP"

        it "normalizes slot flags to uppercase when saved" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-flag-uppercase@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) [("note", "pm")]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch slot.id
                updatedSlot.note `shouldBe` Just "PM"

        it "rejects assigning staff who are not applicable to the slot's roster group via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-reject-htmx@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-group-reject-htmx@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-group-reject-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                slotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                syncStaffRosterGroupAssignments alpha [frontOfHouse.id]
                syncStaffRosterGroupAssignments bravo [backOfHouse.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", ByteString.pack (cs (tshow bravo.id)))]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "That staff member is not applicable to this roster group."
                rejectedSlot <- fetch slot.id
                rejectedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "redirects with an error when a non-HTMX slot update tries to assign ineligible staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-reject@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-group-reject@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-group-reject@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                slotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                syncStaffRosterGroupAssignments alpha [frontOfHouse.id]
                syncStaffRosterGroupAssignments bravo [backOfHouse.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", ByteString.pack (cs (tshow bravo.id)))]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just (cs ("http://localhost/ShowRosterWeek?weekOffset=0&rosterGroupId=" <> tshow frontOfHouse.id))
                rejectedSlot <- fetch slot.id
                rejectedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "allows clearing a slot assignment even when the previously assigned staff is no longer applicable" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-clear@example.com" "staff" True
                alphaUser <- createUserRecord "roster-alpha-group-clear@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                slotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                syncStaffRosterGroupAssignments alpha [backOfHouse.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just alpha) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) [("staffId", "")]

                response `responseStatusShouldBe` status200
                clearedSlot <- fetch slot.id
                clearedSlot.staffId `shouldBe` Nothing

        it "row fragment endpoint renders duplicate conflicts after a duplicate assignment is created" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-duplicate@example.com" "staff" True
                staffUser <- createUserRecord "roster-staff-duplicate@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just staffUser) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                firstSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                secondSlot <- createRosterSlotRecord rosterDay slotName Nothing 1
                _ <- updateRecord (firstSlot |> set #startTime (Just (timeOfDay 9 0)))
                _ <- updateRecord (secondSlot |> set #startTime (Just (timeOfDay 13 0)))

                _ <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction secondSlot.id) [("staffId", ByteString.pack (cs (tshow staffMember.id)))]

                firstRowResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                secondRowResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 1)

                firstRowResponse `responseStatusShouldBe` status200
                secondRowResponse `responseStatusShouldBe` status200

                firstRowBody <- responseBody firstRowResponse
                secondRowBody <- responseBody secondRowResponse
                let firstRowText = cs firstRowBody :: String
                let secondRowText = cs secondRowBody :: String
                firstRowText `shouldContain` "conflict-critical"
                secondRowText `shouldContain` "conflict-critical"
                firstRowText `shouldContain` "data-conflict-message="
                secondRowText `shouldContain` "data-conflict-message="

        it "defers roster month overview loading to an HTMX fragment" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-overview-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-overview-fragment-mount=\"true\""
                response `responseBodyShouldContain` "hx-get=\"/ShowRosterWeekOverviewFragment?weekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldNotContain` "data-week-overview-day=\"true\""

        it "month overview fragment includes other weeks in the same month and counts assigned shifts rather than unique staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-overview@example.com" "staff" True
                workerUser <- createUserRecord "roster-worker-overview@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just workerUser) "Alpha" "Crew"

                currentWeek <- createRosterWeekRecord venue 0 False
                currentWeekDay <- createRosterDayRecord currentWeek 0
                _ <- createRosterSlotRecord currentWeekDay slotName (Just staffMember) 0

                nextWeek <- createRosterWeekRecord venue 1 False
                nextWeekDay <- createRosterDayRecord nextWeek 0
                nextWeekSlotA <- createRosterSlotRecord nextWeekDay slotName (Just staffMember) 0
                nextWeekSlotB <- createRosterSlotRecord nextWeekDay slotName (Just staffMember) 1
                _ <- updateRecord (nextWeekSlotA |> set #durationMinutes (Just 240))
                _ <- updateRecord (nextWeekSlotB |> set #durationMinutes (Just 240))
                _ <- createLeaveRequestRecord venue staffMember (addDays 7 defaultWeekEpoch) (addDays 8 defaultWeekEpoch) "pending"
                _ <- createLeaveRequestRecord venue staffMember (addDays 7 defaultWeekEpoch) (addDays 8 defaultWeekEpoch) "denied"
                _ <- createLeaveRequestRecord venue staffMember (addDays 40 defaultWeekEpoch) (addDays 41 defaultWeekEpoch) "approved"
                _ <- createLeaveRequestRecord venue staffMember (addDays (-6) defaultWeekEpoch) (addDays (-4) defaultWeekEpoch) "approved"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekOverviewFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-overview-loaded=\"true\""
                response `responseBodyShouldContain` "data-week-overview-date=\"2025-01-13\""
                response `responseBodyShouldContain` "data-week-overview-assigned=\"2\""
                response `responseBodyShouldContain` "data-week-overview-hours=\"8h\""
                response `responseBodyShouldContain` "data-week-overview-leave=\"1\""
                response `responseBodyShouldNotContain` "data-week-overview-leave=\"2\""
                response `responseBodyShouldContain` "data-week-overview-date=\"2025-01-01\""
                response `responseBodyShouldContain` "weekDate=2025-01-13"

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
