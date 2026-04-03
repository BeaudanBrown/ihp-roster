module Test.Controller.RosterWeeksSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Config
import qualified Data.ByteString.Char8 as ByteString
import Data.Maybe (fromJust)
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
import Web.Routes
import Web.Types
import Web.View.RosterWeeks.Show (rosterContentFragmentId, rosterRowDomIdText,
                                  rosterStaffPanelFragmentId)

tests :: Spec
tests = beforeAll testContext do
    describe "RosterWeeksController" do
        it "redirects unauthenticated users from RosterWeeksAction" $ withContext do
            response <- callAction RosterWeeksAction
            response `responseStatusShouldBe` status302

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

        it "empty roster pages still expose live-update scope metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-empty-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-client-enabled=\"true\""
                response `responseBodyShouldContain` "data-live-update-scope-kind=\"roster_week\""
                response `responseBodyShouldContain` "data-live-update-roster-group-id=\""
                response `responseBodyShouldContain` "data-live-update-week-offset=\"0\""
                response `responseBodyShouldNotContain` "/helpers.js"
                response `responseBodyShouldNotContain` "/ihp-auto-refresh.js"
                response `responseBodyShouldNotContain` "ihp-auto-refresh-id"

        it "staff on hidden draft pages still expose live-update scope metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-hidden-draft-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-live-update-client-enabled=\"true\""
                response `responseBodyShouldContain` "data-live-update-scope-kind=\"roster_week\""
                response `responseBodyShouldContain` "data-live-update-roster-group-id=\""
                response `responseBodyShouldContain` "data-live-update-week-offset=\"0\""

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
                response `responseBodyShouldContain` "Crew, Alpha"
                response `responseBodyShouldContain` "hx-post=\"/ToggleRosterWeekLiveStatus?rosterWeekId="
                response `responseBodyShouldContain` ">Live</label>"

        it "manager roster pages render reusable week controls in the header" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "hx-post=\"/CopyRosterWeek?sourceWeekOffset=-1&amp;targetWeekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldContain` "data-roster-week-controls=\"manager-actions\""
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
                response `responseBodyShouldContain` "roster-day-label-row-secondary"
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
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #note (Just "Open"))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterDayClosedAction rosterDay.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster day marked closed."
                response `responseBodyShouldContain` "CLOSED"
                response `responseBodyShouldNotContain` "Crew, Alpha"
                response `responseBodyShouldNotContain` "9:00 AM"
                response `responseBodyShouldNotContain` "Open"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""

                updatedDay <- fetch rosterDay.id
                updatedDay.isClosed `shouldBe` True
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                unchangedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                unchangedSlot.note `shouldBe` Just "Open"

        it "closed roster days stay locked at three rows and reject row additions" $ withContext do
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
                response `responseBodyShouldContain` "Closed days stay locked at three blank rows until reopened."

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
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` cs (rosterRowDomIdText rosterDay.id 4)

                slotsForDay <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> orderByAsc #rowIndex
                    |> fetch
                let slotCount = length slotNames
                length slotsForDay `shouldBe` (5 * slotCount)
                map (.rowIndex) slotsForDay `shouldBe` concatMap (replicate slotCount) [0, 1, 2, 3, 4]
                map (.slotNameId) slotsForDay `shouldMatchList` map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames ++ map (unpackId . (.id)) slotNames

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
                _ <- updateRecord (slot |> set #startTime (Just (timeOfDay 9 0)) |> set #note (Just "Open"))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs rosterContentFragmentId
                response `responseBodyShouldContain` "Roster week is now live."
                response `responseBodyShouldContain` "Crew, Alpha"
                response `responseBodyShouldContain` "9:00 AM"
                response `responseBodyShouldContain` "Open"
                response `responseBodyShouldNotContain` "data-roster-day-add=\"true\""
                response `responseBodyShouldNotContain` "data-roster-day-remove=\"true\""
                response `responseBodyShouldNotContain` "name=\"staffId\""
                response `responseBodyShouldNotContain` "js-time-picker-trigger"
                response `responseBodyShouldNotContain` "slot-note-input"

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
                response `responseBodyShouldContain` "Crew, Alpha"
                response `responseBodyShouldNotContain` "No roster exists for this week yet."

        it "manager can toggle a draft week live" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-publish@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 False

                response <- withUser manager do
                    callAction (ToggleRosterWeekLiveStatusAction rosterWeek.id)

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
                response `responseBodyShouldContain` "Crew, Alpha"

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
                response `responseBodyShouldContain` "Crew, Alpha"

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
                response `responseBodyShouldContain` "Alpha Crew"
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
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId bravo.id) |> fetch >>= deleteRecords
                _ <- createStaffRosterGroupRecord alpha frontOfHouse
                _ <- createStaffRosterGroupRecord bravo backOfHouse

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowRosterWeekStaffPanelFragmentAction 0) [("rosterGroupId", idToParam frontOfHouse.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Alpha Crew"
                response `responseBodyShouldNotContain` "Bravo Crew"

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
                            |> set #note (Just "Copied note")
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
                    |> fetch
                length copiedSlots `shouldBe` 1

                let copiedSlot = fromJust (head copiedSlots)
                copiedSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                copiedSlot.slotNameId `shouldBe` unpackId slotName.id
                copiedSlot.rowIndex `shouldBe` 0
                copiedSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                copiedSlot.durationMinutes `shouldBe` Just 480
                copiedSlot.note `shouldBe` Just "Copied note"

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
                        |> set #note (Just "From source")
                    )

                targetWeek <- createRosterWeekRecord venue 1 False
                targetDay <- createRosterDayRecord targetWeek 0
                targetSlot <- createRosterSlotRecord targetDay late (Just bravo) 0
                _ <- updateRecord
                    ( targetSlot
                        |> set #startTime (Just (timeOfDay 14 0))
                        |> set #durationMinutes (Just 180)
                        |> set #note (Just "Old target")
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
                    |> fetch

                length copiedSlots `shouldBe` 1
                let copiedSlot = fromJust (head copiedSlots)
                copiedSlot.staffId `shouldBe` Just (unpackId alpha.id)
                copiedSlot.slotNameId `shouldBe` unpackId early.id
                copiedSlot.startTime `shouldBe` Just (timeOfDay 8 0)
                copiedSlot.durationMinutes `shouldBe` Just 300
                copiedSlot.note `shouldBe` Just "From source"

        it "returns a roster content patch when a slot assignment changes" $ withContext do
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
                let contentId = cs rosterContentFragmentId :: String
                bodyText `shouldContain` contentId
                bodyText `shouldContain` "hx-swap-oob=\"outerHTML\""
                bodyText `shouldContain` "Alpha Crew"
                bodyText `shouldContain` "roster-shift-summary-primary\">0</span><span class=\"roster-shift-summary-divider\">/</span><span class=\"roster-shift-summary-secondary\">5"
                bodyText `shouldContain` "Bravo Crew"
                bodyText `shouldContain` "roster-shift-summary-primary\">1</span><span class=\"roster-shift-summary-divider\">/</span><span class=\"roster-shift-summary-secondary\">7"

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
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId alpha.id) |> fetch >>= deleteRecords
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId bravo.id) |> fetch >>= deleteRecords
                _ <- createStaffRosterGroupRecord alpha frontOfHouse
                _ <- createStaffRosterGroupRecord bravo backOfHouse
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
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId alpha.id) |> fetch >>= deleteRecords
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId bravo.id) |> fetch >>= deleteRecords
                _ <- createStaffRosterGroupRecord alpha frontOfHouse
                _ <- createStaffRosterGroupRecord bravo backOfHouse
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
                _ <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId alpha.id) |> fetch >>= deleteRecords
                _ <- createStaffRosterGroupRecord alpha backOfHouse
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
    where
        timeOfDay hour minute = TimeOfDay hour minute 0
