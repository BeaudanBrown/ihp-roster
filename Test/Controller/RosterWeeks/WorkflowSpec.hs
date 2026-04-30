module Test.Controller.RosterWeeks.WorkflowSpec where

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


timeOfDay :: Int -> Int -> TimeOfDay
timeOfDay hour minute = TimeOfDay hour minute 0
