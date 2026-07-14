module Test.Controller.TimesheetsSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      parseTimeParam)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceFragmentKey (..),
                                                            FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..))
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Test.Support.SurfaceContract
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Timesheets.FrontendSurface
import Web.Timesheets.Mutations (materializeTimesheetSuggestionMutation,
                                 timesheetEntryTouchedResources)
import Web.Timesheets.Projection (TimesheetProjectionFragment (..),
                                  TimesheetProjectionRequest (..),
                                  fetchTimesheetSuggestionForRosterSlot)
import Web.Timesheets.Suggestion (newTimesheetEntryFromSuggestion)
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "TimesheetsController" do
        it "redirects unauthenticated users from timesheets page" $ withContext do
            response <- callAction TimesheetsAction
            response `responseStatusShouldBe` status302

        it "redirects venue-less super-admins from timesheets to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "timesheets-bootstrap-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUser user do
                    callAction TimesheetsAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "redirects unauthenticated users from weekly timesheets page" $ withContext do
            response <- callAction ShowTimesheetWeekAction { weekOffset = 0 }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from day-section fragment action" $ withContext do
            response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from new timesheet entry" $ withContext do
            response <- callAction NewTimesheetEntryAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from create timesheet entry" $ withContext do
            response <- callAction CreateTimesheetEntryAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from approve action" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            response <- callAction ApproveTimesheetEntryAction { timesheetEntryId = entryId }
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from unapprove action" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            response <- callAction UnapproveTimesheetEntryAction { timesheetEntryId = entryId }
            response `responseStatusShouldBe` status302

        it "renders a subscribed timesheet shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Viewer"

                (response, mountConfig, expectedRefs) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWeekWeekOffset = 0 }
                        let mountState = TimesheetsMountStateValue { timesheetsMountShowApproved = False, timesheetsMountShowAllStaff = True, timesheetsMountShowSuggestions = True, timesheetsMountStaffFilterId = Nothing }
                        let impl = timesheetsSurfaceImpl scope mountState
                        response <- callAction ShowTimesheetWeekAction { weekOffset = 0 }
                        pure (response, impl.surfaceImplMountConfig, impl.surfaceImplMountConfig.mountFragments)

                mountConfig.mountSurfaceName `shouldBe` "timesheets"
                mountConfig.mountScopeKey `shouldBe` "timesheets:" <> tshow (unpackId venue.id) <> ":0"
                expectedRefs `shouldNotBe` []

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"timesheets\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldNotContain` "data-live-update-surface="
                response `responseBodyShouldContain` "timesheets:"
                response `responseBodyShouldContain` "data-timesheet-day-offset=\"0\""
                response `responseBodyShouldContain` "hx-sync=\"closest #timesheet-week-shell:replace\""
                response `responseBodyShouldNotContain` "timesheet-week-shell-sync-custom-htmx"

        it "builds typed FrontendSurface mount metadata for the current timesheet query state" $ withContext do
            withCurrentControllerContext do
                let venueId = fromMaybe (error "invalid test UUID") (UUID.fromString "00000000-0000-0000-0000-000000000123")
                let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWeekWeekOffset = 2 }
                let mountState = TimesheetsMountStateValue { timesheetsMountShowApproved = False, timesheetsMountShowAllStaff = True, timesheetsMountShowSuggestions = True, timesheetsMountStaffFilterId = Nothing }
                let impl = timesheetsSurfaceImpl scope mountState
                let mountConfig = impl.surfaceImplMountConfig
                let fragmentKinds = map (\fragment -> fragment.mountedFragmentKey.fragmentKind) mountConfig.mountFragments
                let fragmentTargets = map (.mountedFragmentTargetId) mountConfig.mountFragments
                let fragmentUrls = map (.mountedFragmentUrl) mountConfig.mountFragments

                impl.surfaceImplName `shouldBe` "timesheets"
                mountConfig.mountSurfaceName `shouldBe` "timesheets"
                mountConfig.mountScopeKey `shouldBe` "timesheets:00000000-0000-0000-0000-000000000123:2"
                mountConfig.mountState `shouldBe` Aeson.object
                    [ "showApproved" Aeson..= False
                    , "showAllStaff" Aeson..= True
                    , "showSuggestions" Aeson..= True
                    , "staffFilterId" Aeson..= (Nothing :: Maybe Text)
                    ]
                fragmentKinds `shouldBe` ["timesheet-toolbar", "timesheet-day-columns"] <> replicate 7 "timesheet-day-section"
                fragmentTargets `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"] <> map (\dayOffset -> "timesheet-day-section-" <> tshow dayOffset) [0 .. 6]
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "weekOffset=2")
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "showApproved=false")
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "showAllStaff=true")

        it "records touched resources for timesheet entry mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Touched Timesheet Venue"
                staff <- createStaffRecord venue Nothing "Tim" "Touched"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let weekOffset = venueWeekOffsetForDay venueConfig entry.workedOn

                Set.fromList (timesheetEntryTouchedResources venueConfig [entry])
                    `shouldBe` Set.fromList
                        [ timesheetWeekResource (unpackId venue.id) weekOffset
                        , timesheetDayResource (unpackId venue.id) weekOffset 1

                        ]

        it "denies unauthenticated users through the timesheet surface fragment contract" $ withContext do
            response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }

            liveFragmentResponseShouldBeDenied status302 response

        it "renders the declared timesheet day fragment target for authorized viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Fragment Contract Venue"
                user <- createUserRecord "timesheet-fragment-contract@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tara" "Target"

                (response, fragmentRef) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWeekWeekOffset = 0 }
                        let mountState = TimesheetsMountStateValue { timesheetsMountShowApproved = False, timesheetsMountShowAllStaff = True, timesheetsMountShowSuggestions = True, timesheetsMountStaffFilterId = Nothing }
                        let daySectionRef =
                                timesheetsCandidateMountedFragments scope mountState
                                    |> find (\fragment -> fragment.mountedFragmentTargetId == "timesheet-day-section-0")
                                    |> fromMaybe (error "Expected day section fragment ref")
                        callAction ShowTimesheetWeekAction { weekOffset = 0 }
                        response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }
                        pure (response, daySectionRef)

                liveFragmentResponseShouldRenderTarget response fragmentRef

        it "renders unified toolbar and day-columns fragments for HTMX week navigation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet HTMX Fragment Venue"
                manager <- createUserRecord "timesheet-htmx-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ShowTimesheetWeekAction { weekOffset = 1 }
                            [ ("showApproved", "true")
                            , ("showAllStaff", "false")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"timesheet-week-toolbar\""
                response `responseBodyShouldContain` "id=\"timesheet-day-columns\""
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""
                response `responseBodyShouldNotContain` "data-live-update-surface="
                response `responseBodyShouldNotContain` "id=\"timesheet-week-shell\" hx-history-elt"

        it "renders declared timesheet toolbar and day-columns fragment targets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Layout Fragment Venue"
                manager <- createUserRecord "timesheet-layout-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                toolbarResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowtimesheetToolbarLiveFragmentAction { weekOffset = 0 }
                columnsResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowtimesheetDayColumnsLiveFragmentAction { weekOffset = 0 }

                toolbarResponse `responseStatusShouldBe` status200
                toolbarResponse `responseBodyShouldContain` "id=\"timesheet-week-toolbar\""
                toolbarResponse `responseBodyShouldNotContain` "data-live-update-url="
                columnsResponse `responseStatusShouldBe` status200
                columnsResponse `responseBodyShouldContain` "id=\"timesheet-day-columns\""
                columnsResponse `responseBodyShouldNotContain` "data-live-update-surface="
                columnsResponse `responseBodyShouldContain` "id=\"timesheet-day-section-0\""

        it "lets super-admin create timesheet entries for venue staff without a staff identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Timesheet Venue"
                superAdmin <- createUserRecordWithPlatformRole "timesheet-super-admin@example.com" "staff" (Just SuperAdminRole) True
                worker <- createUserRecord "timesheet-super-admin-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker "worker"
                staff <- createStaffRecord venue (Just worker) "Tess" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]

                response `responseStatusShouldBe` status302
                entryExists <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> fetchExists
                entryExists `shouldBe` True

        it "renders HTMX timesheet forms with javascript submission disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Form"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "Timesheet Tuesday 07/01"
                response `responseBodyShouldContain` "name=\"startTime\" value=\"06:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"14:00\""
                response `responseBodyShouldContain` "data-time-picker-start=\"06:00\""
                response `responseBodyShouldContain` "data-time-picker-end=\"05:45\""
                response `responseBodyShouldNotContain` ">Day<"
                response `responseBodyShouldNotContain` "07/01/2025</div>"

        it "uses venue time picker window for new timesheet defaults and picker ranges" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Picker Venue"
                user <- createUserRecord "timesheet-picker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Tess" "Picker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #timePickerStartMinuteOfDay 540 |> set #timePickerFinalSelectableMinuteOfDay 780)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"13:00\""
                response `responseBodyShouldContain` "data-time-picker-start=\"09:00\""
                response `responseBodyShouldContain` "data-time-picker-end=\"13:00\""

        it "excludes trial staff from manager timesheet forms and staff filters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Trial Exclusion Venue"
                manager <- createUserRecord "timesheet-trial-manager@example.com" "staff" True
                linkedUser <- createUserRecord "timesheet-linked-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue linkedUser "worker"
                linkedStaff <- createStaffRecord venue (Just linkedUser) "Linked" "Worker"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                formResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]
                weekResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWeekAction 0) [("showAllStaff", "true")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldContain` "Linked Worker"
                formResponse `responseBodyShouldNotContain` "Trial Worker"
                formResponse `responseBodyShouldContain` cs (tshow linkedStaff.id)
                formResponse `responseBodyShouldNotContain` cs (tshow trialStaff.id)
                weekResponse `responseStatusShouldBe` status200
                weekResponse `responseBodyShouldContain` "Linked Worker"
                weekResponse `responseBodyShouldNotContain` "Trial Worker"
                weekResponse `responseBodyShouldNotContain` cs (tshow trialStaff.id)

        it "rejects tampered manager timesheet creation for trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Trial Tamper Venue"
                manager <- createUserRecord "timesheet-trial-tamper-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Tamper"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam trialStaff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]

                response `responseStatusShouldBe` status403
                entryExists <- query @TimesheetEntry |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#staffId, unpackId trialStaff.id) |> fetchExists
                entryExists `shouldBe` False

        it "rejects malformed required timesheet ids without creating an entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Required Venue"
                user <- createUserRecord "timesheet-required@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("staffId", "not-a-uuid")
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "09:00")
                            , ("endTime", "17:00")
                            ]

                response `responseStatusShouldBe` status200
                entryExists <- query @TimesheetEntry |> filterWhere (#venueId, unpackId venue.id) |> fetchExists
                entryExists `shouldBe` False

        it "renders the delete action in the HTMX timesheet edit modal footer with a single confirm source" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-delete-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (EditTimesheetEntryAction entry.id)
                            [ ("weekOffset", "0")
                            , ("showApproved", "false")
                            , ("showAllStaff", "true")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (pathTo (DeleteTimesheetEntryAction entry.id))
                response `responseBodyShouldContain` "name=\"_method\" value=\"DELETE\""
                response `responseBodyShouldContain` "hx-confirm=\"Delete this timesheet entry? This cannot be undone.\""
                response `responseBodyShouldNotContain` "onsubmit=\"return window.confirm"
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "app-modal-footer-start"
                response `responseBodyShouldNotContain` "js-delete"

        it "renders the page-modal delete action with native confirmation only" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-page-delete-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (EditTimesheetEntryAction entry.id)
                        [ ("weekOffset", "0")
                        , ("showApproved", "false")
                        , ("showAllStaff", "true")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs (pathTo (DeleteTimesheetEntryAction entry.id))
                response `responseBodyShouldContain` "name=\"_method\" value=\"DELETE\""
                response `responseBodyShouldContain` "onsubmit=\"return window.confirm(&quot;Delete this timesheet entry? This cannot be undone.&quot;);\""
                response `responseBodyShouldNotContain` "hx-confirm=\"Delete this timesheet entry? This cannot be undone.\""
                response `responseBodyShouldContain` "app-modal-footer-start"
                response `responseBodyShouldNotContain` "js-delete"

        it "scopes timesheet day fragments to the current viewer visibility" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-fragment-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-fragment-worker-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-fragment-worker-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                _ <- createVenueMembershipRecord venue workerBUser "worker"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Hours"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Hours"
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerB (fromGregorian 2025 1 7)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Ava Hours"
                managerResponse `responseBodyShouldContain` "Bea Hours"
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldContain` "Ava Hours"
                workerResponse `responseBodyShouldNotContain` "Bea Hours"

        it "renders a roster-derived suggestion for a complete shift on a live roster" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Venue"
                manager <- createUserRecord "timesheet-suggestion-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Rita" "Rostered"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Dinner"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Rostered"
                response `responseBodyShouldContain` "Rita Rostered"
                response `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                response `responseBodyShouldContain` "class=\"timesheet-entry-card timesheet-suggestion-card\""
                response `responseBodyShouldContain` cs (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })
                response `responseBodyShouldContain` cs (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })
                response `responseBodyShouldContain` "timesheet-entry-card-link"
                response `responseBodyShouldContain` "timesheet-shape-bar"
                response `responseBodyShouldContain` "timesheet-shape-segment-shift"
                response `responseBodyShouldContain` "timesheet-shape-segment-break"
                response `responseBodyShouldContain` ">Create</button>"
                response `responseBodyShouldNotContain` ">Edit first</a>"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "shows future live-roster suggestions immediately" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Future Suggestion Venue"
                workerUser <- createUserRecord "timesheet-future-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Faye" "Future"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 3 True
                rosterDay <- createRosterDayRecord rosterWeek 4
                slotName <- fetchSlotNameRecord venue "Late"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 12 0 0))
                        |> set #endTime (Just (TimeOfDay 20 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 3 }
                        [("showSuggestions", "true")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "hides suggestions with the URL-scoped filter and preserves that filter in week navigation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Filter Venue"
                manager <- createUserRecord "timesheet-suggestion-filter-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-filter-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Fiona" "Filtered"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Lunch"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                _ <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 10 0 0))
                        |> set #endTime (Just (TimeOfDay 16 0 0))
                        |> set #durationMinutes (Just 360)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("showSuggestions", "false")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Show suggestions"
                response `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                response `responseBodyShouldContain` "showSuggestions=false"
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=1&amp;showApproved=false&amp;showAllStaff=true&amp;showSuggestions=false"

        it "quick-creates one unapproved snapshot from an authorized roster suggestion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Create Venue"
                workerUser <- createUserRecord "timesheet-suggestion-create-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Quinn" "QuickCreate"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 15 15 0))
                        |> set #durationMinutes (Just 375)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
                        , ("showApproved", "false")
                        , ("showAllStaff", "true")
                        , ("showSuggestions", "true")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.venueId `shouldBe` unpackId venue.id
                entry.staffId `shouldBe` unpackId worker.id
                entry.shiftTypeId `shouldBe` unpackId shiftType.id
                entry.workedOn `shouldBe` fromGregorian 2025 1 7
                entry.startTime `shouldBe` TimeOfDay 9 0 0
                entry.endTime `shouldBe` TimeOfDay 15 15 0
                entry.hadBreak `shouldBe` True
                entry.breakStartTime `shouldBe` Just (TimeOfDay 14 30 0)
                entry.breakEndTime `shouldBe` Just (TimeOfDay 15 0 0)
                entry.breakMinutes `shouldBe` 30
                entry.isApproved `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)
                version <- query @TimesheetEntryVersion |> fetchOne
                version.payload `shouldBe` Aeson.object
                    [ "source" Aeson..= ("roster_suggestion" :: Text)
                    , "rosterSlotId" Aeson..= tshow rosterSlot.id
                    ]

        it "scopes suggestion visibility and creation to the viewer's timesheet authority" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Authority Venue"
                manager <- createUserRecord "timesheet-suggestion-authority-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-suggestion-authority-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-suggestion-authority-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                _ <- createVenueMembershipRecord venue workerBUser "worker"
                workerA <- createStaffRecord venue (Just workerAUser) "Alice" "Authority"
                workerB <- createStaffRecord venue (Just workerBUser) "Bob" "Boundary"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                slotA <- createRosterSlotRecord rosterDay slotName (Just workerA) 0
                slotB <- createRosterSlotRecord rosterDay slotName (Just workerB) 1
                slotA <- updateRecord
                    ( slotA
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )
                slotB <- updateRecord
                    ( slotB
                        |> set #startTime (Just (TimeOfDay 10 0 0))
                        |> set #endTime (Just (TimeOfDay 18 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("showSuggestions", "true")]
                workerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                workerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                deniedResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("weekOffset", "0"), ("showSuggestions", "true")]
                deniedResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("showAllStaff", "true"), ("showSuggestions", "true"), ("staffFilterId", idToParam workerA.id)]
                managerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                managerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                -- URL filters limit presentation, not the manager's venue-wide
                -- Timesheets authority over an otherwise eligible source.
                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("weekOffset", "0"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                createdResponse `responseStatusShouldBe` status302
                createdEntry <- query @TimesheetEntry |> fetchOne
                createdEntry.staffId `shouldBe` unpackId workerB.id

        it "rejects materialization when the roster source changes after projection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Stale Venue"
                workerUser <- createUserRecord "timesheet-suggestion-stale-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Stella" "Stale"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                materializationResult <- withUserAndCurrentVenue workerUser venue.id do
                    withCurrentControllerContext do
                        suggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlot.id >>= maybe (expectationFailure "Expected initial suggestion" >> error "unreachable") pure
                        _ <- updateRecord (rosterSlot |> set #endTime (Just (TimeOfDay 18 0 0)) |> set #durationMinutes (Just 540))
                        let entry = newTimesheetEntryFromSuggestion (unpackId venue.id) suggestion
                        materializeTimesheetSuggestionMutation 0 suggestion entry

                materializationResult `shouldBe` Nothing
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "materializes a suggestion idempotently under concurrent submissions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Concurrent Venue"
                workerUser <- createUserRecord "timesheet-suggestion-concurrent-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Connie" "Concurrent"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                results <- runConcurrentTimesheetActions 8 do
                    withUserAndCurrentVenue workerUser venue.id do
                        callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                            [("weekOffset", "0"), ("showSuggestions", "true")]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)
                activeEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                length activeEntries `shouldBe` 1

        it "lets staff edit rostered values before creating the linked snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Edit Venue"
                workerUser <- createUserRecord "timesheet-suggestion-edit-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Edie" "Editor"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                formResponse <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                            [("weekOffset", "0"), ("showSuggestions", "true")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldContain` "This form starts from the current roster shift"
                formResponse `responseBodyShouldContain` "name=\"staffId\""
                formResponse `responseBodyShouldNotContain` "<select name=\"staffId\""
                formResponse `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                formResponse `responseBodyShouldContain` "name=\"endTime\" value=\"17:00\""

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
                        , ("showSuggestions", "true")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "10:00")
                        , ("endTime", "16:00")
                        ]

                createResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.startTime `shouldBe` TimeOfDay 10 0 0
                entry.endTime `shouldBe` TimeOfDay 16 0 0
                entry.hadBreak `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

        it "warns that an ad-hoc entry is separate when a roster suggestion exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Ad Hoc Warning Venue"
                workerUser <- createUserRecord "timesheet-ad-hoc-warning-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Ada" "AdHoc"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                _ <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            , ("showSuggestions", "false")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "This creates a separate timesheet entry"
                response `responseBodyShouldContain` "The rostered suggestion will remain"
                response `responseBodyShouldContain` cs (pathTo CreateTimesheetEntryAction)
                response `responseBodyShouldNotContain` cs (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("weekOffset", "0")
                        , ("showSuggestions", "true")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "12:00")
                        , ("endTime", "14:00")
                        ]
                createResponse `responseStatusShouldBe` status302
                adHocEntry <- query @TimesheetEntry |> fetchOne
                adHocEntry.sourceRosterSlotId `shouldBe` Nothing

                refreshedResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("showSuggestions", "true")]
                refreshedResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

        it "restores a suggestion after its linked entry is soft-deleted and preserves both snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Restore Venue"
                workerUser <- createUserRecord "timesheet-suggestion-restore-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Rory" "Restore"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )
                oldEntry <-
                    newRecord @TimesheetEntry
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId worker.id)
                        |> set #shiftTypeId (unpackId shiftType.id)
                        |> set #workedOn (fromGregorian 2025 1 7)
                        |> set #startTime (TimeOfDay 9 0 0)
                        |> set #endTime (TimeOfDay 17 0 0)
                        |> set #sourceRosterSlotId (Just (unpackId rosterSlot.id))
                        |> createRecord
                now <- getCurrentTime
                _ <- updateRecord
                    ( oldEntry
                        |> set #deletedAt (Just now)
                        |> set #deletedByUserId (Just (unpackId workerUser.id))
                        |> set #deleteReason (Just "test_deleted")
                    )

                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("showSuggestions", "true")]
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [("weekOffset", "0"), ("showSuggestions", "true")]

                createResponse `responseStatusShouldBe` status302
                linkedEntries :: [TimesheetEntry] <-
                    query @TimesheetEntry
                        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
                        |> orderByAsc #createdAt
                        |> fetch
                length linkedEntries `shouldBe` 2
                length (filter (isNothing . (.deletedAt)) linkedEntries) `shouldBe` 1

        it "keeps roster-derived staff, date, and source immutable during edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Immutable Venue"
                manager <- createUserRecord "timesheet-suggestion-immutable-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosteredUser <- createUserRecord "timesheet-suggestion-immutable-rostered@example.com" "staff" True
                otherUser <- createUserRecord "timesheet-suggestion-immutable-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue rosteredUser "worker"
                _ <- createVenueMembershipRecord venue otherUser "worker"
                rosteredStaff <- createStaffRecord venue (Just rosteredUser) "Robin" "Rostered"
                otherStaff <- createStaffRecord venue (Just otherUser) "Sam" "Separate"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just rosteredStaff) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #startTime (Just (TimeOfDay 9 0 0))
                        |> set #endTime (Just (TimeOfDay 17 0 0))
                        |> set #durationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                creationResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [("weekOffset", "0"), ("showAllStaff", "true"), ("showSuggestions", "true")]
                creationResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 1)
                entry <- query @TimesheetEntry |> fetchOne

                editResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams EditTimesheetEntryAction { timesheetEntryId = entry.id }
                            [("weekOffset", "0"), ("showAllStaff", "true")]
                editResponse `responseStatusShouldBe` status200
                editResponse `responseBodyShouldContain` "Rostered"
                editResponse `responseBodyShouldNotContain` "<select name=\"staffId\""

                updateResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("weekOffset", "0")
                        , ("showAllStaff", "true")
                        , ("staffId", idToParam otherStaff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-08")
                        , ("startTime", "10:00")
                        , ("endTime", "16:00")
                        ]
                updateResponse `responseStatusShouldBe` status403

                unchanged <- fetch entry.id
                unchanged.staffId `shouldBe` unpackId rosteredStaff.id
                unchanged.workedOn `shouldBe` fromGregorian 2025 1 7
                unchanged.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

        it "shows approved entries to staff with a disabled approved button" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Approved Staff Venue"
                manager <- createUserRecord "timesheet-approved-marker-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-approved-marker-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                worker <- createStaffRecord venue (Just workerUser) "Ava" "Approved"
                _ <- createApprovedTimesheetEntryRecord venue worker manager (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }
                        [("showApproved", "true")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Approved"
                response `responseBodyShouldContain` "data-timesheet-entry-approved=\"true\""
                response `responseBodyShouldContain` ">Approved</button>"
                response `responseBodyShouldContain` "disabled"
                response `responseBodyShouldNotContain` "UnapproveTimesheetEntry"

        it "applies manager timesheet filters from the week query params" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Filter Venue"
                manager <- createUserRecord "timesheet-filter-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-filter-worker-a@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                managerStaff <- createStaffRecord venue (Just manager) "Mia" "Manager"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Hours"
                _ <- createApprovedTimesheetEntryRecord venue managerStaff manager (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("showApproved", "false")
                        , ("showAllStaff", "false")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hide approved"
                response `responseBodyShouldContain` "Show all staff"
                response `responseBodyShouldContain` "app-toggle-button btn-success"
                response `responseBodyShouldContain` "app-toggle-button btn-outline-success"
                response `responseBodyShouldContain` "aria-pressed=\"true\""
                response `responseBodyShouldContain` "No entries for this day."
                response `responseBodyShouldNotContain` "timesheet-entry-staff-name\">Ava Hours"
                response `responseBodyShouldNotContain` "timesheet-entry-card\" data-timesheet-entry-approved=\"true\""

        it "renders FrontendSurface refresh urls with current timesheet filters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Live Filter Url Venue"
                manager <- createUserRecord "timesheet-live-filter-url-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just manager) "Lina" "Filtered"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("showApproved", "false")
                        , ("showAllStaff", "true")
                        , ("staffFilterId", idToParam staff.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldNotContain` "data-live-update-url="
                response `responseBodyShouldContain` "showApproved=false"
                response `responseBodyShouldContain` "showAllStaff=true"
                response `responseBodyShouldContain` cs ("staffFilterId=" <> tshow staff.id)
                response `responseBodyShouldNotContain` "showApproved=true"

        it "filters manager timesheet views to a selected staff member" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Staff Filter Venue"
                manager <- createUserRecord "timesheet-staff-filter-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                workerAUser <- createUserRecord "timesheet-staff-filter-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-staff-filter-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerAUser "worker"
                _ <- createVenueMembershipRecord venue workerBUser "worker"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Filter"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Filter"
                entryA <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerB (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("showApproved", "true")
                        , ("showAllStaff", "true")
                        , ("staffFilterId", idToParam workerA.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"staffFilterId\""
                response `responseBodyShouldContain` "timesheet-entry-staff-name\">Ava Filter"
                response `responseBodyShouldNotContain` "timesheet-entry-staff-name\">Bea Filter"
                response `responseBodyShouldContain` cs ("href=\"/Timesheets?showApproved=true&amp;showAllStaff=true&amp;showSuggestions=true&amp;staffFilterId=" <> tshow workerA.id <> "\"")
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=-1&amp;showApproved=true&amp;showAllStaff=true&amp;showSuggestions=true&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=1&amp;showApproved=true&amp;showAllStaff=true&amp;showSuggestions=true&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` "timesheet-entry-card-link"
                response `responseBodyShouldContain` cs (pathTo (EditTimesheetEntryAction entryA.id))

        it "renders a shape bar for valid after-midnight timesheet entries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet After Midnight Venue"
                manager <- createUserRecord "timesheet-after-midnight-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just manager) "Mia" "Manager"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 20)
                _ <-
                    entry
                        |> set #startTime (TimeOfDay 0 15 0)
                        |> set #endTime (TimeOfDay 4 0 0)
                        |> set #hadBreak False
                        |> set #breakStartTime Nothing
                        |> set #breakEndTime Nothing
                        |> set #breakMinutes 0
                        |> updateRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 2 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "12:15"
                response `responseBodyShouldContain` "4:00 AM"
                response `responseBodyShouldContain` "timesheet-shape-bar"
                response `responseBodyShouldContain` "timesheet-shape-segment-shift"

        it "renders the timesheet filter menu form against the canonical week path" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Menu Venue"
                manager <- createUserRecord "timesheet-menu-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 2 }
                        [ ("showApproved", "true")
                        , ("showAllStaff", "false")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-toolbar=\"timesheets\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"quick\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"navigation\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"settings\""
                response `responseBodyShouldContain` "btn btn-outline-secondary app-week-nav-button"
                response `responseBodyShouldContain` "href=\"/Timesheets?showApproved=true&amp;showAllStaff=false&amp;showSuggestions=true\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=1&amp;showApproved=true&amp;showAllStaff=false&amp;showSuggestions=true\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=3&amp;showApproved=true&amp;showAllStaff=false&amp;showSuggestions=true\""
                response `responseBodyShouldContain` "action=\"/ShowTimesheetWeek?weekOffset=2\""
                response `responseBodyShouldContain` "hx-get=\"/ShowTimesheetWeek?weekOffset=2\""
                response `responseBodyShouldContain` "name=\"weekOffset\" value=\"2\""
                response `responseBodyShouldNotContain` "action=\"/ShowTimesheetWeek?weekOffset=2&amp;showApproved=true"
                response `responseBodyShouldNotContain` "hx-get=\"/ShowTimesheetWeek?weekOffset=2&amp;showApproved=true"

        it "keeps comment-only edits from resetting approved timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Comments Venue"
                manager <- createUserRecord "timesheet-comments-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-comments-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue workerUser "worker"
                staff <- createStaffRecord venue (Just workerUser) "Cora" "Comment"
                today <- utctDay <$> getCurrentTime
                entry <- createApprovedTimesheetEntryRecord venue staff manager today

                workerResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("staffId", idToParam staff.id)
                        , ("shiftTypeId", cs (tshow entry.shiftTypeId))
                        , ("workedOn", cs (tshow today))
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("staffComment", "Rooks staff note")
                        , ("managerNote", "worker should not set this")
                        ]

                workerResponse `responseStatusShouldBe` status302
                staffCommentedEntry <- fetch entry.id
                staffCommentedEntry.isApproved `shouldBe` True
                staffCommentedEntry.approvedByUserId `shouldBe` Just (unpackId manager.id)
                staffCommentedEntry.staffComment `shouldBe` Just "Rooks staff note"
                staffCommentedEntry.managerNote `shouldBe` Nothing

                managerEditResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (EditTimesheetEntryAction entry.id)
                managerEditResponse `responseStatusShouldBe` status200
                managerEditResponse `responseBodyShouldContain` "Staff comment"
                managerEditResponse `responseBodyShouldContain` "Rooks staff note"
                managerEditResponse `responseBodyShouldContain` "Manager note"

                workerEditResponse <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (EditTimesheetEntryAction entry.id)
                workerEditResponse `responseStatusShouldBe` status200
                workerEditResponse `responseBodyShouldContain` "Staff comment"
                workerEditResponse `responseBodyShouldNotContain` "Manager note"

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("staffId", idToParam staff.id)
                        , ("shiftTypeId", cs (tshow entry.shiftTypeId))
                        , ("workedOn", cs (tshow today))
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("staffComment", "manager should not overwrite")
                        , ("managerNote", "Manager visible note")
                        ]

                managerResponse `responseStatusShouldBe` status302
                managerCommentedEntry <- fetch entry.id
                managerCommentedEntry.isApproved `shouldBe` True
                managerCommentedEntry.staffComment `shouldBe` Just "Rooks staff note"
                managerCommentedEntry.managerNote `shouldBe` Just "Manager visible note"

                versions <- query @TimesheetEntryVersion |> orderByAsc #createdAt |> fetch
                map (inputValue . (.versionAction)) versions `shouldBe` ["updated", "updated"]
                resetAuditExists <- query @AuditEvent |> filterWhere (#eventType, "timesheet_approval_reset") |> fetchExists
                resetAuditExists `shouldBe` False

        it "keeps approved entries hidden after an HTMX timesheet create with hide approved" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Create Hidden Approved Venue"
                manager <- createUserRecord "timesheet-create-hide-approved-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                approvedUser <- createUserRecord "timesheet-approved-worker@example.com" "staff" True
                pendingUser <- createUserRecord "timesheet-pending-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue approvedUser "worker"
                _ <- createVenueMembershipRecord venue pendingUser "worker"
                approvedStaff <- createStaffRecord venue (Just approvedUser) "Ada" "Approved"
                pendingStaff <- createStaffRecord venue (Just pendingUser) "Pia" "Pending"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                _ <- createApprovedTimesheetEntryRecord venue approvedStaff manager (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("weekOffset", "0")
                            , ("showApproved", "false")
                            , ("showAllStaff", "true")
                            , ("staffId", idToParam pendingStaff.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "10:15")
                            , ("endTime", "14:15")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "Timesheet entry created"
                let hiddenCreateTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":1")
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-1")

        it "creating timesheets via HTMX updates the actor fragment and bumps the week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Tess" "Create"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                versionBefore <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "timesheet-create-client")
                        ] do
                            callActionWithParams CreateTimesheetEntryAction
                                [ ("weekOffset", "0")
                                , ("staffId", idToParam staff.id)
                                , ("shiftTypeId", idToParam shiftType.id)
                                , ("workedOn", "2025-01-07")
                                , ("startTime", "09:15")
                                , ("endTime", "17:15")
                                ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "Timesheet entry created"
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let createTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":1")
                createTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-1")

                versionAfter <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)
                versionAfter `shouldBe` versionBefore

        it "editing a timesheet date refreshes both old and new day sections" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-date-move-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just manager) "Tia" "Move"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "timesheet-date-move-client")
                        ] do
                            callActionWithParams (UpdateTimesheetEntryAction entry.id)
                                [ ("weekOffset", "0")
                                , ("staffId", idToParam staff.id)
                                , ("shiftTypeId", idToParam shiftType.id)
                                , ("workedOn", "2025-01-08")
                                , ("startTime", "09:15")
                                , ("endTime", "17:15")
                                ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2\""
                response `responseBodyShouldContain` "Timesheet entry updated"
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let moveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":1")
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":2")
                moveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-1")
                moveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2")

                updatedEntry <- fetch entry.id
                updatedEntry.workedOn `shouldBe` fromGregorian 2025 1 8
                versionAfter <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)
                versionAfter `shouldBe` versionBefore

        it "manager review actions bump the timesheet week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "timesheet-approve-client")] do
                        callAction ApproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let approveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":1")
                approveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-1")
                versionAfter <- currentLiveUpdateVersion (timesheetWeekLiveScope (unpackId venue.id) 0)
                versionAfter `shouldBe` versionBefore

        it "writes an audit event when approving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ApproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` True
                updatedEntry.approvedByUserId `shouldBe` Just (unpackId manager.id)
                updatedEntry.staffPayVersionId `shouldSatisfy` isJust

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approved"
                version.timesheetEntryId `shouldBe` unpackId entry.id
                version.actorUserId `shouldBe` unpackId manager.id

                snapshot <- query @StaffPayVersion |> fetchOne
                updatedEntry.staffPayVersionId `shouldBe` Just (unpackId snapshot.id)
                snapshot.staffId `shouldBe` updatedEntry.staffId

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId manager.id
                auditEvent.eventType `shouldBe` "timesheet_approved"
                auditEvent.targetTable `shouldBe` "timesheet_entries"
                auditEvent.targetId `shouldBe` unpackId entry.id
                auditEvent.sourceChannel `shouldBe` "web"

        it "writes an audit event when unapproving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-unapprove@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Una" "Shift"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 8)

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction UnapproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` False
                updatedEntry.approvedByUserId `shouldBe` Nothing
                updatedEntry.staffPayVersionId `shouldBe` Nothing

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "unapproved"
                version.timesheetEntryId `shouldBe` unpackId entry.id

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "timesheet_unapproved"
                auditEvent.targetId `shouldBe` unpackId entry.id

        it "writes an audit event when editing resets a prior approval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-reset@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just manager) "Ria" "Shift"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 9)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-09")
                        , ("startTime", "09:15")
                        , ("endTime", "17:15")
                        ]

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` False
                parseTimeParam "09:15" `shouldBe` Just updatedEntry.startTime
                parseTimeParam "17:15" `shouldBe` Just updatedEntry.endTime

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approval_reset"
                version.timesheetEntryId `shouldBe` unpackId entry.id

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "timesheet_approval_reset"
                auditEvent.targetId `shouldBe` unpackId entry.id

        it "records a version row before deleting an unapproved timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Del" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("weekOffset", "0")]

                response `responseStatusShouldBe` status302

                retainedEntry <- fetch entry.id
                retainedEntry.deletedAt `shouldSatisfy` isJust
                retainedEntry.deletedByUserId `shouldBe` Just (unpackId manager.id)

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "deleted"
                version.timesheetEntryId `shouldBe` unpackId entry.id

        it "allows deleting an approved timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-protected-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Ada" "Shift"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 11)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("weekOffset", "0")]

                response `responseStatusShouldBe` status302

                retainedEntry <- fetch entry.id
                retainedEntry.deletedAt `shouldSatisfy` isJust
                retainedEntry.deletedByUserId `shouldBe` Just (unpackId manager.id)

                versionCount <- query @TimesheetEntryVersion |> fetchCount
                versionCount `shouldBe` 1

runConcurrentTimesheetActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentTimesheetActions count action = do
    vars <- mapM (const newEmptyMVar) [1 .. count]
    _ <- mapM (\var -> forkIO (try action >>= putMVar var)) vars
    mapM takeMVar vars
