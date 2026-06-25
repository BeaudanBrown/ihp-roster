module Test.Controller.RosterWeeks.FragmentsSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveUpdate (LiveUpdateScope (..))
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveUpdateWireFragment (..))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Config
import Data.ByteString (ByteString)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Set as Set
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
import Web.LiveSurfaceRegistry (LiveSurfaceInvalidationTarget (..),
                                planRegisteredLiveSurfaceInvalidations)
import Web.RosterWeeks.Dom (rosterDayColumnsFragmentId, rosterDaySectionDomId,
                            rosterGridFrameFragmentId, rosterRowDomIdText,
                            rosterStaffPanelFragmentId)
import Web.Routes
import Web.Types

countText :: Text -> Text -> Int
countText needle haystack
    | Text.null needle = 0
    | otherwise = go haystack 0
    where
        go remaining count =
            case Text.breakOn needle remaining of
                (_, "") -> count
                (_, afterMatch) -> go (Text.drop (Text.length needle) afterMatch) (count + 1)

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

                shiftType <- ensureVenueDefaultShiftType venue
                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) (fullShiftParams staffB shiftType)

                response `responseStatusShouldBe` status200

                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""

                let dayColumnsTarget = cs rosterDayColumnsFragmentId :: String
                let staffPanelTarget = cs rosterStaffPanelFragmentId :: String
                bodyText `shouldContain` ("id=\"" <> dayColumnsTarget <> "\"")
                bodyText `shouldNotContain` ("id=\"" <> (cs rosterGridFrameFragmentId :: String) <> "\"")
                bodyText `shouldContain` ("id=\"" <> staffPanelTarget <> "\"")
                bodyText `shouldContain` "hx-swap-oob=\"outerHTML\""

        it "plans non-overlapping passive roster content and staff panel fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-passive-overlap@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False

                targets <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        pure $ planRegisteredLiveSurfaceInvalidations
                            (Set.singleton (RosterWeekResource rosterWeek.rosterGroupId rosterWeek.weekOffset))
                            [RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = rosterWeek.rosterGroupId, weekOffset = rosterWeek.weekOffset }]

                targetFragmentKeys targets
                    `shouldBe` [[RosterGridToolbarFragment, RosterDayColumnsFragment, RosterDayRailFragment, RosterWageRailFragment, RosterSlotsGridFragment, RosterStaffPanelFragment]]

        it "renders hidden draft roster fragments without leaking closed days or slots to staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                worker <- createUserRecord "roster-worker-hidden-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker "worker"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just worker) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- updateRecord (rosterDay |> set #isClosed True)
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWeekGridFrameFragmentAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-visibility=\"hidden-draft\""
                response `responseBodyShouldContain` "This roster isn't live yet."
                response `responseBodyShouldNotContain` "Crew, Alpha"
                response `responseBodyShouldNotContain` "roster-day-closed-label"
                response `responseBodyShouldNotContain` "slot-closed-cell"

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

                shiftType <- ensureVenueDefaultShiftType venue
                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction currentSlot.id) (fullShiftParams staffB shiftType)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                let otherWeekRowTarget = cs (rosterRowDomIdText otherDay.id 2) :: String
                bodyText `shouldContain` (cs rosterDayColumnsFragmentId :: String)
                bodyText `shouldNotContain` (cs rosterGridFrameFragmentId :: String)
                bodyText `shouldNotContain` ("id=\"" <> otherWeekRowTarget <> "\"")

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
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffAtIdealShifts", "true")]
                    callAction (EditRosterSlotDialogAction slot.id)

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
                slot <- createRosterSlotRecord mondayRosterDay slotName (Just selectedStaff) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffUnavailable", "true")]
                    callAction (EditRosterSlotDialogAction slot.id)

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
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName mondayRosterDay frontSlotName

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffUnavailable", "true")]
                    callAction (NewRosterSlotDialogAction mondayRosterDay.id slotDefinition.id 0)

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
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName mondayRosterDay slotName

                response <- withUserAndCurrentVenue manager venue.id do
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0) [("hideStaffOnApprovedLeave", "true")]
                    callAction (NewRosterSlotDialogAction mondayRosterDay.id slotDefinition.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` ">Approved</option>"
                response `responseBodyShouldContain` ">Pending</option>"
                response `responseBodyShouldContain` ">Ended</option>"
                response `responseBodyShouldContain` ">Future</option>"

        it "renders one launcher wrapper per editable existing and create row-grid shift" $ withContext do
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
                lateDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay late

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                let bodyTextValue = cs body :: Text
                let existingGroupKey = "existing:" <> tshow firstSlot.id
                let createGroupKey = "new:" <> tshow rosterDay.id <> ":" <> tshow lateDefinition.id <> ":0"
                bodyText `shouldContain` ("class=\"roster-shift-unit roster-shift-launcher\"")
                bodyText `shouldContain` ("class=\"roster-shift-unit roster-shift-launcher roster-shift-create-unit\"")
                bodyText `shouldContain` ("data-roster-shift-group-key=\"" <> cs existingGroupKey <> "\"")
                bodyText `shouldContain` ("hx-get=\"/EditRosterSlotDialog?rosterSlotId=" <> cs (tshow firstSlot.id) <> "\"")
                bodyText `shouldContain` ("data-roster-shift-group-key=\"" <> cs createGroupKey <> "\"")
                bodyText `shouldContain` ("hx-get=\"/NewRosterSlotDialog?rosterDayId=" <> cs (tshow rosterDay.id) <> "&amp;rosterWeekSlotDefinitionId=" <> cs (tshow lateDefinition.id) <> "&amp;rowIndex=0\"")
                countText ("data-roster-shift-group-key=\"" <> existingGroupKey <> "\"") bodyTextValue `shouldBe` 1
                countText ("data-roster-shift-group-key=\"" <> createGroupKey <> "\"") bodyTextValue `shouldBe` 1
                bodyText `shouldNotContain` "data-roster-field-key="

        it "renders draft empty day-row shifts as unmerged visual cells with a hover-only merged create marker" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay early

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "roster-shift-unit roster-shift-launcher roster-shift-create-unit"
                bodyText `shouldContain` "roster-shift-unit-cell slot-empty-cell"
                bodyText `shouldContain` "roster-shift-create-plus-overlay"
                bodyText `shouldContain` ("data-roster-shift-group-key=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldContain` ">+</div>"
                bodyText `shouldNotContain` ">Add</div>"

        it "renders draft empty day-column shifts as empty cards with a centered green plus" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-empty-day-column-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay early

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterLayoutPreferenceAction 0) [("rosterLayoutMode", "day_columns")]

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "roster-shift-card-empty roster-shift-card-create roster-shift-launcher roster-shift-create-plus-card"
                bodyText `shouldContain` "<span class=\"roster-shift-create-plus\" aria-hidden=\"true\">+</span>"
                bodyText `shouldContain` "<span class=\"visually-hidden\">Add shift</span>"
                bodyText `shouldContain` ("data-roster-shift-group-key=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldNotContain` ">Add shift</div>"

        it "does not render empty day-row create markers for live rosters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-empty-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "roster-shift-create-plus-cell"
                response `responseBodyShouldNotContain` ">+</div>"
                response `responseBodyShouldNotContain` ">Add</div>"

        it "renders read-only existing row-grid shifts without launcher attrs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-live-existing-readonly@example.com" "staff" True
                staffUser <- createUserRecord "roster-staff-live-existing-readonly@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue staffUser "worker"
                early <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue (Just staffUser) "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay early (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekRowFragmentAction 0 rosterDay.id 0)

                response `responseStatusShouldBe` status200
                body <- responseBody response
                let bodyText = cs body :: String
                bodyText `shouldContain` "slot-staff-cell position-relative"
                bodyText `shouldContain` "Alpha"
                bodyText `shouldNotContain` ("data-roster-shift-group-key=\"existing:" <> cs (tshow slot.id) <> "\"")
                bodyText `shouldNotContain` ("hx-get=\"/EditRosterSlotDialog?rosterSlotId=" <> cs (tshow slot.id) <> "\"")
                bodyText `shouldNotContain` "data-roster-shift-launcher=\"true\""

        it "keeps create markers, row controls, and conflict staff-cell depth styling in CSS" $ withContext do
            cssBytes <- ByteString.readFile "static/css/features/roster/grid-cells.css"
            dayActionsCssBytes <- ByteString.readFile "static/css/features/roster/day-actions.css"
            shiftCardCssBytes <- ByteString.readFile "static/css/features/roster/shift-card.css"
            statesCssBytes <- ByteString.readFile "static/css/features/roster/states.css"
            staffPanelCssBytes <- ByteString.readFile "static/css/features/roster/staff-panel.css"
            staffHighlightCssBytes <- ByteString.readFile "static/css/features/roster/staff-highlight.css"
            let css = cs cssBytes :: String
            let dayActionsCss = cs dayActionsCssBytes :: String
            let shiftCardCss = cs shiftCardCssBytes :: String
            let statesCss = cs statesCssBytes :: String
            let staffPanelCss = cs staffPanelCssBytes :: String
            let staffHighlightCss = cs staffHighlightCssBytes :: String
            css `shouldContain` ".roster-grid .roster-shift-create-plus-cell .slot-cell-static"
            css `shouldContain` "opacity: 0;"
            css `shouldContain` ".roster-grid .roster-shift-create-plus-cell:hover .slot-cell-static"
            dayActionsCss `shouldContain` ".roster-grid-frame[data-roster-column-editing=\"true\"] .roster-day-action-add"
            dayActionsCss `shouldContain` ".roster-day-rail-section .roster-day-action-add,"
            dayActionsCss `shouldContain` "display: none;"
            shiftCardCss `shouldContain` ".roster-shift-create-plus-card"
            shiftCardCss `shouldContain` "color: var(--bs-success);"
            shiftCardCss `shouldContain` "font-size: 1.15rem;"
            shiftCardCss `shouldContain` "font-weight: 800;"
            shiftCardCss `shouldContain` ".roster-grid-frame[data-roster-end-times=\"true\"] .roster-shift-card-empty.roster-shift-create-plus-card"
            shiftCardCss `shouldNotContain` "article.roster-shift-card[data-roster-shift-colour^=\"palette-\"]:not(.roster-shift-card-create)"
            statesCss `shouldContain` ".roster-grid .slot-staff-cell.conflict-critical"
            statesCss `shouldContain` "background-image: linear-gradient(180deg, var(--roster-conflict-bg-start), var(--roster-conflict-bg))"
            staffPanelCss `shouldContain` ".roster-staff-name"
            staffPanelCss `shouldContain` "padding-left: 0.55rem !important;"
            staffHighlightCss `shouldContain` ".roster-grid-frame[data-roster-warnings=\"hidden\"] .roster-grid [role=\"gridcell\"].is-roster-staff-slot-highlighted"
            staffHighlightCss `shouldContain` ".roster-grid-frame[data-roster-warnings=\"hidden\"] .roster-shift-card.is-roster-staff-slot-highlighted .roster-shift-card-field"

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
                shiftType <- ensureVenueDefaultShiftType venue

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) (fullShiftParams alpha shiftType)

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
                shiftType <- ensureVenueDefaultShiftType venue

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterSlotAction slot.id) (fullShiftParams bravo shiftType)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Live roster weeks are read-only. Move it back to draft to make changes."
                unchangedSlot <- fetch slot.id
                unchangedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "creates a complete roster slot from a dialog submit" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-create-complete-slot@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                shiftType <- ensureVenueDefaultShiftType venue
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- newRecord @RosterWeekSlotDefinition
                    |> set #rosterWeekId (unpackId rosterWeek.id)
                    |> set #name "Early"
                    |> set #sortOrder 0
                    |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 2)
                            (fullShiftParams staffMember shiftType)

                response `responseStatusShouldBe` status200
                createdSlot <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#rosterWeekSlotDefinitionId, unpackId slotDefinition.id)
                    |> filterWhere (#rowIndex, 2)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetchOne
                createdSlot.staffId `shouldBe` Just (unpackId staffMember.id)
                createdSlot.startTime `shouldBe` Just (timeOfDay 9 0)
                createdSlot.shiftTypeId `shouldBe` Just (unpackId shiftType.id)
                updatedDay <- fetch rosterDay.id
                updatedDay.rowCount `shouldBe` 4

        it "extends day row count when creating a complete slot beyond the current rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-create-complete-slot-new-row@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                shiftType <- ensureVenueDefaultShiftType venue
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- newRecord @RosterWeekSlotDefinition
                    |> set #rosterWeekId (unpackId rosterWeek.id)
                    |> set #name "Early"
                    |> set #sortOrder 0
                    |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateRosterSlotAction rosterDay.id slotDefinition.id 5)
                            (fullShiftParams staffMember shiftType)

                response `responseStatusShouldBe` status200
                updatedDay <- fetch rosterDay.id
                updatedDay.rowCount `shouldBe` 6

        it "deletes a roster slot via the explicit delete action" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-delete-slot@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (DeleteRosterSlotAction slot.id)

                response `responseStatusShouldBe` status200
                clearedSlot <- fetch slot.id
                clearedSlot.deletedAt `shouldSatisfy` isJust

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
                shiftType <- ensureVenueDefaultShiftType venue

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterSlotAction slot.id) (fullShiftParams bravo shiftType)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "That staff member is not applicable to this roster group."
                rejectedSlot <- fetch slot.id
                rejectedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "renders an error when a non-HTMX slot update tries to assign ineligible staff" $ withContext do
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
                shiftType <- ensureVenueDefaultShiftType venue

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction slot.id) (fullShiftParams bravo shiftType)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "That staff member is not applicable to this roster group."
                rejectedSlot <- fetch slot.id
                rejectedSlot.staffId `shouldBe` Just (unpackId alpha.id)

        it "allows deleting a slot even when the previously assigned staff is no longer applicable" $ withContext do
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
                    callAction (DeleteRosterSlotAction slot.id)

                response `responseStatusShouldBe` status200
                clearedSlot <- fetch slot.id
                clearedSlot.deletedAt `shouldSatisfy` isJust

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
                shiftType <- ensureVenueDefaultShiftType venue
                _ <- updateRecord (firstSlot |> set #startTime (Just (timeOfDay 9 0)))

                _ <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateRosterSlotAction secondSlot.id) (fullShiftParamsAt staffMember shiftType "13:00")

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

        it "renders a static roster week label without the month overview trigger" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-overview-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "roster-week-nav-label"
                response `responseBodyShouldContain` "Week of"
                response `responseBodyShouldNotContain` "Open roster week overview"
                response `responseBodyShouldNotContain` "data-week-overview-fragment-mount=\"true\""
                response `responseBodyShouldNotContain` "hx-get=\"/ShowRosterWeekOverviewFragment?weekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldNotContain` "data-week-overview-day=\"true\""

        it "promotes roster layout selection through typed interaction intent markup" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-layout-intent@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"true\""
                response `responseBodyShouldContain` "data-bepis-intent-form=\"set-roster-layout-mode\""
                response `responseBodyShouldContain` "hx-trigger=\"bepis:intent-submit\""
                response `responseBodyShouldContain` "name=\"rosterLayoutMode\" value=\"\" data-bepis-intent-field=\"rosterLayoutMode\" data-bepis-field-presence=\"required\""
                response `responseBodyShouldContain` "data-bepis-marker=\"activation\" data-bepis-activation=\"roster-layout-day_columns\""
                response `responseBodyShouldContain` "data-bepis-activation-intent=\"set-roster-layout-mode\""
                response `responseBodyShouldContain` "data-bepis-activation-trigger=\"change\""
                response `responseBodyShouldContain` "data-bepis-activation-value-field=\"rosterLayoutMode\""

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

targetFragmentKeys :: [LiveSurfaceInvalidationTarget] -> [[LiveFragmentKey]]
targetFragmentKeys targets =
    [ map (.fragmentKey) target.targetFragments
    | target <- targets
    ]

fullShiftParams :: Staff -> ShiftType -> [(ByteString, ByteString)]
fullShiftParams staff shiftType = fullShiftParamsAt staff shiftType "09:00"

fullShiftParamsAt :: Staff -> ShiftType -> ByteString -> [(ByteString, ByteString)]
fullShiftParamsAt staff shiftType startTime =
    [ ("staffId", idToParam staff.id)
    , ("startTime", startTime)
    , ("endTime", "17:00")
    , ("shiftTypeId", idToParam shiftType.id)
    ]

timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
