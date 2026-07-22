module Test.Controller.RosterWeeks.FragmentsSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceHtmxRequest (..),
                                                                    FrontendSurfaceIntentForm,
                                                                    intentFormName)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekResource)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..))
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.SurfaceResource
import Application.Helper.View (dialogOverlayMountId)
import Config
import Data.ByteString (ByteString)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
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
import Web.RosterWeeks.Dom (rosterDayColumnsFragmentId, rosterDaySectionDomId,
                            rosterGridFrameFragmentId, rosterRowDomIdText,
                            rosterStaffPanelFragmentId)
import Web.RosterWeeks.FrontendSurface
import Web.Routes
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidations)
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
tests = aroundAll withDatabaseTestContext do
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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldContain` "id=\"dialog-overlay-mount\""

                let dayColumnsTarget = cs rosterDayColumnsFragmentId :: Text
                let staffPanelTarget = cs rosterStaffPanelFragmentId :: Text
                bodyText `shouldNotContain` ("id=\"" <> cs dayColumnsTarget <> "\"")
                bodyText `shouldNotContain` ("id=\"" <> (cs rosterGridFrameFragmentId :: String) <> "\"")
                bodyText `shouldNotContain` ("id=\"" <> cs staffPanelTarget <> "\"")
                bodyText `shouldNotContain` "hx-swap-oob=\"outerHTML\""
                let rosterAssignmentTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                rosterAssignmentTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf dayColumnsTarget)
                rosterAssignmentTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")
                rosterAssignmentTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf staffPanelTarget)

        it "refreshes the settings owner after roster preference changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "roster-admin-settings-owner@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                _ <- fetchSlotNameRecord venue "Early"
                _ <- createRosterWeekRecord venue 0 False

                warningResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterWarningPreferenceAction 0)
                            [("showRosterWarnings", "true")]
                wageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterWageEstimatePreferenceAction 0)
                            [("showWageEstimates", "true")]
                layoutResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateRosterLayoutPreferenceAction 0)
                            [("rosterLayoutMode", "day_columns")]

                let refreshesRosterSettings response = do
                        let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                        triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-grid-toolbar\"")
                        triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-grid-frame\"")
                        triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")
                refreshesRosterSettings warningResponse
                refreshesRosterSettings wageResponse
                refreshesRosterSettings layoutResponse

        it "plans non-overlapping passive roster content and staff panel fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-passive-overlap@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False

                targets <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        let scope = RosterLive.rosterWeekLiveScope (unpackId venue.id) rosterWeek.rosterGroupId rosterWeek.weekOffset
                        let scopeValue = RosterWeekScopeValue { rosterWeekVenueId = unpackId venue.id, rosterWeekGroupId = Id rosterWeek.rosterGroupId, rosterWeekWeekOffset = rosterWeek.weekOffset, rosterWeekTimelineDayOffset = Nothing }
                        let mountedPlan = RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
                        let subscription =
                                SurfaceSubscription
                                    { subscriptionScope = scope
                                    , subscriptionScopeKey = surfaceScopeKey scope
                                    , subscriptionFragmentKeys = rosterSurfaceFragmentKeys (rosterCandidateMountedFragments scopeValue mountedPlan)
                                    }
                        pure $ planSurfaceInvalidations
                            (Set.singleton (rosterWeekResource rosterWeek.rosterGroupId rosterWeek.weekOffset))
                            [subscription]

                targetFragmentKeys targets
                    `shouldBe`
                        [[ RosterLive.rosterGridToolbarLiveFragment
                         , RosterLive.rosterDayColumnsLiveFragment
                         , RosterLive.rosterDayRailLiveFragment
                         , RosterLive.rosterWageRailLiveFragment
                         , RosterLive.rosterStaffPanelLiveFragment
                         ]]

        it "builds typed FrontendSurface mount metadata for roster fragments" $ withContext do
            withCurrentControllerContext do
                let venueId = fromMaybe (error "invalid roster venue UUID") (UUID.fromString "00000000-0000-0000-0000-000000000111")
                let rosterGroupId = Id "00000000-0000-0000-0000-000000000222" :: Id RosterGroup
                let rosterDayId = Id "00000000-0000-0000-0000-000000000333" :: Id RosterDay
                let scope = RosterWeekScopeValue { rosterWeekVenueId = venueId, rosterWeekGroupId = rosterGroupId, rosterWeekWeekOffset = 3, rosterWeekTimelineDayOffset = Nothing }
                let plan = RosterMountedFragmentPlan { rosterMountedDayIds = [rosterDayId], rosterMountedRows = [(rosterDayId, 0), (rosterDayId, 1)] }
                let impl = rosterSurfaceImpl scope plan
                let mountConfig = impl.surfaceImplMountConfig
                let fragmentTargets = map (.mountedFragmentTargetId) mountConfig.mountFragments
                let fragmentUrls = map (.mountedFragmentUrl) mountConfig.mountFragments
                let fragmentKeys = rosterSurfaceFragmentKeys mountConfig.mountFragments

                impl.surfaceImplName `shouldBe` "roster"
                map (.intentFormName) (rosterIntentForms scope)
                    `shouldBe` ["set-roster-layout-mode", "move-roster-shift-to-slot", "duplicate-roster-shift-to-day", "drop-roster-staff"]
                mountConfig.mountSurfaceName `shouldBe` "roster"
                mountConfig.mountScopeKey `shouldBe` "roster:00000000-0000-0000-0000-000000000111:00000000-0000-0000-0000-000000000222:3"
                fragmentKeys
                    `shouldBe` [ RosterLive.rosterContentLiveFragment
                               , RosterLive.rosterGridToolbarLiveFragment
                               , RosterLive.rosterGridFrameLiveFragment
                               , RosterLive.rosterDayColumnsLiveFragment
                               , RosterLive.rosterDayRailLiveFragment
                               , RosterLive.rosterWageRailLiveFragment
                               , RosterLive.rosterSlotsGridLiveFragment
                               , RosterLive.rosterStaffPanelLiveFragment
                               , RosterLive.rosterDaySectionLiveFragment (unpackId rosterDayId)
                               , RosterLive.rosterRowLiveFragment (unpackId rosterDayId) 0
                               , RosterLive.rosterRowLiveFragment (unpackId rosterDayId) 1
                               ]
                fragmentTargets `shouldContain` [rosterDaySectionDomId rosterDayId]
                fragmentTargets `shouldContain` [rosterRowDomIdText rosterDayId 1]
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "weekOffset=3")
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "rosterGroupId=00000000-0000-0000-0000-000000000222")
                fragmentKeys `shouldContain` [RosterLive.rosterRowLiveFragment (unpackId rosterDayId) 1]

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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                bodyText `shouldNotContain` (cs rosterDayColumnsFragmentId :: String)
                bodyText `shouldNotContain` (cs rosterGridFrameFragmentId :: String)
                bodyText `shouldNotContain` ("id=\"" <> otherWeekRowTarget <> "\"")
                let currentWeekTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                currentWeekTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf rosterDayColumnsFragmentId)
                currentWeekTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf (cs otherWeekRowTarget))

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
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0)
                        [ ("hideStaffAtIdealShifts", "true")
                        , ("hideStaffUnavailable", "false")
                        , ("hideStaffOnApprovedLeave", "false")
                        , ("hideStaffAlreadyAssignedToday", "false")
                        ]
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
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0)
                        [ ("hideStaffAtIdealShifts", "false")
                        , ("hideStaffUnavailable", "true")
                        , ("hideStaffOnApprovedLeave", "false")
                        , ("hideStaffAlreadyAssignedToday", "false")
                        ]
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
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
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
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0)
                        [ ("hideStaffAtIdealShifts", "false")
                        , ("hideStaffUnavailable", "true")
                        , ("hideStaffOnApprovedLeave", "false")
                        , ("hideStaffAlreadyAssignedToday", "false")
                        ]
                    callAction (NewRosterSlotDialogAction mondayRosterDay.id slotDefinition.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ">CrossGroup</option>"

        it "renders timeline dropzones from the venue time picker window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-timeline-picker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #timePickerStartMinuteOfDay 540 |> set #timePickerFinalSelectableMinuteOfDay 780)
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                timelineSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                _ <- updateRecord (timelineSlot |> set #startTime (Just (TimeOfDay 9 0 0)) |> set #endTime (Just (TimeOfDay 13 0 0)))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowRosterWeekAction 0)
                        [ ("rosterView", "timeline")
                        , ("dayOffset", "0")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-roster-timeline-minute=\"540\""
                response `responseBodyShouldContain` "data-roster-timeline-minute=\"780\""
                response `responseBodyShouldContain` ("data-bepis-roster-day-timeline-shift-group-highlight-source=\"existing:" <> cs (tshow timelineSlot.id) <> "\"")
                response `responseBodyShouldContain` ("data-bepis-roster-day-timeline-shift-group-highlight-member=\"existing:" <> cs (tshow timelineSlot.id) <> "\"")
                response `responseBodyShouldNotContain` "data-roster-timeline-minute=\"360\""

        it "defaults new shift dialog times from the venue time picker window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-default-picker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
                slotName <- fetchSlotNameRecord venue "Early"
                rosterWeek <- createRosterWeekRecord venue 0 False
                mondayRosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName mondayRosterDay slotName
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #timePickerStartMinuteOfDay 540 |> set #timePickerFinalSelectableMinuteOfDay 780)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (NewRosterSlotDialogAction mondayRosterDay.id slotDefinition.id 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"13:00\""
                response `responseBodyShouldContain` "data-bepis-time-picker-config="
                response `responseBodyShouldContain` "&quot;rangeStart&quot;:&quot;09:00&quot;"
                response `responseBodyShouldContain` "&quot;rangeEnd&quot;:&quot;13:00&quot;"

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
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
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
                    _ <- callActionWithParams (UpdateRosterAssignmentFiltersAction 0)
                        [ ("hideStaffAtIdealShifts", "false")
                        , ("hideStaffUnavailable", "false")
                        , ("hideStaffOnApprovedLeave", "true")
                        , ("hideStaffAlreadyAssignedToday", "false")
                        ]
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
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-source=\"" <> cs existingGroupKey <> "\"")
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-member=\"" <> cs existingGroupKey <> "\"")
                bodyText `shouldContain` ("hx-get=\"/EditRosterSlotDialog?rosterSlotId=" <> cs (tshow firstSlot.id) <> "\"")
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-source=\"" <> cs createGroupKey <> "\"")
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-member=\"" <> cs createGroupKey <> "\"")
                bodyText `shouldContain` ("hx-get=\"/NewRosterSlotDialog?rosterDayId=" <> cs (tshow rosterDay.id) <> "&amp;rosterWeekSlotDefinitionId=" <> cs (tshow lateDefinition.id) <> "&amp;rowIndex=0\"")
                countText ("data-bepis-roster-shift-group-highlight-source=\"" <> existingGroupKey <> "\"") bodyTextValue `shouldBe` 1
                countText ("data-bepis-roster-shift-group-highlight-member=\"" <> existingGroupKey <> "\"") bodyTextValue `shouldBe` 1
                countText ("data-bepis-roster-shift-group-highlight-source=\"" <> createGroupKey <> "\"") bodyTextValue `shouldBe` 1
                countText ("data-bepis-roster-shift-group-highlight-member=\"" <> createGroupKey <> "\"") bodyTextValue `shouldBe` 1
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
                bodyText `shouldContain` "data-bepis-dropzone-ref=\"shift-slot-dropzone\""
                bodyText `shouldContain` "roster-shift-create-grid"
                bodyText `shouldNotContain` "data-bepis-dropzone-ref=\"staff-create-dropzone\""
                bodyText `shouldContain` "roster-shift-unit-cell slot-empty-cell"
                bodyText `shouldContain` "roster-shift-create-plus-overlay"
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-source=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-member=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
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
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` "roster-shift-card-empty roster-shift-card-create roster-shift-launcher roster-shift-create-plus-card"

                fragmentResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekDayColumnsFragmentAction 0)
                body <- responseBody fragmentResponse
                let bodyText = cs body :: String
                bodyText `shouldContain` "roster-shift-card-empty roster-shift-card-create roster-shift-launcher roster-shift-create-plus-card"
                bodyText `shouldContain` "<span class=\"roster-shift-create-plus\" aria-hidden=\"true\">+</span>"
                bodyText `shouldContain` "<span class=\"visually-hidden\">Add shift</span>"
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-source=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldContain` ("data-bepis-roster-shift-group-highlight-member=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldContain` "data-bepis-dropzone-ref=\"staff-create-dropzone\""
                bodyText `shouldContain` ("data-bepis-dropzone-key=\"new:" <> cs (tshow rosterDay.id) <> ":" <> cs (tshow slotDefinition.id) <> ":0\"")
                bodyText `shouldNotContain` ">Add shift</div>"

        it "renders editable day-column shifts as typed drag sources and create cards as drop targets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-day-column-drag-intent@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                early <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                sourceSlot <- createRosterSlotRecord rosterDay early (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterLayoutPreferenceAction 0) [("rosterLayoutMode", "day_columns")]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` "roster-day-columns"

                fragmentResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekDayColumnsFragmentAction 0)
                body <- responseBody fragmentResponse
                let bodyText = cs body :: String
                let sourceGroupKey = "existing:" <> tshow sourceSlot.id
                let targetGroupKey = "new:" <> tshow rosterDay.id <> ":" <> tshow sourceSlot.rosterWeekSlotDefinitionId <> ":1"
                bodyText `shouldContain` "roster-day-columns"
                bodyText `shouldContain` "data-bepis-source-ref=\"shift-drag-source\""
                bodyText `shouldContain` ("data-bepis-source-key=\"" <> cs sourceGroupKey <> "\"")
                bodyText `shouldContain` "data-bepis-dropzone-ref=\"existing-shift-dropzone\""
                bodyText `shouldContain` ("data-bepis-dropzone-key=\"" <> cs sourceGroupKey <> "\"")
                bodyText `shouldContain` "data-bepis-dropzone-ref=\"day-column-dropzone\""
                bodyText `shouldContain` ("data-bepis-dropzone-key=\"day:" <> cs (tshow rosterDay.id) <> "\"")
                bodyText `shouldContain` "data-bepis-dropzone-ref=\"staff-create-dropzone\""
                bodyText `shouldContain` ("data-bepis-dropzone-key=\"" <> cs targetGroupKey <> "\"")
                bodyText `shouldContain` ("hx-get=\"/EditRosterSlotDialog?rosterSlotId=" <> cs (tshow sourceSlot.id) <> "\"")
                bodyText `shouldContain` ("hx-get=\"/NewRosterSlotDialog?rosterDayId=" <> cs (tshow rosterDay.id) <> "&amp;rosterWeekSlotDefinitionId=" <> cs (tshow sourceSlot.rosterWeekSlotDefinitionId) <> "&amp;rowIndex=1\"")

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
                bodyText `shouldNotContain` ("data-bepis-roster-shift-group-highlight-source=\"existing:" <> cs (tshow slot.id) <> "\"")
                bodyText `shouldNotContain` ("hx-get=\"/EditRosterSlotDialog?rosterSlotId=" <> cs (tshow slot.id) <> "\"")
                bodyText `shouldNotContain` "data-roster-shift-launcher=\"true\""

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
                firstRowText `shouldContain` "title="
                secondRowText `shouldContain` "title="

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
                response `responseBodyShouldNotContain` "data-bepis-roster-week-overview-panel="
                response `responseBodyShouldNotContain` "hx-get=\"/ShowRosterWeekOverviewFragment?weekOffset=0&amp;rosterGroupId="
                response `responseBodyShouldNotContain` "data-bepis-roster-week-overview-day="

        it "promotes roster layout selection through typed interaction intent markup" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-layout-intent@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"roster\""
                response `responseBodyShouldContain` "data-bepis-intent-form=\"set-roster-layout-mode\""
                response `responseBodyShouldContain` "hx-trigger=\"bepis:intent-submit\""
                response `responseBodyShouldContain` "name=\"rosterLayoutMode\" value=\"day_rows\" data-bepis-intent-field=\"rosterLayoutMode\" data-bepis-field-presence=\"required\""
                response `responseBodyShouldContain` "data-bepis-activation-ref=\"roster-layout-mode-activation\""
                response `responseBodyShouldNotContain` "data-bepis-activation-intent=\"set-roster-layout-mode\""
                response `responseBodyShouldNotContain` "data-bepis-activation-trigger=\"change\""

        it "renders typed drag/drop intent markup for editable row-grid shifts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-intent@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                _ <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWeekAction 0)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-disposable-layer=\"drag-preview\""
                response `responseBodyShouldContain` "data-bepis-intent-form=\"move-roster-shift-to-slot\""
                response `responseBodyShouldContain` "data-bepis-intent-form=\"duplicate-roster-shift-to-day\""
                response `responseBodyShouldContain` "data-bepis-intent-form=\"drop-roster-staff\""
                response `responseBodyShouldContain` "name=\"sourceItemKey\" value=\"\" data-bepis-intent-field=\"sourceItemKey\" data-bepis-field-presence=\"required\""
                response `responseBodyShouldContain` "name=\"targetDropzoneKey\" value=\"\" data-bepis-intent-field=\"targetDropzoneKey\" data-bepis-field-presence=\"required\""
                response `responseBodyShouldContain` "name=\"sessionKind\" value=\"\" data-bepis-intent-field=\"sessionKind\" data-bepis-field-presence=\"optional\""
                response `responseBodyShouldContain` "name=\"pointerId\" value=\"\" data-bepis-intent-field=\"pointerId\" data-bepis-field-presence=\"optional\""
                response `responseBodyShouldContain` "data-bepis-source-ref=\"shift-drag-source\""
                response `responseBodyShouldContain` "data-bepis-source-key=\"existing:"
                response `responseBodyShouldContain` "data-bepis-dropzone-ref=\"existing-shift-dropzone\""
                response `responseBodyShouldContain` "data-bepis-dropzone-ref=\"shift-slot-dropzone\""
                response `responseBodyShouldNotContain` "data-bepis-dropzone-ref=\"staff-create-dropzone\""
                response `responseBodyShouldContain` "data-bepis-dropzone-ref=\"delete-shift-dropzone\""
                response `responseBodyShouldContain` "data-bepis-dropzone-key=\"new:"

        it "opens delete confirmation when a roster shift is dropped on the toolbar delete target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-delete-confirm@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                sourceSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams MoveRosterShiftToSlotAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("existing:" <> tshow sourceSlot.id))
                            , ("targetDropzoneKey", "delete")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ("id=\"" <> cs dialogOverlayMountId <> "\"")
                response `responseBodyShouldContain` "hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldContain` "hx-confirm=\"Delete this shift?\""
                response `responseBodyShouldContain` "data-bepis-dialog-auto-submit-once=\"true\""
                response `responseBodyShouldNotContain` "data-bepis-app-shell-action="
                persistedSlot <- fetch sourceSlot.id
                persistedSlot.deletedAt `shouldBe` Nothing

        it "moves an editable roster shift to a typed empty dropzone intent target" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-move@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                sourceSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                let sourceToken = "existing:" <> tshow sourceSlot.id
                let targetToken = "new:" <> tshow rosterDay.id <> ":" <> tshow sourceSlot.rosterWeekSlotDefinitionId <> ":1"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams MoveRosterShiftToSlotAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs sourceToken)
                            , ("targetDropzoneKey", cs targetToken)
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch sourceSlot.id
                updatedSlot.rosterDayId `shouldBe` unpackId rosterDay.id
                updatedSlot.rosterWeekSlotDefinitionId `shouldBe` sourceSlot.rosterWeekSlotDefinitionId
                updatedSlot.rowIndex `shouldBe` 1
                response `responseBodyShouldContain` "Roster shift moved."

        it "moves a shift onto a semantic day target and grows the target day rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-move-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                otherStaff <- createStaffRecord venue Nothing "Beta" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                sourceDay <- createRosterDayRecord rosterWeek 0
                targetDay <- createRosterDayRecord rosterWeek 1 >>= updateRecord . set #rowCount 1
                sourceSlot <- createRosterSlotRecord sourceDay slotName (Just staffMember) 0
                _ <- createRosterSlotRecord targetDay slotName (Just otherStaff) 0
                let sourceToken = "existing:" <> tshow sourceSlot.id
                let targetToken = "day:" <> tshow targetDay.id

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams MoveRosterShiftToSlotAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs sourceToken)
                            , ("targetDropzoneKey", cs targetToken)
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch sourceSlot.id
                updatedTargetDay <- fetch targetDay.id
                updatedSlot.rosterDayId `shouldBe` unpackId targetDay.id
                updatedSlot.rowIndex `shouldBe` 1
                updatedTargetDay.rowCount `shouldBe` 2
                response `responseBodyShouldContain` "Roster shift moved."

        it "silently no-ops a semantic day move onto the source day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-same-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                sourceSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams MoveRosterShiftToSlotAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("existing:" <> tshow sourceSlot.id))
                            , ("targetDropzoneKey", cs ("day:" <> tshow rosterDay.id))
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch sourceSlot.id
                updatedSlot.rosterDayId `shouldBe` unpackId rosterDay.id
                updatedSlot.rowIndex `shouldBe` 0
                response `responseBodyShouldNotContain` "Roster shift moved."

        it "assigns dragged staff onto an existing roster shift" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-staff-drop-existing@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                originalStaff <- createStaffRecord venue Nothing "Alpha" "Crew"
                replacementStaff <- createStaffRecord venue Nothing "Beta" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                targetSlot <- createRosterSlotRecord rosterDay slotName (Just originalStaff) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DropRosterStaffAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("staff:" <> tshow replacementStaff.id))
                            , ("targetDropzoneKey", cs ("existing:" <> tshow targetSlot.id))
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch targetSlot.id
                updatedSlot.staffId `shouldBe` Just (unpackId replacementStaff.id)
                response `responseBodyShouldContain` "Staff assigned."

        it "rejects dragged staff assignment on live roster weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-staff-drop-live@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                originalStaff <- createStaffRecord venue Nothing "Alpha" "Crew"
                replacementStaff <- createStaffRecord venue Nothing "Beta" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                targetSlot <- createRosterSlotRecord rosterDay slotName (Just originalStaff) 0

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DropRosterStaffAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("staff:" <> tshow replacementStaff.id))
                            , ("targetDropzoneKey", cs ("existing:" <> tshow targetSlot.id))
                            ]

                response `responseStatusShouldBe` status200
                updatedSlot <- fetch targetSlot.id
                updatedSlot.staffId `shouldBe` Just (unpackId originalStaff.id)
                response `responseBodyShouldContain` "Drop staff onto an editable shift in this roster week."

        it "opens the new shift dialog with dragged staff preselected" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-staff-drop-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
                let targetToken = "new:" <> tshow rosterDay.id <> ":" <> tshow slotDefinition.id <> ":0"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DropRosterStaffAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("staff:" <> tshow staffMember.id))
                            , ("targetDropzoneKey", cs targetToken)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` ("id=\"" <> cs dialogOverlayMountId <> "\"")
                response `responseBodyShouldContain` "hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldContain` "Add shift"
                response `responseBodyShouldContain` ("value=\"" <> cs (tshow staffMember.id) <> "\"")
                response `responseBodyShouldContain` "selected"

        it "duplicates a shift onto a semantic day target and grows rows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "roster-manager-drag-copy-day@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                slotName <- fetchSlotNameRecord venue "Early"
                staffMember <- createStaffRecord venue Nothing "Alpha" "Crew"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0 >>= updateRecord . set #rowCount 1
                sourceSlot <- createRosterSlotRecord rosterDay slotName (Just staffMember) 0
                sourceSlot <- updateRecord (sourceSlot |> set #startTime (Just (TimeOfDay 9 0 0)) |> set #endTime (Just (TimeOfDay 17 0 0)) |> set #durationMinutes (Just 480))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams DuplicateRosterShiftToDayAction { weekOffset = 0 }
                            [ ("rosterGroupId", cs (tshow rosterWeek.rosterGroupId))
                            , ("sourceItemKey", cs ("existing:" <> tshow sourceSlot.id))
                            , ("targetDropzoneKey", cs ("day:" <> tshow rosterDay.id))
                            ]

                response `responseStatusShouldBe` status200
                updatedSource <- fetch sourceSlot.id
                updatedDay <- fetch rosterDay.id
                copiedSlots <- query @RosterSlot
                    |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> orderByAsc #rowIndex
                    |> fetch
                length copiedSlots `shouldBe` 2
                updatedSource.rowIndex `shouldBe` 0
                updatedDay.rowCount `shouldBe` 2
                map (.staffId) copiedSlots `shouldBe` [sourceSlot.staffId, sourceSlot.staffId]
                map (.startTime) copiedSlots `shouldBe` [sourceSlot.startTime, sourceSlot.startTime]
                map (.durationMinutes) copiedSlots `shouldBe` [sourceSlot.durationMinutes, sourceSlot.durationMinutes]
                response `responseBodyShouldContain` "Roster shift duplicated."

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
                response `responseBodyShouldContain` "data-bepis-roster-week-overview-panel="
                response `responseBodyShouldContain` "&quot;weekOverviewDate&quot;:&quot;2025-01-13&quot;"
                response `responseBodyShouldContain` "&quot;weekOverviewAssignedDisplay&quot;:&quot;2&quot;"
                response `responseBodyShouldContain` "&quot;weekOverviewHoursDisplay&quot;:&quot;8h&quot;"
                response `responseBodyShouldContain` "&quot;weekOverviewLeaveDisplay&quot;:&quot;1&quot;"
                response `responseBodyShouldNotContain` "&quot;weekOverviewLeaveDisplay&quot;:&quot;2&quot;"
                response `responseBodyShouldContain` "&quot;weekOverviewDate&quot;:&quot;2025-01-01&quot;"
                response `responseBodyShouldContain` "weekDate=2025-01-13"

targetFragmentKeys :: [SurfaceInvalidationTarget] -> [[SurfaceFragmentKey]]
targetFragmentKeys targets =
    [ target.targetFragments
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
