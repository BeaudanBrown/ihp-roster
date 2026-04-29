module Test.Controller.RosterWeeksSpec where

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
        it "redirects unauthenticated users from RosterWeeksAction" $ withContext do
            response <- callAction RosterWeeksAction
            response `responseStatusShouldBe` status302

        it "redirects venue-less super-admins from roster weeks to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "roster-bootstrap-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUser user do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "redirects unauthenticated users from ShowRosterWeekAction" $ withContext do
            response <- callAction (ShowRosterWeekAction 0)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from ShowRosterWeekContentFragmentAction" $ withContext do
            response <- callAction (ShowRosterWeekContentFragmentAction 0)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from ShowRosterWeekStaffPanelFragmentAction" $ withContext do
            response <- callAction (ShowRosterWeekStaffPanelFragmentAction 0)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from ShowRosterWeekRowFragmentAction" $ withContext do
            response <- callAction (ShowRosterWeekRowFragmentAction 0 "11111111-1111-1111-1111-111111111111" 0)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from CreateRosterWeekAction" $ withContext do
            response <- callAction (CreateRosterWeekAction 0)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from CopyRosterWeekAction" $ withContext do
            response <- callAction (CopyRosterWeekAction 0 1)
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from ToggleRosterDayClosedAction" $ withContext do
            response <- callAction (ToggleRosterDayClosedAction "11111111-1111-1111-1111-111111111111")
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from AddRosterRowAction" $ withContext do
            response <- callAction (AddRosterRowAction "11111111-1111-1111-1111-111111111111")
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from RemoveRosterRowAction" $ withContext do
            response <- callAction (RemoveRosterRowAction "11111111-1111-1111-1111-111111111111")
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from UpdateRosterSlotAction" $ withContext do
            response <- callAction (UpdateRosterSlotAction "22222222-2222-2222-2222-222222222222")
            response `responseStatusShouldBe` status302

        it "redirects venue members without a completed staff profile to edit profile" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-needs-profile@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/EditProfile")]

        it "visiting a missing week auto-creates an empty draft roster" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-auto-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                slotNames <- query @SlotName
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetch

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                createdWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetchOne
                createdWeek.isLive `shouldBe` False
                createdDays <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId createdWeek.id)
                    |> fetch
                length createdDays `shouldBe` 7
                createdSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) createdDays)
                    |> fetch
                length createdSlots `shouldBe` (7 * 4 * length slotNames)

        it "staff cannot see draft weeks but still gets the roster shell" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-draft@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- fetchSlotNameRecord venue "Early"
                _ <- createRosterWeekRecord venue 0 False

                response <- withUser user do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-grid"
                response `responseBodyShouldNotContain` "Crew, Alpha"

        it "empty roster pages still expose declarative live-update surface metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-empty-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-surface=\""
                response `responseBodyShouldContain` "roster_week"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "weekOffset"
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldNotContain` "ihp-auto-refresh-id"

        it "staff on hidden draft pages still expose declarative live-update surface metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-hidden-draft-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-surface=\""
                response `responseBodyShouldContain` "roster_week"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "weekOffset"

        it "manager can see draft weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser manager do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Alpha</option>"
                response `responseBodyShouldContain` "hx-post=\"/ToggleRosterWeekLiveStatus?rosterWeekId="
                response `responseBodyShouldContain` ">Live</label>"

        it "does not render conflict highlights on live roster weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-no-conflicts@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <-
                    createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                        >>= updateRecord . set #startTime (Just (TimeOfDay 8 0 0))
                _ <- createLeaveRequestRecord venue staffMember defaultWeekEpoch (addDays 1 defaultWeekEpoch) "approved"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "conflict-critical"
                response `responseBodyShouldNotContain` "Staff member is on approved leave."

        it "manager roster pages render reusable week controls in the header" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-week-controls=\"manager-actions\""
                response `responseBodyShouldContain` "hx-post=\"/CopyRosterWeek?sourceWeekOffset=-1&amp;targetWeekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldContain` "hx-confirm=\"This will overwrite the current week with the previous week's roster. Continue?\""
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "roster-live-toggle-"

        it "roster group switcher preserves weekOffset in the submitted form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-switcher@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 3)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "action=\"/ShowRosterWeek?weekOffset=3\""
                response `responseBodyShouldContain` "type=\"hidden\" name=\"weekOffset\" value=\"3\""
                response `responseBodyShouldContain` "name=\"rosterGroupId\""

        it "always renders separate day-name and date rows even when a day only has one roster row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-day-labels@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-day-label-row-primary"
                response `responseBodyShouldContain` "roster-day-label-row-controls"
                response `responseBodyShouldContain` cs (rosterRowDomIdText rosterDay.id 1)

        it "manager can mark a draft roster day closed via HTMX without deleting existing slot content" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-close-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #note (Just "OP"))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterDayClosedAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldBe` ""

                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                fromJust triggerHeader `shouldContain` "app-live-fragments-refresh"
                fromJust triggerHeader `shouldContain` "app-roster-fragments-refresh"
                fromJust triggerHeader `shouldContain` (cs (rosterDaySectionDomId rosterDay.id) :: String)
                fromJust triggerHeader `shouldContain` (cs rosterStaffPanelFragmentId :: String)
                fromJust triggerHeader `shouldContain` "ShowRosterWeekDaySectionFragment"
                fromJust triggerHeader `shouldContain` "ShowRosterWeekStaffPanelFragment"

                updatedDay <- fetch rosterDay.id
                updatedDay.isClosed `shouldBe` True
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                unchangedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                unchangedSlot.note `shouldBe` Just "OP"

        it "closed roster days stay locked at two rows and reject row additions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-closed-day-add@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (AddRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Closed days stay locked at two blank rows until reopened."

        it "manager can create a draft week via HTMX without redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-create-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CreateRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week created successfully"

        it "manager can add a row to an auto-created draft week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-add-row@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotNames <- query @SlotName
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isActive, True)
                    |> fetch

                _ <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                rosterWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetchOne
                rosterDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (AddRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldBe` ""

                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                fromJust triggerHeader `shouldContain` "app-roster-fragments-refresh"
                fromJust triggerHeader `shouldContain` (cs (rosterDaySectionDomId rosterDay.id) :: String)
                fromJust triggerHeader `shouldContain` (cs rosterStaffPanelFragmentId :: String)
                fromJust triggerHeader `shouldContain` "ShowRosterWeekDaySectionFragment"
                fromJust triggerHeader `shouldContain` "ShowRosterWeekStaffPanelFragment"

                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> orderByAsc #rowIndex
                    |> fetch
                let slotCount = length slotNames
                length slotsForDay `shouldBe` (5 * slotCount)
                map (.rowIndex) slotsForDay `shouldBe` concatMap (replicate slotCount) [0, 1, 2, 3, 4]
                map (.slotNameId) slotsForDay `shouldMatchList` map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames

        it "manager can remove the last roster row via a day-section refresh" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-remove-row-patch@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 0
                _ <- createRosterSlotRecord rosterDay slotName Nothing 1
                _ <- createRosterSlotRecord rosterDay slotName Nothing 2

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (RemoveRosterRowAction rosterDay.id)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldBe` ""

                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                fromJust triggerHeader `shouldContain` "app-roster-fragments-refresh"
                fromJust triggerHeader `shouldContain` (cs (rosterDaySectionDomId rosterDay.id) :: String)
                fromJust triggerHeader `shouldContain` (cs rosterStaffPanelFragmentId :: String)
                fromJust triggerHeader `shouldContain` "ShowRosterWeekDaySectionFragment"
                fromJust triggerHeader `shouldContain` "ShowRosterWeekStaffPanelFragment"

                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                map (.rowIndex) slotsForDay `shouldMatchList` [0, 1]

        it "syncs a draft week to the current slot template only when explicitly requested" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-sync-slots@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                early <- fetchSlotNameRecord venue "Early"
                mid <- fetchSlotNameRecord venue "Mid"
                late <- fetchSlotNameRecord venue "Late"
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                earlySlot <- createRosterSlotRecord rosterDay early Nothing 0
                _ <- createRosterSlotRecord rosterDay mid Nothing 0
                _ <- createRosterSlotRecord rosterDay late Nothing 0
                _ <- updateRecord (earlySlot |> set #note (Just "KM"))

                _ <- updateRecord (mid |> set #isActive False)
                _ <- updateRecord (late |> set #sortOrder 1)
                _ <- updateRecord (early |> set #sortOrder 2)
                graveyard <- createSlotNameRecordForRosterGroup venue rosterGroup "Graveyard" >>= updateRecord . set #sortOrder 0

                beforeSyncSlots <-
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                        |> orderByAsc #slotSortOrder
                        |> fetch

                map (.slotNameId) beforeSyncSlots `shouldBe` [unpackId early.id, unpackId mid.id, unpackId late.id]

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (SyncRosterWeekSlotStructureAction rosterWeek.id)

                response `responseStatusShouldBe` status302

                afterSyncSlots <-
                    query @RosterSlot
                        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #slotSortOrder
                        |> fetch

                map (.slotNameId) afterSyncSlots `shouldBe` [unpackId graveyard.id, unpackId late.id, unpackId early.id]
                map (.slotSortOrder) afterSyncSlots `shouldBe` [0, 1, 2]
                map (.note) afterSyncSlots `shouldBe` [Nothing, Nothing, Just "KM"]

        it "manager can toggle a draft week live via HTMX without redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-toggle-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #note (Just "OP"))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                            [("isLive", "on")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week is now live."
                response `responseBodyShouldContain` ">Alpha<"
                response `responseBodyShouldContain` "9:00 AM"
                response `responseBodyShouldContain` "OP"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""
                response `responseBodyShouldNotContain` "name=\"staffId\""
                response `responseBodyShouldNotContain` "js-time-picker-trigger"
                response `responseBodyShouldNotContain` "slot-note-input"

        it "renders live closed days as read-only closed text without the lock control" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-closed-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-day-closed-label"
                response `responseBodyShouldContain` "CLOSED"
                response `responseBodyShouldNotContain` "data-roster-day-closed-toggle=\"true\""
                response `responseBodyShouldNotContain` "bi-lock-fill"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""

        it "staff can see published weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-live@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser user do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">Alpha<"
                response `responseBodyShouldNotContain` "No roster exists for this week yet."

        it "manager can toggle a draft week live" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 False

                response <- withUser manager do
                    callActionWithParams
                        (ToggleRosterWeekLiveStatusAction rosterWeek.id)
                        [("isLive", "on")]

                response `responseStatusShouldBe` status302

                publishedWeek <- fetch rosterWeek.id
                publishedWeek.isLive `shouldBe` True

        it "manager can toggle a live week back to draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-draft-toggle@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 True

                response <- withUser manager do
                    callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)

                response `responseStatusShouldBe` status302

                updatedWeek <- fetch rosterWeek.id
                updatedWeek.isLive `shouldBe` False

        it "manager can fetch a roster row fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-row-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (rosterRowDomIdText rosterDay.id 0)
                response `responseBodyShouldContain` ">Alpha</option>"

        it "manager can fetch the roster content fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-content-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekContentFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` ">Alpha</option>"

        it "manager can fetch the roster staff panel fragment for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-panel-fragment@example.com" "staff" True
                linkedUser <- createUserRecord "roster-worker-panel-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue linkedUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just linkedUser) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekStaffPanelFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterStaffPanelFragmentId
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldContain` "1"

        it "manager roster staff panel fragment only shows staff applicable to the selected roster group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                alphaUser <- createUserRecord "roster-alpha-group-panel@example.com" "staff" True
                bravoUser <- createUserRecord "roster-bravo-group-panel@example.com" "staff" True
                _ <- createVenueMembershipRecord venue alphaUser "worker"
                _ <- createVenueMembershipRecord venue bravoUser "worker"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                alpha <- createStaffRecord venue (Just alphaUser) "Alpha" "Crew"
                bravo <- createStaffRecord venue (Just bravoUser) "Bravo" "Crew"
                syncStaffRosterGroupAssignments alpha [frontOfHouse.id]
                syncStaffRosterGroupAssignments bravo [backOfHouse.id]

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowRosterWeekStaffPanelFragmentAction 0) [("rosterGroupId", idToParam frontOfHouse.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-staff-name=\"Alpha\""
                response `responseBodyShouldNotContain` "data-roster-staff-name=\"Bravo\""

        it "staff row fragment fetch returns a masked row for a draft week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                staffUser <- createUserRecord "roster-staff-row-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue staffUser "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue staffUser venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                let rowId = cs (rosterRowDomIdText rosterDay.id 0) :: String
                bodyText `shouldContain` rowId
                bodyText `shouldNotContain` "Crew, Alpha"

        it "manager can copy a week and it is created as draft with copied slots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                sourceWeek <- createRosterWeekRecord venue 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                sourceSlot <- createRosterSlotRecord sourceDay slotName (Just staffMember) 0
                let sourceSlotWithFields =
                        sourceSlot
                            |> set #startTime (Just (timeOfDay 9 0))
                            |> set #durationMinutes (Just 480)
                            |> set #note (Just "CP")
                _ <- updateRecord sourceSlotWithFields

                response <- withUser manager do
                    callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status302

                copiedWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetchOne
                copiedWeek.isLive `shouldBe` False

                copiedDays <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> fetch
                length copiedDays `shouldBe` 7

                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                copiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                length copiedSlots `shouldBe` 1

                let copiedSlot = fromJust (head copiedSlots)
                copiedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                copiedSlot.slotNameId `shouldBe` unpackId slotName.id
                copiedSlot.rowIndex `shouldBe` 0
                copiedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                copiedSlot.durationMinutes `shouldBe` Just 480
                copiedSlot.note `shouldBe` Just "CP"

        it "manager can overwrite an existing target week with the previous roster" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-overwrite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                late <- fetchSlotNameRecord venue "Late"
                alpha <- createStaffRecord venue Nothing "Alpha" "Crew"
                bravo <- createStaffRecord venue Nothing "Bravo" "Crew"

                sourceWeek <- createRosterWeekRecord venue 0 True
                sourceDay <- createRosterDayRecord sourceWeek 0
                sourceSlot <- createRosterSlotRecord sourceDay early (Just alpha) 0
                _ <- updateRecord
                    ( sourceSlot
                        |> set #startTime (Just (timeOfDay 8 0))
                        |> set #durationMinutes (Just 300)
                        |> set #note (Just "FS")
                    )

                targetWeek <- createRosterWeekRecord venue 1 False
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> set #startTime (Just (timeOfDay 14 0))
                        |> set #durationMinutes (Just 180)
                        |> set #note (Just "OT")
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (CopyRosterWeekAction 0 1)

                response `responseStatusShouldBe` status302

                targetWeeks <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetch
                length targetWeeks `shouldBe` 1

                copiedWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 1)
                    |> fetchOne
                copiedDay <- query @RosterDay
                    |> filterWhere (#rosterWeekId, unpackId copiedWeek.id)
                    |> filterWhere (#dayOffset, 0)
                    |> fetchOne
                copiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId copiedDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch

                length copiedSlots `shouldBe` 1
                let copiedSlot = fromJust (head copiedSlots)
                copiedSlot.staffId `shouldBe` Just (unpackId alpha.id)
                copiedSlot.slotNameId `shouldBe` unpackId early.id
                copiedSlot.startTime `shouldBe` Just (timeOfDay 8 0)
                copiedSlot.durationMinutes `shouldBe` Just 300
                copiedSlot.note `shouldBe` Just "FS"

        it "rejects copying a roster week onto itself via HTMX" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-self-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                originalWeek <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 0 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Cannot copy a roster week onto itself."

                persistedWeeks <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 0)
                    |> fetch
                length persistedWeeks `shouldBe` 1
                map (.id) persistedWeeks `shouldBe` [originalWeek.id]

        it "rejects copying from a missing source week via HTMX without creating the target week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-copy-missing-source-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CopyRosterWeekAction 7 8)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Source week not found. Cannot copy."

                targetWeek <- query @RosterWeek
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#weekOffset, 8)
                    |> fetchOneOrNothing
                targetWeek `shouldBe` Nothing

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
                        |> set #rosterGroupId slotName.rosterGroupId
                        |> set #slotNameId (unpackId slotName.id)
                        |> set #weekdayIndex 2
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

        it "does not count shift preferences from another roster group as availability" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-cross-group-preference@example.com" "staff" True
                staffUser <- createUserRecord "roster-cross-group-preference@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                defaultSlotName <- fetchSlotNameRecord venue "Early"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                frontSlotName <- fetchSlotNameRecordForRosterGroup frontOfHouse "Early"
                staffMember <- createStaffRecord venue (Just staffUser) "CrossGroup" "Preference"
                _ <- createStaffRosterGroupRecord staffMember frontOfHouse
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staffMember.id)
                        |> set #rosterGroupId defaultSlotName.rosterGroupId
                        |> set #slotNameId (unpackId defaultSlotName.id)
                        |> set #weekdayIndex 1
                        |> createRecord
                rosterWeek <- createRosterWeekRecordForRosterGroup venue frontOfHouse 0 False
                mondayRosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord mondayRosterDay frontSlotName Nothing 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffUnavailable", "true")]
                    callAction (ShowRosterWeekRowFragmentAction 0 mondayRosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` ">CrossGroup Preference</option>"

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
    where
        timeOfDay hour minute = TimeOfDay hour minute 0
