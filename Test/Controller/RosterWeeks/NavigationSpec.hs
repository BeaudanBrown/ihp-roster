module Test.Controller.RosterWeeks.NavigationSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Config
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy.Char8 as LByteString
import Data.Maybe (fromJust)
import qualified Data.Text as Text
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

        it "redirects unauthenticated users from CreateRosterSlotAction" $ withContext do
            response <- callAction (CreateRosterSlotAction "11111111-1111-1111-1111-111111111111" "22222222-2222-2222-2222-222222222222" 0)
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
                map (.rowCount) createdDays `shouldBe` replicate 7 4
                createdSlots <- query @RosterSlot
                    |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) createdDays)
                    |> fetch
                length createdSlots `shouldBe` 0

        it "staff cannot see draft weeks but still gets the hidden roster shell" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-draft@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just user) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUser user do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-hidden-draft-grid"
                response `responseBodyShouldContain` "This roster isn't live yet."
                response `responseBodyShouldNotContain` "Crew, Alpha"
                response `responseBodyShouldNotContain` "roster-day-closed-label"
                response `responseBodyShouldNotContain` "slot-closed-cell"
                response `responseBodyShouldNotContain` "roster-grid-header-row-subheads"

        it "empty roster pages still expose FrontendSurface live metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-empty-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"roster\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "roster:"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "weekOffset"
                response `responseBodyShouldNotContain` "/helpers.js"

        it "staff on hidden draft pages still expose FrontendSurface live metadata" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-hidden-draft-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createRosterWeekRecord venue 0 False

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"roster\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "roster:"
                response `responseBodyShouldContain` "rosterGroupId"
                response `responseBodyShouldContain` "weekOffset"

        it "staff roster quick timesheet card subscribes to the operational timesheet day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                user <- createUserRecord "roster-staff-timesheet-live-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Roster"
                _ <- fetchSlotNameRecord venue "Early"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"roster-staff-self-service-timesheet-live-surface\""
                response `responseBodyShouldContain` "data-bepis-surface=\"timesheets\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldContain` "timesheets:"
                response `responseBodyShouldContain` "timesheet-day-section"
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-roster-self-service-leave-request\""
                response `responseBodyShouldNotContain` "data-live-update-surface"

                body <- responseBody response
                let bodyText = cs (LByteString.unpack body)
                Text.count "data-bepis-surface-config" bodyText `shouldBe` 2

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
                response `responseBodyShouldContain` ">Alpha</div>"
                response `responseBodyShouldContain` "hx-get=\"/EditRosterSlotDialog?rosterSlotId="
                response `responseBodyShouldContain` "hx-post=\"/ToggleRosterWeekLiveStatus?rosterWeekId="
                response `responseBodyShouldContain` ">Live</span></label>"

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
                response `responseBodyShouldNotContain` "Staff member has an approved unavailable period."

        it "manager roster pages render reusable week controls and staff panel settings" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"
                _ <- createVenueRosterGroupWithDefaults venue "Back of House" 1 False

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-toolbar=\"roster\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"quick\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"navigation\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"settings\""
                response `responseBodyShouldContain` "href=\"/RosterWeeks\""
                response `responseBodyShouldContain` "This week</a>"
                response `responseBodyShouldContain` "btn btn-outline-secondary app-week-nav-button"
                response `responseBodyShouldNotContain` "data-roster-week-controls=\"manager-actions\""
                response `responseBodyShouldContain` "data-roster-staff-panel-tab=\"staff\""
                response `responseBodyShouldContain` "data-roster-staff-panel-tab=\"settings\""
                response `responseBodyShouldContain` "id=\"roster-staff-panel-settings-pane\""
                response `responseBodyShouldContain` "Week actions"
                response `responseBodyShouldContain` "hx-post=\"/CopyRosterWeek?sourceWeekOffset=-1&amp;targetWeekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldContain` "hx-confirm=\"This will overwrite the current week with the previous week&#39;s roster. Continue?\""
                response `responseBodyShouldContain` "Sort shifts"
                response `responseBodyShouldContain` "hx-post=\"/SortRosterWeek?rosterWeekId="
                response `responseBodyShouldNotContain` "Roster columns"
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "roster-live-toggle-"
                response `responseBodyShouldContain` "btn btn-outline-success app-toggle-button"
                response `responseBodyShouldContain` "data-bepis-toggle-transport=\"toggle-transport:roster-live-toggle-"
                response `responseBodyShouldContain` "data-bepis-toggle-config=\""
                response `responseBodyShouldContain` "aria-pressed=\"false\""
                response `responseBodyShouldContain` "role=\"switch\" aria-checked=\"false\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"navigate-roster-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-week-live-status\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-staff-scope\""
                response `responseBodyShouldContain` "hx-target=\"#roster-staff-panel-fragment\""
                response `responseBodyShouldNotContain` "hx-target=\"#roster-staff-panel\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-warnings\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-roster-assignment-filters\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"sort-roster-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"copy-roster-week\""

        it "hides copy previous week controls from staff users" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                worker <- createUserRecord "roster-worker-copy-hidden@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker "worker"
                _ <- fetchSlotNameRecord venue "Early"

                response <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Copy Previous Week"
                response `responseBodyShouldNotContain` "hx-post=\"/CopyRosterWeek"
                response `responseBodyShouldNotContain` "Sort shifts"

        it "roster group switcher preserves weekOffset in the submitted form for multi-group venues" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-group-switcher@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- newRecord @RosterGroup
                    |> set #venueId (unpackId venue.id)
                    |> set #name ("Second group" :: Text)
                    |> set #sortOrder 2
                    |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 3)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "action=\"/ShowRosterWeek?weekOffset=3\""
                response `responseBodyShouldContain` "type=\"hidden\" name=\"weekOffset\" value=\"3\""
                response `responseBodyShouldContain` "name=\"rosterGroupId\""
