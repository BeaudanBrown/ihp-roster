module Test.Controller.TimesheetsSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      parseTimeParam)
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveSurface (mkTypedDefinedLiveSurface,
                                       typedLiveSurfaceFragmentRefs,
                                       unSurfaceFragmentRefs)
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay)
import Config
import qualified Data.Set as Set
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (getCurrentTime, utctDay)
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
import Test.Support.LiveSurfaceContract
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Timesheets.Mutations (timesheetEntryTouchedResources)
import Web.Timesheets.Projection (TimesheetProjectionFragment (..),
                                  TimesheetProjectionRequest (..),
                                  timesheetDaySectionFragmentRef,
                                  timesheetLiveSurfaceDefinition)
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

                (response, liveSurface, expectedRefs) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let requestKey = TimesheetProjectionRequest 0 False True Nothing
                        let liveSurface = mkTypedDefinedLiveSurface timesheetLiveSurfaceDefinition requestKey
                        let expectedRefs = typedLiveSurfaceFragmentRefs timesheetLiveSurfaceDefinition requestKey [TimesheetProjectionDayColumns]
                        response <- callAction ShowTimesheetWeekAction { weekOffset = 0 }
                        pure (response, liveSurface, unSurfaceFragmentRefs expectedRefs)

                liveSurfaceConfigShouldRoundTrip liveSurface
                liveSurfaceConfigShouldExposeRefs liveSurface expectedRefs
                responseShouldMountLiveSurface response liveSurface

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "timesheet_week"
                response `responseBodyShouldContain` "data-timesheet-day-offset=\"0\""

        it "records touched resources for timesheet entry mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Touched Timesheet Venue"
                staff <- createStaffRecord venue Nothing "Tim" "Touched"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let weekOffset = venueWeekOffsetForDay venueConfig entry.workedOn

                Set.fromList (timesheetEntryTouchedResources venueConfig [entry])
                    `shouldBe` Set.fromList
                        [ TimesheetWeekResource (unpackId venue.id) weekOffset
                        , TimesheetDayResource (unpackId venue.id) weekOffset 1
                        , StaffTimesheetResource (unpackId staff.id)
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
                        let requestKey = TimesheetProjectionRequest 0 False True Nothing
                        let fragmentRef = timesheetDaySectionFragmentRef requestKey 0
                        callAction ShowTimesheetWeekAction { weekOffset = 0 }
                        response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }
                        let rawFragmentRef =
                                case unSurfaceFragmentRefs [fragmentRef] of
                                    [ref] -> ref
                                    _     -> error "Expected one timesheet fragment ref"
                        pure (response, rawFragmentRef)

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
                response `responseBodyShouldContain` "data-live-update-surface="
                response `responseBodyShouldNotContain` "id=\"timesheet-week-shell\" hx-history-elt"

        it "renders declared timesheet toolbar and day-columns fragment targets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Layout Fragment Venue"
                manager <- createUserRecord "timesheet-layout-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                toolbarResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetToolbarFragmentAction { weekOffset = 0 }
                columnsResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetDayColumnsFragmentAction { weekOffset = 0 }

                toolbarResponse `responseStatusShouldBe` status200
                toolbarResponse `responseBodyShouldContain` "id=\"timesheet-week-toolbar\""
                toolbarResponse `responseBodyShouldContain` "data-live-update-url=\"/ShowTimesheetToolbarFragment"
                columnsResponse `responseStatusShouldBe` status200
                columnsResponse `responseBodyShouldContain` "id=\"timesheet-day-columns\""
                columnsResponse `responseBodyShouldContain` "data-live-update-surface="
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
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "Timesheet Tuesday 07/01"
                response `responseBodyShouldContain` "name=\"startTime\" value=\"12:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"20:00\""
                response `responseBodyShouldNotContain` ">Day<"
                response `responseBodyShouldNotContain` "07/01/2025</div>"

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
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
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

        it "renders live day refresh urls with current timesheet filters" $ withContext do
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
                response `responseBodyShouldContain` "data-live-update-url="
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
                response `responseBodyShouldContain` cs ("href=\"/Timesheets?showApproved=true&amp;showAllStaff=true&amp;staffFilterId=" <> tshow workerA.id <> "\"")
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=-1&amp;showApproved=true&amp;showAllStaff=true&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=1&amp;showApproved=true&amp;showAllStaff=true&amp;staffFilterId=" <> tshow workerA.id)
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
                response `responseBodyShouldContain` "href=\"/Timesheets?showApproved=true&amp;showAllStaff=false\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=1&amp;showApproved=true&amp;showAllStaff=false\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=3&amp;showApproved=true&amp;showAllStaff=false\""
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
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "Pia Pending"
                response `responseBodyShouldContain` "data-timesheet-entry-approved=\"false\""
                response `responseBodyShouldNotContain` "Ada Approved"
                response `responseBodyShouldNotContain` "data-timesheet-entry-approved=\"true\""

        it "creating timesheets via HTMX updates the actor fragment and bumps the week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Tess" "Create"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                versionBefore <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }

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
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "Timesheet entry created"
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""

                versionAfter <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

        it "editing a timesheet date refreshes both old and new day sections" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-date-move-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just manager) "Tia" "Move"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }

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
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "id=\"timesheet-day-section-2\""
                response `responseBodyShouldContain` "Timesheet entry updated"
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""

                updatedEntry <- fetch entry.id
                updatedEntry.workedOn `shouldBe` fromGregorian 2025 1 8
                versionAfter <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

        it "manager review actions bump the timesheet week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "timesheet-approve-client")] do
                        callAction ApproveTimesheetEntryAction { timesheetEntryId = entry.id }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldContain` "hx-swap-oob=\"outerHTML\""
                versionAfter <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId venue.id, weekOffset = 0 }
                versionAfter `shouldBe` versionBefore + 1

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
