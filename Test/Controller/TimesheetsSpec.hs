module Test.Controller.TimesheetsSpec where

import Application.Helper.Audit.Vocabulary (AuditEventType (TimesheetApprovedAudit),
                                            auditEventTypeText)
import Application.Helper.Controller (parseTimeParam)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountConfig (..),
                                                            FrontendSurfaceMountedFragment (..),
                                                            SurfaceImpl (..))
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as TimesheetsLive
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (currentOperationalDayForVenue)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.VenueTime (RepeatedTimeOccurrence (..),
                              melbourneTimeZoneName)
import Application.VenueTime.Model (ShiftBoundaryInput (..),
                                    applyRosterSlotBoundaries,
                                    authoritativeBreakElapsedSeconds,
                                    authoritativeBreakStartLocalTime,
                                    authoritativeBreakStartOccurrence,
                                    authoritativeElapsedSeconds,
                                    authoritativeStartLocalTime,
                                    decodeTimesheetTiming,
                                    resolveShiftBoundaries,
                                    storedInstantOccurrence,
                                    timesheetEntryBoundaries,
                                    timesheetEntryElapsedSeconds,
                                    timesheetEntryOperationalDate)
import Config
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.Controller.Response (ResponseException (..))
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue, sqlExecDiscardResult)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Test.Support.Concurrency (runConcurrentActionsImmediately)
import Test.Support.SurfaceContract
import Web.Controller.Timesheets ()
import Web.FrontController ()
import Web.Routes
import Web.Timesheets.FrontendSurface
import Web.Timesheets.Mutations (approveTimesheetEntryMutation,
                                 createTimesheetEntryMutation,
                                 deleteTimesheetEntryMutation,
                                 materializeAndApproveTimesheetSuggestionMutation,
                                 materializeTimesheetSuggestionMutation,
                                 timesheetEntryTouchedResourcesForScopes,
                                 unapproveTimesheetEntryMutation,
                                 updateTimesheetEntryMutation)
import Web.Timesheets.Projection (TimesheetFormContext (..),
                                  TimesheetFormReferences (..),
                                  TimesheetProjectionFragment (..),
                                  TimesheetProjectionRequest (..),
                                  fetchTimesheetFormContext,
                                  fetchTimesheetSuggestionForRosterSlot,
                                  noReferencedTimesheetOptions)
import Web.Timesheets.Responses (requireTimesheetCalendarResult)
import Web.Timesheets.Suggestion (TimesheetSuggestion (..),
                                  newTimesheetEntryFromSuggestion)
import Web.Timesheets.Validation (TimesheetCalendarConflict (..),
                                  prepareTimesheetEdit)
import Web.Types
import qualified Web.View.Timesheets.Index as TimesheetsView

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "TimesheetsController" do
        it "redirects unauthenticated users through shared controller middleware" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            actionResponsesShouldHaveStatus status302
                [ ("index", callAction TimesheetsAction)
                , ("week", callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0))))
                , ("day fragment", callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 0 ) (testAnchorForOffset 0)) })
                , ("new entry", callAction NewTimesheetEntryAction)
                , ("create entry", callAction CreateTimesheetEntryAction)
                , ("approve", callAction ApproveTimesheetEntryAction { timesheetEntryId = entryId })
                , ("unapprove", callAction UnapproveTimesheetEntryAction { timesheetEntryId = entryId })
                ]

        it "redirects venue-less super-admins from timesheets to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "timesheets-bootstrap-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- withUser user do
                    callAction TimesheetsAction

                response `responseStatusShouldBe` status302
                responseHeaders response `shouldContain` [("Location", "http://localhost/Support")]

        it "renders a subscribed timesheet shell for authenticated viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-shell@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Tess" "Viewer"

                (response, mountConfig, expectedRefs) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWindowStart = testAnchorForOffset (0 ), timesheetWindowEnd = addDays 7 (testAnchorForOffset (0 )), timesheetCalendarRevision = 1}
                        let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing, timesheetsMountRosterGroupFilterId = Nothing }
                        let impl = timesheetsSurfaceImpl scope mountState
                        response <- callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        pure (response, impl.surfaceImplMountConfig, impl.surfaceImplMountConfig.mountFragments)

                mountConfig.mountSurfaceName `shouldBe` "timesheets"
                mountConfig.mountScopeKey `shouldBe` "timesheets:" <> tshow (unpackId venue.id) <> ":2025-01-06:2025-01-13:1"
                expectedRefs `shouldNotBe` []

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"timesheets\""
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldNotContain` "data-live-update-surface="
                response `responseBodyShouldContain` "timesheets:"
                response `responseBodyShouldContain` "data-timesheet-operational-date=\"2025-01-06\""
                response `responseBodyShouldContain` "hx-sync=\"closest #timesheet-week-shell:replace\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"navigate-timesheet-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-timesheet-hide-approved\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-timesheet-show-suggestions\""
                response `responseBodyShouldNotContain` "timesheet-week-shell-sync-custom-htmx"
                response `responseBodyShouldNotContain` "Pay preview"
                response `responseBodyShouldNotContain` "timesheet-wage-preview"

        it "resets This week navigation canonically" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Current Week Venue"
                user <- createUserRecord "timesheet-current-week@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Current" "Week"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                operationalToday <- currentOperationalDayForVenue venueConfig
                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams TimesheetsAction [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                response `responseStatusShouldBe` status302
                let location = cs <$> lookup "Location" (responseHeaders response)
                location `shouldSatisfy` maybe False (Text.isInfixOf ("anchorDate=" <> tshow operationalToday))
                unauthorizedFilterResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 4)))
                        [("staffFilterId", idToParam staff.id)]
                unauthorizedFilterResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders unauthorizedFilterResponse)
                    `shouldBe` Just "http://localhost/ShowTimesheetWindow?anchorDate=2025-02-03"

        it "ignores additional query fields instead of treating them as Timesheets state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Query Authority Venue"
                user <- createUserRecord "timesheet-query-authority@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Query" "Authority"

                pageResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("unrecognizedDisplayState", "true")]
                pageResponse `responseStatusShouldBe` status200
                lookup "Location" (responseHeaders pageResponse) `shouldBe` Nothing
                pageResponse `responseBodyShouldContain` "id=\"timesheet-week-shell\""

                fragmentResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 0 ) (testAnchorForOffset 0)) }
                        [("unrecognizedDisplayState", "true")]
                fragmentResponse `responseStatusShouldBe` status200
                lookup "Location" (responseHeaders fragmentResponse) `shouldBe` Nothing
                fragmentResponse `responseBodyShouldContain` "id=\"timesheet-day-section-2025-01-06\""

        it "keeps preference redirects and refreshes on explicit windows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Preference Venue"
                user <- createUserRecord "timesheet-preferences@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Perry" "Preferences"
                _ <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 21)
                selectedWindowResponse <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowTimesheetWindowAction "2025-01-20")
                selectedWindowResponse `responseStatusShouldBe` status200
                selectedWindowResponse `responseBodyShouldContain` "data-timesheet-operational-date=\"2025-01-21\""

                hideResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams ToggleTimesheetHideApprovedAction
                        [("anchorDate", "2025-01-20"), ("rosterCalendarRevision", "1"), ("hideApproved", "false")]

                hideResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders hideResponse)
                    `shouldBe` Just "http://localhost/ShowTimesheetWindow?anchorDate=2025-01-20"

                suggestionResponse <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ToggleTimesheetShowSuggestionsAction
                            [("anchorDate", "2025-01-20"), ("rosterCalendarRevision", "1"), ("showTimesheetSuggestions", "false")]

                suggestionResponse `responseStatusShouldBe` status200
                lookup "HX-Push-Url" (responseHeaders suggestionResponse)
                    `shouldBe` Nothing
                suggestionResponse `responseBodyShouldNotContain` "id=\"timesheet-week-toolbar\""
                suggestionResponse `responseBodyShouldNotContain` "id=\"timesheet-day-columns\""
                let preferenceRefreshHeader = cs <$> lookup "HX-Trigger" (responseHeaders suggestionResponse)
                preferenceRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                preferenceRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-toolbar\"")
                preferenceRefreshHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-columns\"")

                preferences <- query @UserPreference
                    |> filterWhere (#userId, unpackId user.id)
                    |> fetchOne
                preferences.hideApproved `shouldBe` False
                preferences.showTimesheetSuggestions `shouldBe` False

                reloaded <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 2)))
                reloaded `responseStatusShouldBe` status200
                reloaded `responseBodyShouldContain` "name=\"hideApproved\" value=\"false\""
                reloaded `responseBodyShouldContain` "name=\"showTimesheetSuggestions\" value=\"false\""

        it "builds typed FrontendSurface mount metadata for the current timesheet query state" $ withContext do
            withCurrentControllerContext do
                let venueId = fromMaybe (error "invalid test UUID") (UUID.fromString "00000000-0000-0000-0000-000000000123")
                let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWindowStart = testAnchorForOffset (2 ), timesheetWindowEnd = addDays 7 (testAnchorForOffset (2 )), timesheetCalendarRevision = 1}
                let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing, timesheetsMountRosterGroupFilterId = Nothing }
                let impl = timesheetsSurfaceImpl scope mountState
                let mountConfig = impl.surfaceImplMountConfig
                let fragmentKeys = map (.mountedFragmentKey) mountConfig.mountFragments
                let fragmentTargets = map (.mountedFragmentTargetId) mountConfig.mountFragments
                let fragmentUrls = map (.mountedFragmentUrl) mountConfig.mountFragments

                impl.surfaceImplName `shouldBe` "timesheets"
                mountConfig.mountSurfaceName `shouldBe` "timesheets"
                mountConfig.mountScopeKey `shouldBe` "timesheets:00000000-0000-0000-0000-000000000123:2025-01-20:2025-01-27:1"
                mountConfig.mountState `shouldBe` Aeson.object
                    [ "staffFilterId" Aeson..= (Nothing :: Maybe Text)
                    , "rosterGroupFilterId" Aeson..= (Nothing :: Maybe Text)
                    ]
                fragmentKeys
                    `shouldBe` [ TimesheetsLive.timesheetToolbarLiveFragment
                               , TimesheetsLive.timesheetDayColumnsLiveFragment
                               , TimesheetsLive.timesheetSidePanelContentLiveFragment
                               ]
                        <> map TimesheetsLive.timesheetDaySectionLiveFragment [testAnchorForOffset 2 .. addDays 6 (testAnchorForOffset 2)]
                fragmentTargets `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns", "timesheet-side-panel-content"] <> map (\operationalDate -> "timesheet-day-section-" <> tshow operationalDate) [testAnchorForOffset 2 .. addDays 6 (testAnchorForOffset 2)]
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "anchorDate=2025-01-20")

        it "touches every overlapping explicit active window for timesheet mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Touched Timesheet Venue"
                staff <- createStaffRecord venue Nothing "Tim" "Touched"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                entry <-
                    entry
                        |> set #operationalDate (fromGregorian 2025 1 12)
                        |> setTestWorkedOn (fromGregorian 2025 1 13)
                        |> setTestStartTime (TimeOfDay 2 0 0)
                        |> setTestEndTime (TimeOfDay 5 0 0)
                        |> updateRecord
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn entry.operationalDate

                let overlappingWindowStart = addDays 4 windowStart
                Set.fromList
                    ( timesheetEntryTouchedResourcesForScopes
                        venueConfig
                        [(unpackId venue.id, overlappingWindowStart, addDays 7 overlappingWindowStart, 99)]
                        [entry]
                    )
                    `shouldBe` Set.fromList
                        [ timesheetWeekResource (unpackId venue.id) windowStart (addDays 7 windowStart)
                        , timesheetWeekResource (unpackId venue.id) overlappingWindowStart (addDays 7 overlappingWindowStart)
                        , timesheetDayResource (unpackId venue.id) entry.operationalDate
                        ]

        it "rejects a timesheet mutation from a stale roster calendar revision" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Stale Timesheet Calendar Venue"
                user <- createUserRecord "stale-timesheet-calendar@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Stale" "Calendar"
                payLevel <- createPayLevelRecord venue "Stale calendar level"
                _ <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #rosterWeekStartsOn 2)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06")
                            , ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam staff.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "09:00")
                            , ("endTime", "17:00")
                            ]

                response `responseStatusShouldBe` status409
                lookup "HX-Refresh" (responseHeaders response) `shouldBe` Just "true"
                response `responseBodyShouldContain` "The roster calendar changed. Review the refreshed window and try again."
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "returns typed locked-calendar failures before effects and preserves native/HTMX conflict responses" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Locked Timesheet Calendar"
                manager <- createUserRecord "locked-calendar-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Locked" "Calendar"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                let scope = TimesheetWeekScopeValue (unpackId venue.id) (fromGregorian 2025 1 6) (fromGregorian 2025 1 13) 0
                withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                        let submittedRequest = ?request { queryString =
                                [ ("staffId", Just (idToParam staff.id))
                                , ("shiftTypeId", Just (cs (tshow entry.shiftTypeId)))
                                , ("workedOn", Just "2025-01-07")
                                , ("startTime", Just "09:00")
                                , ("endTime", Just "18:00")
                                ] }
                        let ?request = submittedRequest
                        editIntent <- prepareTimesheetEdit venueConfig Nothing entry >>= \case
                            Left _ -> expectationFailure "Expected validated edit intent" >> error "unreachable"
                            Right intent -> pure intent
                        outcomes <- sequence
                            [ fmap (fmap (const ())) (updateTimesheetEntryMutation scope editIntent)
                            , fmap (fmap (const ())) (createTimesheetEntryMutation scope entry)
                            , fmap (fmap (const ())) (deleteTimesheetEntryMutation scope entry)
                            , fmap (fmap (const ())) (approveTimesheetEntryMutation scope entry)
                            , fmap (fmap (const ())) (unapproveTimesheetEntryMutation scope entry)
                            ]
                        outcomes `shouldBe` replicate 5 (Left TimesheetCalendarChanged)
                        forM_ [(False, status403), (True, status409)] \(htmx, expectedStatus) -> do
                            withRequestHeaders (if htmx then [("HX-Request", "true")] else []) do
                                response <- withCurrentControllerContext $
                                    Exception.try @ResponseException (requireTimesheetCalendarResult (Left TimesheetCalendarChanged :: Either TimesheetCalendarConflict ()))
                                case response of
                                    Right () -> expectationFailure "Expected terminal calendar response"
                                    Left (ResponseException rejected) -> do
                                        rejected `responseStatusShouldBe` expectedStatus
                                        lookup "HX-Refresh" (responseHeaders rejected) `shouldBe` if htmx then Just "true" else Nothing
                unchanged <- fetch entry.id
                unchanged.deletedAt `shouldBe` Nothing
                unchanged.startsAt `shouldBe` entry.startsAt
                unchanged.endsAt `shouldBe` entry.endsAt
                unchanged.isApproved `shouldBe` entry.isApproved
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 0)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` 0)

        it "keeps native stale-calendar redirect ahead of malformed form fields without effects" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Native stale timesheet"
                manager <- createUserRecord "native-stale-timesheet@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06")
                        , ("rosterCalendarRevision", "0")
                        , ("staffId", "malformed")
                        , ("hadBreak", "malformed")
                        ]
                response `responseStatusShouldBe` status302
                lookup "HX-Refresh" (responseHeaders response) `shouldBe` Nothing
                lookup "Location" (responseHeaders response) `shouldSatisfy` maybe False (Text.isInfixOf "2025-01-06" . cs)
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 0)

        it "denies foreign entry edits before parsing the missing mutation calendar" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet authorized venue"
                foreignVenue <- createVenueWithConfig "Timesheet foreign venue"
                manager <- createUserRecord "foreign-timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord foreignVenue Nothing "Foreign" "Staff"
                entry <- createTimesheetEntryRecord foreignVenue staff (fromGregorian 2025 1 7)
                forM_ [[], [("HX-Request", "true")]] \headers -> do
                    response <- withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders headers do
                            callActionWithParams (UpdateTimesheetEntryAction entry.id) [("staffId", "malformed")]
                    response `responseStatusShouldBe` status403
                unchanged <- fetch entry.id
                unchanged.startsAt `shouldBe` entry.startsAt
                unchanged.staffId `shouldBe` entry.staffId
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 0)

        it "denies unauthenticated users through the timesheet surface fragment contract" $ withContext do
            response <- callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 0 ) (testAnchorForOffset 0)) }

            liveFragmentResponseShouldBeDenied status302 response

        it "renders the declared timesheet day fragment target for authorized viewers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Fragment Contract Venue"
                user <- createUserRecord "timesheet-fragment-contract@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Tara" "Target"

                (response, fragmentRef) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWindowStart = testAnchorForOffset (0 ), timesheetWindowEnd = addDays 7 (testAnchorForOffset (0 )), timesheetCalendarRevision = 1}
                        let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing, timesheetsMountRosterGroupFilterId = Nothing }
                        let daySectionRef =
                                timesheetsCandidateMountedFragments scope mountState
                                    |> find (\fragment -> fragment.mountedFragmentKey == TimesheetsLive.timesheetDaySectionLiveFragment (testAnchorForOffset 0))
                                    |> fromMaybe (error "Expected day section fragment ref")
                        callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        response <- callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 0 ) (testAnchorForOffset 0)) }
                        pure (response, daySectionRef)

                liveFragmentResponseShouldRenderTarget response fragmentRef

        it "renders the typed outerHTML Timesheets shell for HTMX window navigation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet HTMX Fragment Venue"
                manager <- createUserRecord "timesheet-htmx-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 1)))
                            [ ("anchorDate", "2025-01-13"), ("rosterCalendarRevision", "1")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"timesheet-week-shell\""
                response `responseBodyShouldContain` "id=\"timesheet-week-toolbar\""
                response `responseBodyShouldContain` "id=\"timesheet-day-columns\""
                response `responseBodyShouldContain` "data-bepis-surface=\"timesheets\""
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""

        it "renders declared Timesheets toolbar, day-columns, and side-panel fragment targets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Layout Fragment Venue"
                manager <- createUserRecord "timesheet-layout-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                toolbarResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowtimesheetToolbarLiveFragmentAction { anchorDate = tshow (testAnchorForOffset 0)  }
                columnsResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowtimesheetDayColumnsLiveFragmentAction { anchorDate = tshow (testAnchorForOffset 0)  }
                sidePanelResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate = tshow (testAnchorForOffset 0)  }

                toolbarResponse `responseStatusShouldBe` status200
                toolbarResponse `responseBodyShouldContain` "id=\"timesheet-week-toolbar\""
                toolbarResponse `responseBodyShouldNotContain` "data-live-update-url="
                columnsResponse `responseStatusShouldBe` status200
                columnsResponse `responseBodyShouldContain` "id=\"timesheet-day-columns\""
                columnsResponse `responseBodyShouldNotContain` "data-live-update-surface="
                columnsResponse `responseBodyShouldContain` "id=\"timesheet-day-section-2025-01-06\""
                sidePanelResponse `responseStatusShouldBe` status200
                sidePanelResponse `responseBodyShouldContain` "id=\"timesheet-side-panel-content\""
                sidePanelResponse `responseBodyShouldContain` "data-bepis-timesheets-timesheet-side-panel-panel=\"true\""

        it "lets super-admin create timesheet entries for venue staff without a staff identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Timesheet Venue"
                superAdmin <- createUserRecordWithPlatformRole "timesheet-super-admin@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "timesheet-super-admin-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Tess" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]

                response `responseStatusShouldBe` status302
                entry <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> fetchOne
                testHadBreak entry `shouldBe` False

        it "keeps an after-midnight ad-hoc entry on its explicitly selected Operational day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "After Midnight Operational Day Venue"
                workerUser <- createUserRecord "timesheet-after-midnight@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Manager
                worker <- createStaffRecord venue (Just workerUser) "Nora" "Night"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                let operationalDate = fromGregorian 2025 1 12

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-12")
                        , ("startTime", "02:00")
                        , ("endTime", "05:00")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.operationalDate `shouldBe` operationalDate
                boundaries <- either (\reason -> expectationFailure (cs (tshow reason)) >> error "unreachable") pure (timesheetEntryBoundaries entry)
                (authoritativeStartLocalTime boundaries).localDay `shouldBe` fromGregorian 2025 1 13

                sourceWindow <- withUserAndCurrentVenue workerUser venue.id do
                    callAction (ShowTimesheetWindowAction "2025-01-06")
                followingWindow <- withUserAndCurrentVenue workerUser venue.id do
                    callAction (ShowTimesheetWindowAction "2025-01-13")
                let entryPath = cs (pathTo (EditTimesheetEntryAction entry.id))
                sourceWindow `responseBodyShouldContain` entryPath
                followingWindow `responseBodyShouldNotContain` entryPath

        it "preserves a migrated after-midnight ad-hoc instant when saving comments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Historical After Midnight Timesheet Venue"
                manager <- createUserRecord "timesheet-historical-after-midnight@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Harper" "Historical"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2026 8 4)
                entry <-
                    entry
                        |> setTestWorkedOn (fromGregorian 2026 8 4)
                        |> setTestStartTime (TimeOfDay 2 0 0)
                        |> setTestEndTime (TimeOfDay 5 0 0)
                        |> updateRecord
                let originalStartsAt = entry.startsAt
                let originalEndsAt = entry.endsAt

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("anchorDate", "2026-08-04"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", cs (tshow entry.shiftTypeId))
                        , ("workedOn", "2026-08-04")
                        , ("startTime", "02:00")
                        , ("endTime", "05:00")
                        , ("hadBreak", "false")
                        , ("managerNote", "Historical note")
                        ]

                response `responseStatusShouldBe` status302
                updatedEntry <- fetch entry.id
                updatedEntry.startsAt `shouldBe` originalStartsAt
                updatedEntry.endsAt `shouldBe` originalEndsAt
                updatedEntry.managerNote `shouldBe` Just "Historical note"

        it "uses effective worker ownership and actual founder attribution for timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonated Worker Timesheet Venue"
                founder <- createUserRecordWithPlatformRole "timesheet-impersonated-founder@example.com" "staff" (Just SuperAdmin) True
                workerUser <- createUserRecord "timesheet-impersonated-worker@example.com" "staff" True
                otherUser <- createUserRecord "timesheet-impersonated-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                _ <- createVenueMembershipRecord venue otherUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Effective" "Worker"
                otherStaff <- createStaffRecord venue (Just otherUser) "Other" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                _ <- makeStaffTimesheetProducing payLevel otherStaff
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                let entryParams staffId =
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staffId)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]

                (tamperedResponse, ownResponse) <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue workerUser.id))]
                    tamperedResponse <- callActionWithParams CreateTimesheetEntryAction (entryParams otherStaff.id)
                    ownResponse <- callActionWithParams CreateTimesheetEntryAction (entryParams worker.id)
                    pure (tamperedResponse, ownResponse)

                tamperedResponse `responseStatusShouldBe` status403
                ownResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.staffId `shouldBe` unpackId worker.id
                version <- query @TimesheetEntryVersion |> filterWhere (#versionAction, EntryVersionActionEnumCreated) |> fetchOne
                version.actorUserId `shouldBe` unpackId founder.id
                version.payload `shouldSatisfy` \case
                    Aeson.Object payload -> case AesonKeyMap.lookup "requestContext" payload of
                        Just (Aeson.Object requestContext) ->
                            AesonKeyMap.lookup "accessMode" requestContext == Just (Aeson.String "impersonation")
                                && AesonKeyMap.lookup "effectiveUserId" requestContext == Just (Aeson.toJSON workerUser.id)
                        _ -> False
                    _ -> False

        it "parses the generated explicit false had-break transport as no break" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Explicit No Break Venue"
                workerUser <- createUserRecord "timesheet-explicit-no-break@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Nora" "NoBreak"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("hadBreak", "false")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                testHadBreak entry `shouldBe` False
                testBreakStartTime entry `shouldBe` Nothing
                testBreakEndTime entry `shouldBe` Nothing
                testBreakMinutes entry `shouldBe` 0

        it "parses the generated explicit true had-break transport with break times" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Explicit Break Venue"
                workerUser <- createUserRecord "timesheet-explicit-break@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Tara" "TakesBreak"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        , ("hadBreak", "true")
                        , ("breakStartTime", "12:00")
                        , ("breakEndTime", "12:30")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                testHadBreak entry `shouldBe` True
                testBreakStartTime entry `shouldBe` Just (TimeOfDay 12 0 0)
                testBreakEndTime entry `shouldBe` Just (TimeOfDay 12 30 0)
                testBreakMinutes entry `shouldBe` 30

        it "requires an occurrence only for an ambiguous autumn timesheet boundary" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Autumn Boundary Venue"
                manager <- createUserRecord "timesheet-autumn-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Autumn" "Manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                let baseParams =
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-04")
                        , ("startTime", "02:30")
                        , ("endTime", "04:00")
                        , ("hadBreak", "false")
                        ]

                missingOccurrenceResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction baseParams

                missingOccurrenceResponse `responseStatusShouldBe` status200
                missingOccurrenceResponse `responseBodyShouldContain` "Choose whether this is the first or second occurrence."
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"startOccurrence\""
                missingOccurrenceResponse `responseBodyShouldNotContain` "data-time-occurrence-chooser=\"endOccurrence\""
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction (baseParams <> [("startOccurrence", "second")])

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Right (Just SecondOccurrence)
                timesheetEntryElapsedSeconds entry `shouldBe` Right (90 * 60)

        it "creates a positive repeated-hour timesheet with equal local clocks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Equal Autumn Boundary Venue"
                manager <- createUserRecord "timesheet-equal-autumn-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Equal Autumn" "Manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                let baseParams =
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-04")
                        , ("startTime", "02:30")
                        , ("endTime", "02:30")
                        , ("hadBreak", "false")
                        ]

                missingOccurrenceResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction baseParams

                missingOccurrenceResponse `responseStatusShouldBe` status200
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"startOccurrence\""
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"endOccurrence\""
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        (baseParams <> [("startOccurrence", "first"), ("endOccurrence", "second")])

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Right (Just FirstOccurrence)
                storedInstantOccurrence entry.timezone entry.endsAt `shouldBe` Right (Just SecondOccurrence)
                timesheetEntryElapsedSeconds entry `shouldBe` Right (60 * 60)

        it "creates a positive repeated-hour break with equal local clocks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Equal Autumn Break Venue"
                manager <- createUserRecord "timesheet-equal-autumn-break-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Equal Autumn Break" "Manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                let baseParams =
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-04")
                        , ("startTime", "01:30")
                        , ("endTime", "03:30")
                        , ("hadBreak", "true")
                        , ("breakStartTime", "02:30")
                        , ("breakEndTime", "02:30")
                        ]

                missingOccurrenceResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction baseParams

                missingOccurrenceResponse `responseStatusShouldBe` status200
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"breakStartOccurrence\""
                missingOccurrenceResponse `responseBodyShouldContain` "data-time-occurrence-chooser=\"breakEndOccurrence\""
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        (baseParams <> [("breakStartOccurrence", "first"), ("breakEndOccurrence", "second")])

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                breakStart <- maybe (expectationFailure "Expected break start" >> error "unreachable") pure entry.breakStartsAt
                breakEnd <- maybe (expectationFailure "Expected break end" >> error "unreachable") pure entry.breakEndsAt
                storedInstantOccurrence entry.timezone breakStart `shouldBe` Right (Just FirstOccurrence)
                storedInstantOccurrence entry.timezone breakEnd `shouldBe` Right (Just SecondOccurrence)
                testBreakMinutes entry `shouldBe` 60

        it "rejects a nonexistent spring timesheet boundary without normalizing it" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Spring Boundary Venue"
                manager <- createUserRecord "timesheet-spring-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Spring" "Manager"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam staff.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2026-10-03")
                            , ("startTime", "02:30")
                            , ("endTime", "04:00")
                            , ("hadBreak", "false")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "This local time does not exist because clocks move forward."
                response `responseBodyShouldNotContain` "data-time-occurrence-chooser=\"startOccurrence\""
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "rejects a malformed generated had-break transport without creating an entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Invalid Break Transport Venue"
                workerUser <- createUserRecord "timesheet-invalid-break-transport@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Ivy" "InvalidBreak"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam worker.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "09:00")
                            , ("endTime", "17:00")
                            , ("hadBreak", "not-a-boolean")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Had break must be true or false"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "rejects malformed had-break edits without mutating persisted break fields" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Invalid Break Edit Venue"
                manager <- createUserRecord "timesheet-invalid-break-edit@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Mara" "Manager"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                entry <-
                    updateRecord
                        ( entry
                            |> setTestHadBreak True
                            |> setTestBreakStartTime (Just (TimeOfDay 12 0 0))
                            |> setTestBreakEndTime (Just (TimeOfDay 12 30 0))
                            |> setTestBreakMinutes 30
                        )

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateTimesheetEntryAction entry.id)
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam staff.id)
                            , ("shiftTypeId", cs (tshow entry.shiftTypeId))
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "09:00")
                            , ("endTime", "17:00")
                            , ("hadBreak", "not-a-boolean")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Had break must be true or false"
                persistedEntry <- fetch entry.id
                testHadBreak persistedEntry `shouldBe` True
                testBreakStartTime persistedEntry `shouldBe` Just (TimeOfDay 12 0 0)
                testBreakEndTime persistedEntry `shouldBe` Just (TimeOfDay 12 30 0)
                testBreakMinutes persistedEntry `shouldBe` 30

        it "renders HTMX timesheet forms with javascript submission disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-form@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Tess" "Form"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "Timesheet Tuesday 07/01"
                response `responseBodyShouldContain` "name=\"startTime\" value=\"06:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"14:00\""
                response `responseBodyShouldContain` "data-bepis-time-picker-config="
                response `responseBodyShouldContain` "&quot;rangeStart&quot;:&quot;06:00&quot;"
                response `responseBodyShouldContain` "&quot;rangeEnd&quot;:&quot;05:45&quot;"
                response `responseBodyShouldNotContain` ">Day<"
                response `responseBodyShouldNotContain` "07/01/2025</div>"

        it "uses venue time picker window for new timesheet defaults and picker ranges" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Picker Venue"
                user <- createUserRecord "timesheet-picker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Tess" "Picker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #timePickerStartMinuteOfDay 540 |> set #timePickerFinalSelectableMinuteOfDay 780)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"13:00\""
                response `responseBodyShouldContain` "data-bepis-time-picker-config="
                response `responseBodyShouldContain` "&quot;rangeStart&quot;:&quot;09:00&quot;"
                response `responseBodyShouldContain` "&quot;rangeEnd&quot;:&quot;13:00&quot;"

        it "renders, edits, and blocks approval for a corrupt persisted Timesheet without throwing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Corrupt Timing"
                manager <- createUserRecord "timesheet-corrupt-timing@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                importedPayItem <- createImportedXeroPayItemRecord venue manager "Corrupt timing pay" "corrupt-timing-pay" 30
                staff <- createStaffRecord venue Nothing "Tess" "Repair"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                let restoreConstraint = do
                        sqlExecDiscardResult "UPDATE timesheet_entries SET timezone = 'Australia/Melbourne' WHERE id = ?" (Only (unpackId entry.id))
                        sqlExecDiscardResult "ALTER TABLE timesheet_entries DROP CONSTRAINT IF EXISTS timesheet_entries_supported_timezone_check" ()
                        sqlExecDiscardResult "ALTER TABLE timesheet_entries ADD CONSTRAINT timesheet_entries_supported_timezone_check CHECK (timezone = 'Australia/Melbourne')" ()
                (do
                    sqlExecDiscardResult "DO $$ DECLARE constraint_name TEXT; BEGIN SELECT conname INTO constraint_name FROM pg_constraint WHERE conrelid = 'timesheet_entries'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%timezone = %Australia/Melbourne%%'; EXECUTE format('ALTER TABLE timesheet_entries DROP CONSTRAINT %I', constraint_name); END $$" ()
                    sqlExecDiscardResult "UPDATE timesheet_entries SET timezone = 'not-a-zone' WHERE id = ?" (Only (unpackId entry.id))

                    pageResponse <- withUserAndCurrentVenue manager venue.id do
                        callAction (ShowTimesheetWindowAction "2025-01-06")
                    modalResponse <- withUserAndCurrentVenue manager venue.id do
                        withRequestHeaders [("HX-Request", "true")] do
                            callActionWithParams EditTimesheetEntryAction { timesheetEntryId = entry.id }
                                [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                    approvalResponse <- withUserAndCurrentVenue manager venue.id do
                        callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                    pageResponse `responseStatusShouldBe` status200
                    pageResponse `responseBodyShouldContain` "data-timesheet-timing-issue=\"true\""
                    modalResponse `responseStatusShouldBe` status200
                    modalResponse `responseBodyShouldContain` "name=\"startTime\" value=\"\""
                    modalResponse `responseBodyShouldContain` "name=\"endTime\" value=\"\""
                    approvalResponse `responseStatusShouldBe` status409
                    approvalResponse `responseBodyShouldContain` "Repair the Timesheet timing before approval."

                    repairResponse <- withUserAndCurrentVenue manager venue.id do
                        callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam staff.id), ("shiftTypeId", cs (tshow entry.shiftTypeId))
                            , ("workedOn", "2025-01-07"), ("startTime", "09:00"), ("endTime", "17:00")
                            , ("hadBreak", "false")
                            ]

                    repairResponse `responseStatusShouldBe` status302
                    persisted <- fetch entry.id
                    persisted.isApproved `shouldBe` False
                    persisted.timezone `shouldBe` melbourneTimeZoneName
                    decodeTimesheetTiming persisted `shouldSatisfy` either (const False) (const True)
                    query @TimesheetEntryVersion |> filterWhere (#timesheetEntryId, unpackId entry.id) |> fetchCount >>= (`shouldBe` 1)
                 ) `Exception.finally` restoreConstraint

        it "keeps existing Timesheets pages available while invalid venue timing disables creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Invalid Venue Time"
                user <- createUserRecord "timesheet-invalid-venue-time@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Tess" "Repair"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
                _ <- createShiftTypeRecord venue payLevel "Ordinary"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #timezone "not-a-zone")

                pageResponse <- withUserAndCurrentVenue user venue.id do
                    callAction (ShowTimesheetWindowAction "2025-01-06")
                createResponse <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("workedOn", "2025-01-07")
                            ]

                pageResponse `responseStatusShouldBe` status200
                createResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "excludes trial staff from manager timesheet forms and staff filters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Trial Exclusion Venue"
                manager <- createUserRecord "timesheet-trial-manager@example.com" "staff" True
                linkedUser <- createUserRecord "timesheet-linked-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue linkedUser Worker
                linkedStaff <- createStaffRecord venue (Just linkedUser) "Linked" "Worker"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel linkedStaff
                _ <- createShiftTypeRecord venue payLevel "Ordinary"

                formResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("workedOn", "2025-01-07")
                            ]
                weekResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0))) []

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldContain` "Linked Worker"
                formResponse `responseBodyShouldNotContain` "Trial Worker"
                formResponse `responseBodyShouldContain` cs (tshow linkedStaff.id)
                formResponse `responseBodyShouldNotContain` cs (tshow trialStaff.id)
                weekResponse `responseStatusShouldBe` status200
                weekResponse `responseBodyShouldContain` "Linked Worker"
                weekResponse `responseBodyShouldNotContain` "Trial Worker"
                weekResponse `responseBodyShouldNotContain` cs (tshow trialStaff.id)

        it "excludes roster-only staff and shift types from ad-hoc selectors and authorization" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Roster-only Selector Venue"
                manager <- createUserRecord "timesheet-roster-only-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-roster-only-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                managerStaff <- createStaffRecord venue (Just manager) "Mia" "Manager"
                worker <- createStaffRecord venue (Just workerUser) "Rory" "RosterOnly"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (managerStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                ordinaryShift <- createShiftTypeRecord venue payLevel "Timesheet shift"
                rosterOnlyShift <- createShiftTypeRecord venue payLevel "Roster-only shift"
                currentWorker <- fetch worker.id
                _ <- updateRecord (currentWorker |> set #payAssignmentMode RosterOnly |> set #defaultAwardLevelId Nothing)
                _ <- updateRecord (rosterOnlyShift |> set #payAssignmentMode RosterOnly |> set #overrideAwardLevelId Nothing)

                (newContext, editContext) <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        (,)
                            <$> fetchTimesheetFormContext noReferencedTimesheetOptions Nothing
                            <*> fetchTimesheetFormContext
                                TimesheetFormReferences
                                    { referencedStaffId = Just worker.id
                                    , referencedShiftTypeId = Just rosterOnlyShift.id
                                    }
                                Nothing
                map (.id) newContext.formStaffMembers `shouldNotContain` [worker.id]
                map (.id) editContext.formStaffMembers `shouldContain` [worker.id]
                map (.id) newContext.formShiftTypes `shouldNotContain` [rosterOnlyShift.id]
                map (.id) editContext.formShiftTypes `shouldContain` [rosterOnlyShift.id]

                formResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1"), ("workedOn", "2025-01-07")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldNotContain` "Rory RosterOnly"
                formResponse `responseBodyShouldNotContain` "Roster-only shift"
                formResponse `responseBodyShouldContain` "Timesheet shift"

                let createParams staffId shiftTypeId =
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staffId)
                        , ("shiftTypeId", idToParam shiftTypeId)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]
                rosterOnlyStaffResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction (createParams worker.id ordinaryShift.id)
                rosterOnlyShiftResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction (createParams managerStaff.id rosterOnlyShift.id)

                rosterOnlyStaffResponse `responseStatusShouldBe` status403
                rosterOnlyShiftResponse `responseStatusShouldBe` status403
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "derives suggestions only for timesheet-producing staff and shifts and restores them after pay correction" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Roster-only Suggestion Venue"
                manager <- createUserRecord "timesheet-roster-only-suggestion-manager@example.com" "staff" True
                payableUser <- createUserRecord "timesheet-payable-suggestion@example.com" "staff" True
                rosterOnlyUser <- createUserRecord "timesheet-roster-only-suggestion@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue payableUser Worker
                _ <- createVenueMembershipRecord venue rosterOnlyUser Worker
                payableStaff <- createStaffRecord venue (Just payableUser) "Payable" "Worker"
                rosterOnlyStaff <- createStaffRecord venue (Just rosterOnlyUser) "Roster" "Only"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (payableStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                payableShift <- createShiftTypeRecord venue payLevel "Payable shift"
                rosterOnlyShift <- createShiftTypeRecord venue payLevel "Roster-only shift"
                currentRosterOnlyStaff <- fetch rosterOnlyStaff.id
                _ <- updateRecord (currentRosterOnlyStaff |> set #payAssignmentMode RosterOnly |> set #defaultAwardLevelId Nothing)
                _ <- updateRecord (rosterOnlyShift |> set #payAssignmentMode RosterOnly |> set #overrideAwardLevelId Nothing)
                persistedRosterOnlyStaff <- fetch rosterOnlyStaff.id
                persistedRosterOnlyStaff.payAssignmentMode `shouldBe` RosterOnly
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                let createSuggestionSlot rowIndex staff shiftType = do
                        slot <- createRosterSlotRecord rosterDay slotName (Just staff) rowIndex
                        updateRecord
                            ( slot
                                |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay (9 + rowIndex) 0 0) (TimeOfDay (10 + rowIndex) 0 0)
                                |> setTestDurationMinutes (Just 60)
                                |> set #shiftTypeId (Just (unpackId shiftType.id))
                            )
                eligibleSlot <- createSuggestionSlot 0 payableStaff payableShift
                staffSuppressedSlot <- createSuggestionSlot 1 rosterOnlyStaff payableShift
                shiftSuppressedSlot <- createSuggestionSlot 2 payableStaff rosterOnlyShift
                bothSuppressedSlot <- createSuggestionSlot 3 rosterOnlyStaff rosterOnlyShift

                initialSuggestions <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        mapM (fetchTimesheetSuggestionForRosterSlot . (.id))
                            [eligibleSlot, staffSuppressedSlot, shiftSuppressedSlot, bothSuppressedSlot]
                map isJust initialSuggestions `shouldBe` [True, False, False, False]

                tamperedMaterialization <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = eligibleSlot.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam payableStaff.id)
                        , ("shiftTypeId", idToParam rosterOnlyShift.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "10:00")
                        , ("hadBreak", "false")
                        ]
                tamperedMaterialization `responseStatusShouldBe` status403
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                let eligibleSuggestion = fromMaybe (error "expected eligible suggestion") (listToMaybe initialSuggestions >>= \suggestion -> suggestion)
                    tamperedEntry =
                        newTimesheetEntryFromSuggestion (unpackId venue.id) eligibleSuggestion
                            |> set #shiftTypeId (unpackId rosterOnlyShift.id)
                lockedRevalidation <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
                        materializeTimesheetSuggestionMutation scope eligibleSuggestion tamperedEntry
                lockedRevalidation `shouldBe` Right Nothing
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                suppressedStaff <- fetch rosterOnlyStaff.id
                _ <- updateRecord (suppressedStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                restoredSuggestion <- withUserAndCurrentVenue manager venue.id do
                    withCurrentControllerContext do
                        fetchTimesheetSuggestionForRosterSlot staffSuppressedSlot.id
                restoredSuggestion `shouldSatisfy` isJust

        it "rejects tampered manager timesheet creation for trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Trial Tamper Venue"
                manager <- createUserRecord "timesheet-trial-tamper-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                trialStaff <- createStaffRecord venue Nothing "Trial" "Tamper"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
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
                _ <- createVenueMembershipRecord venue user Manager
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
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
                _ <- createVenueMembershipRecord venue user Manager
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (EditTimesheetEntryAction entry.id)
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
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
                _ <- createVenueMembershipRecord venue user Manager
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (EditTimesheetEntryAction entry.id)
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerAUser Worker
                _ <- createVenueMembershipRecord venue workerBUser Worker
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Hours"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Hours"
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerB (fromGregorian 2025 1 7)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 1 ) (testAnchorForOffset 0)) }
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 1 ) (testAnchorForOffset 0)) }

                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldContain` "Ava Hours"
                managerResponse `responseBodyShouldContain` "Bea Hours"
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldContain` "Ava Hours"
                workerResponse `responseBodyShouldNotContain` "Bea Hours"

        it "renders a highlighted roster-derived suggestion without a status badge" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Venue"
                manager <- createUserRecord "timesheet-suggestion-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Rita" "Rostered"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Dinner"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                workerResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Rita Rostered"
                response `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                response `responseBodyShouldContain` "class=\"timesheet-entry-card timesheet-suggestion-card\""
                response `responseBodyShouldNotContain` "<span class=\"badge text-bg-info\">Rostered</span>"
                response `responseBodyShouldContain` cs (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })
                response `responseBodyShouldContain` cs (pathTo NewTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })
                response `responseBodyShouldContain` "timesheet-entry-card-link"
                response `responseBodyShouldContain` "timesheet-shape-bar"
                response `responseBodyShouldContain` "timesheet-shape-segment-shift"
                response `responseBodyShouldContain` "timesheet-shape-segment-break"
                response `responseBodyShouldContain` ">Approve</button>"
                response `responseBodyShouldContain` "approveSuggestion=true"
                response `responseBodyShouldNotContain` ">Create</button>"
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-timesheet-entry-from-suggestion\""
                response `responseBodyShouldNotContain` ">Edit first</a>"
                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldContain` ">Create</button>"
                workerResponse `responseBodyShouldNotContain` "approveSuggestion=true"
                workerResponse `responseBodyShouldNotContain` ">Approve</button>"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "shows future Published-roster suggestions immediately" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Future Suggestion Venue" Nothing "timesheet-future-suggestion-worker@example.com" "Faye" "Future"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Late" 3 4 (fromGregorian 2025 1 31) (TimeOfDay 12 0 0) (TimeOfDay 20 0 0) 480
                    }

                response <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 3)))
                        [("anchorDate", "2025-01-27"), ("rosterCalendarRevision", "1")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow scenario.scenarioRosterSlot.id <> "\"")
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "hides suggestions from the persisted user preference with clean week navigation" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Filter Venue" (Just "timesheet-suggestion-filter-manager@example.com") "timesheet-suggestion-filter-worker@example.com" "Fiona" "Filtered"
                    , suggestionActor = SuggestionManager
                    , suggestionEligibility = PreserveStaffPayDefaults
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Lunch" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 10 0 0) (TimeOfDay 16 0 0) 360
                    }

                now <- getCurrentTime
                _ <- newRecord @UserPreference
                    |> set #userId (unpackId scenario.scenarioActor.id)
                    |> set #showTimesheetSuggestions False
                    |> set #timesheetPreferencesInitializedAt (Just now)
                    |> createRecord
                response <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Show suggestions"
                response `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow scenario.scenarioRosterSlot.id <> "\"")
                response `responseBodyShouldContain` "name=\"showTimesheetSuggestions\" value=\"false\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWindow?anchorDate=2025-01-13\""

        it "quick-creates one unapproved snapshot from an authorized roster suggestion" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Create Venue" Nothing "timesheet-suggestion-create-worker@example.com" "Quinn" "QuickCreate"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0) 375
                    }

                malformedResponse <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("hadBreak", "not-a-boolean")
                            ]

                malformedResponse `responseStatusShouldBe` status200
                malformedResponse `responseBodyShouldContain` "Had break must be true or false"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                response <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.venueId `shouldBe` unpackId scenario.scenarioVenue.id
                entry.staffId `shouldBe` unpackId scenario.scenarioWorker.id
                entry.shiftTypeId `shouldBe` unpackId scenario.scenarioShiftType.id
                testWorkedOn entry `shouldBe` fromGregorian 2025 1 7
                testStartTime entry `shouldBe` TimeOfDay 9 0 0
                testEndTime entry `shouldBe` TimeOfDay 15 15 0
                testHadBreak entry `shouldBe` True
                testBreakStartTime entry `shouldBe` Just (TimeOfDay 14 30 0)
                testBreakEndTime entry `shouldBe` Just (TimeOfDay 15 0 0)
                testBreakMinutes entry `shouldBe` 30
                entry.isApproved `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId scenario.scenarioRosterSlot.id)
                version <- query @TimesheetEntryVersion |> fetchOne
                version.payload `shouldBe` Aeson.object
                    [ "source" Aeson..= ("roster_suggestion" :: Text)
                    , "rosterSlotId" Aeson..= tshow scenario.scenarioRosterSlot.id
                    ]

        it "quick-approves a manager's roster suggestion atomically" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Quick Approve Venue" (Just "timesheet-suggestion-quick-approve-manager@example.com") "timesheet-suggestion-quick-approve-worker@example.com" "Quinn" "Approve"
                    , suggestionActor = SuggestionManager
                    , suggestionEligibility = PreserveStaffPayDefaults
                    , suggestionApprovalFacts = XeroSuggestionApproval "Suggestion approval" "suggestion-approval" 31
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0) 375
                    }

                response <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("approveSuggestion", "true")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.isApproved `shouldBe` True
                entry.approvedByUserId `shouldBe` Just (unpackId scenario.scenarioActor.id)
                entry.activePayCalculationId `shouldSatisfy` isJust
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 2)
                query @AuditEvent |> filterWhere (#eventType, auditEventTypeText TimesheetApprovedAudit) |> fetchCount >>= (`shouldBe` 1)

        it "rolls back quick suggestion creation when manager approval fails" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Approval Rollback Venue" (Just "timesheet-suggestion-approval-rollback-manager@example.com") "timesheet-suggestion-approval-rollback-worker@example.com" "Rollback" "Approval"
                    , suggestionActor = SuggestionManager
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = AwardSuggestionApprovalWithoutSealedFacts
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0) 375
                    }

                response <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("approveSuggestion", "true")
                        ]

                response `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetPayCalculation |> fetchCount >>= (`shouldBe` 0)

        it "preserves an authoritative repeated occurrence through a roster suggestion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet DST Suggestion Venue"
                workerUser <- createUserRecord "timesheet-dst-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Autumn" "Suggestion"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Early"
                rosterWeek <- createRosterWeekRecord venue 64 True
                rosterDay <- createRosterDayRecord rosterWeek 5
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                boundaries <- case resolveShiftBoundaries "Australia/Melbourne" ShiftBoundaryInput
                    { shiftBoundaryDate = fromGregorian 2026 4 5
                    , shiftBoundaryStartTime = TimeOfDay 2 30 0
                    , shiftBoundaryStartOccurrence = Just SecondOccurrence
                    , shiftBoundaryEndTime = TimeOfDay 4 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    } of
                        Left failure -> expectationFailure ("Expected DST suggestion boundaries: " <> Text.unpack (tshow failure)) >> error "unreachable"
                        Right value -> pure value
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> applyRosterSlotBoundaries boundaries
                    )

                let surfaceParams =
                        [ ("anchorDate", "2026-03-30"), ("rosterCalendarRevision", "1")
                        ]
                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 64))) surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Right (Just SecondOccurrence)
                timesheetEntryElapsedSeconds entry `shouldBe` Right (90 * 60)
                testWorkedOn entry `shouldBe` fromGregorian 2026 4 5
                testStartTime entry `shouldBe` TimeOfDay 2 30 0
                testEndTime entry `shouldBe` TimeOfDay 4 0 0

        it "keeps an equal-clock repeated roster interval eligible and renders its elapsed shape" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Equal DST Suggestion Venue"
                workerUser <- createUserRecord "timesheet-equal-dst-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Equal" "Suggestion"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Repeated"
                rosterWeek <- createRosterWeekRecord venue 64 True
                rosterDay <- createRosterDayRecord rosterWeek 5
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                boundaries <- case resolveShiftBoundaries "Australia/Melbourne" ShiftBoundaryInput
                    { shiftBoundaryDate = fromGregorian 2026 4 5
                    , shiftBoundaryStartTime = TimeOfDay 2 30 0
                    , shiftBoundaryStartOccurrence = Just FirstOccurrence
                    , shiftBoundaryEndTime = TimeOfDay 2 30 0
                    , shiftBoundaryEndOccurrence = Just SecondOccurrence
                    , shiftBoundaryBreak = Nothing
                    } of
                        Left failure -> expectationFailure ("Expected equal repeated boundaries: " <> Text.unpack (tshow failure)) >> error "unreachable"
                        Right value -> pure value
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> applyRosterSlotBoundaries boundaries
                    )
                let surfaceParams =
                        [ ("anchorDate", "2026-03-30"), ("rosterCalendarRevision", "1")
                        ]

                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 64))) surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Right (Just FirstOccurrence)
                storedInstantOccurrence entry.timezone entry.endsAt `shouldBe` Right (Just SecondOccurrence)
                timesheetEntryElapsedSeconds entry `shouldBe` Right (60 * 60)
                timing <- either (\reason -> expectationFailure (cs (tshow reason)) >> fail "invalid test timing") pure (decodeTimesheetTiming entry)
                let shapeSegments = TimesheetsView.timesheetShapeSegments TimesheetsView.defaultTimesheetTimelineScale timing
                length shapeSegments `shouldBe` 1
                sum (map TimesheetsView.segmentWidth shapeSegments)
                    `shouldSatisfy` (\width -> abs (width - (100 / 24)) < 0.000001)

        it "derives automatic suggestion breaks from exact elapsed DST duration" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet DST Break Suggestion Venue"
                workerUser <- createUserRecord "timesheet-dst-break-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "DST" "Break"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Early"
                slotName <- fetchSlotNameRecord venue "Early"

                autumnWeek <- createRosterWeekRecord venue 64 True
                autumnDay <- createRosterDayRecord autumnWeek 5
                autumnSlot <- createRosterSlotRecord autumnDay slotName (Just worker) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2026 4 4) (TimeOfDay 22 0 0) (TimeOfDay 5 0 0)
                springWeek <- createRosterWeekRecord venue 90 True
                springDay <- createRosterDayRecord springWeek 5
                springSlot <- createRosterSlotRecord springDay slotName (Just worker) 0
                    >>= updateRecord
                        . set #shiftTypeId (Just (unpackId shiftType.id))
                        . setTestRosterSlotBoundaries (fromGregorian 2026 10 3) (TimeOfDay 22 0 0) (TimeOfDay 5 0 0)

                autumnSuggestion <- withUserAndCurrentVenue workerUser venue.id do
                    withCurrentControllerContext do
                        fetchTimesheetSuggestionForRosterSlot autumnSlot.id
                            >>= maybe (expectationFailure "Expected autumn suggestion" >> error "unreachable") pure
                springSuggestion <- withUserAndCurrentVenue workerUser venue.id do
                    withCurrentControllerContext do
                        fetchTimesheetSuggestionForRosterSlot springSlot.id
                            >>= maybe (expectationFailure "Expected spring suggestion" >> error "unreachable") pure

                authoritativeElapsedSeconds autumnSuggestion.suggestionBoundaries `shouldBe` 480 * 60
                authoritativeBreakElapsedSeconds autumnSuggestion.suggestionBoundaries `shouldBe` 30 * 60
                fmap (.localTimeOfDay) (authoritativeBreakStartLocalTime autumnSuggestion.suggestionBoundaries)
                    `shouldBe` Just (TimeOfDay 2 30 0)
                authoritativeBreakStartOccurrence autumnSuggestion.suggestionBoundaries `shouldBe` Just SecondOccurrence
                authoritativeElapsedSeconds springSuggestion.suggestionBoundaries `shouldBe` 360 * 60
                authoritativeBreakStartLocalTime springSuggestion.suggestionBoundaries `shouldBe` Nothing

        it "keeps a Sunday after-midnight roster suggestion in its source Operational week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Operational Week Venue"
                workerUser <- createUserRecord "timesheet-operational-week-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Monday" "Suggestion"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Early"
                rosterWeek <- createRosterWeekRecord venue 64 True
                rosterDay <- createRosterDayRecord rosterWeek 6
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                        |> setTestRosterSlotBoundaries (fromGregorian 2026 4 6) (TimeOfDay 2 0 0) (TimeOfDay 4 0 0)
                    )
                let surfaceParams =
                        [ ("anchorDate", "2026-03-30"), ("rosterCalendarRevision", "1")
                        ]

                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 64))) surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.operationalDate `shouldBe` rosterDay.operationalDate
                entry.operationalDate `shouldBe` fromGregorian 2026 4 5
                testStartTime entry `shouldBe` TimeOfDay 2 0 0
                testEndTime entry `shouldBe` TimeOfDay 4 0 0

        it "scopes suggestion visibility and creation to the viewer's timesheet authority" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Authority Venue"
                manager <- createUserRecord "timesheet-suggestion-authority-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-suggestion-authority-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-suggestion-authority-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerAUser Worker
                _ <- createVenueMembershipRecord venue workerBUser Worker
                workerA <- createStaffRecord venue (Just workerAUser) "Alice" "Authority"
                workerB <- createStaffRecord venue (Just workerBUser) "Bob" "Boundary"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel workerA
                _ <- makeStaffTimesheetProducing payLevel workerB
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                slotA <- createRosterSlotRecord rosterDay slotName (Just workerA) 0
                slotB <- createRosterSlotRecord rosterDay slotName (Just workerB) 1
                slotA <- updateRecord
                    ( slotA
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )
                slotB <- updateRecord
                    ( slotB
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 10 0 0) (TimeOfDay 18 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                workerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                workerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                deniedResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                deniedResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1"), ("staffFilterId", idToParam workerA.id)]
                managerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                managerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                -- URL filters limit presentation, not the manager's venue-wide
                -- Timesheets authority over an otherwise eligible source.
                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                createdResponse `responseStatusShouldBe` status302
                createdEntry <- query @TimesheetEntry |> fetchOne
                createdEntry.staffId `shouldBe` unpackId workerB.id

        it "rejects materialization when the roster source changes after projection" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Stale Venue" Nothing "timesheet-suggestion-stale-worker@example.com" "Stella" "Stale"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) 480
                    }

                materializationResult <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    withCurrentControllerContext do
                        suggestion <- fetchTimesheetSuggestionForRosterSlot scenario.scenarioRosterSlot.id >>= maybe (expectationFailure "Expected initial suggestion" >> error "unreachable") pure
                        _ <- updateRecord (scenario.scenarioRosterSlot |> setTestEndTime (Just (TimeOfDay 18 0 0)) |> setTestDurationMinutes (Just 540))
                        let entry = newTimesheetEntryFromSuggestion (unpackId scenario.scenarioVenue.id) suggestion
                        let scope = TimesheetWeekScopeValue (unpackId scenario.scenarioVenue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
                        materializeTimesheetSuggestionMutation scope suggestion entry

                materializationResult `shouldBe` Right Nothing
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "returns typed locked-calendar failures for both suggestion paths without materialization or publication" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Locked Suggestion Calendar" (Just "locked-suggestion-manager@example.com") "locked-suggestion-calendar@example.com" "Calendar" "Suggestion"
                    , suggestionActor = SuggestionManager
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) 480
                    }
                eventCount <- query @LiveInvalidationEvent |> fetchCount
                withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    withCurrentControllerContext do
                        suggestion <- fetchTimesheetSuggestionForRosterSlot scenario.scenarioRosterSlot.id >>= maybe (expectationFailure "Expected suggestion" >> error "unreachable") pure
                        let entry = newTimesheetEntryFromSuggestion (unpackId scenario.scenarioVenue.id) suggestion
                        let scope = TimesheetWeekScopeValue (unpackId scenario.scenarioVenue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 0
                        materializeTimesheetSuggestionMutation scope suggestion entry `shouldReturn` Left TimesheetCalendarChanged
                        materializeAndApproveTimesheetSuggestionMutation scope suggestion entry `shouldReturn` Left TimesheetCalendarChanged
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 0)
                query @LiveInvalidationEvent |> fetchCount >>= (`shouldBe` eventCount)

        it "materializes a suggestion idempotently under concurrent submissions" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Concurrent Venue" Nothing "timesheet-suggestion-concurrent-worker@example.com" "Connie" "Concurrent"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) 480
                    }

                results <- runConcurrentActionsImmediately 8 do
                    withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                        callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)
                activeEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#sourceRosterSlotId, Just (unpackId scenario.scenarioRosterSlot.id))
                        |> filterWhere (#deletedAt, Nothing)
                        |> fetch
                length activeEntries `shouldBe` 1

        it "lets staff edit rostered values before creating the linked snapshot" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Edit Venue" Nothing "timesheet-suggestion-edit-worker@example.com" "Edie" "Editor"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) 480
                    }

                formResponse <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldContain` "This form starts from the current roster shift"
                formResponse `responseBodyShouldNotContain` "<span class=\"badge text-bg-info\">Rostered</span>"
                formResponse `responseBodyShouldContain` "name=\"staffId\""
                formResponse `responseBodyShouldNotContain` "<select name=\"staffId\""
                formResponse `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                formResponse `responseBodyShouldContain` "name=\"endTime\" value=\"17:00\""

                createResponse <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam scenario.scenarioWorker.id)
                        , ("shiftTypeId", idToParam scenario.scenarioShiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "10:00")
                        , ("endTime", "16:00")
                        , ("hadBreak", "false")
                        ]

                createResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                testStartTime entry `shouldBe` TimeOfDay 10 0 0
                testEndTime entry `shouldBe` TimeOfDay 16 0 0
                testHadBreak entry `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId scenario.scenarioRosterSlot.id)

        it "keeps an ad-hoc entry separate without showing an origin warning" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Ad Hoc Warning Venue"
                workerUser <- createUserRecord "timesheet-ad-hoc-warning-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Ada" "AdHoc"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                _ <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "This creates a separate timesheet entry"
                response `responseBodyShouldNotContain` "The rostered suggestion will remain"
                response `responseBodyShouldContain` cs (pathTo CreateTimesheetEntryAction)
                response `responseBodyShouldNotContain` cs (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
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
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                refreshedResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

        it "restores a suggestion after its linked entry is soft-deleted and preserves both snapshots" $ withContext do
            withCleanDb do
                scenario <- createSuggestionScenario SuggestionScenarioPlan
                    { suggestionIdentity = SuggestionIdentity "Timesheet Suggestion Restore Venue" Nothing "timesheet-suggestion-restore-worker@example.com" "Rory" "Restore"
                    , suggestionActor = SuggestionWorker
                    , suggestionEligibility = EnsureTimesheetProducing
                    , suggestionApprovalFacts = NoSuggestionApproval
                    , suggestionRosterFacts = SuggestionRosterFacts "Day" "Early" 0 1 (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) 480
                    }
                oldEntry <-
                    newRecord @TimesheetEntry
                        |> set #venueId (unpackId scenario.scenarioVenue.id)
                        |> set #staffId (unpackId scenario.scenarioWorker.id)
                        |> set #shiftTypeId (unpackId scenario.scenarioShiftType.id)
                        |> set #operationalDate (fromGregorian 2025 1 7)
                        |> setTestWorkedOn (fromGregorian 2025 1 7)
                        |> setTestStartTime (TimeOfDay 9 0 0)
                        |> setTestEndTime (TimeOfDay 17 0 0)
                        |> set #sourceRosterSlotId (Just (unpackId scenario.scenarioRosterSlot.id))
                        |> createRecord
                now <- getCurrentTime
                _ <- updateRecord
                    ( oldEntry
                        |> set #deletedAt (Just now)
                        |> set #deletedByUserId (Just (unpackId scenario.scenarioWorkerUser.id))
                        |> set #deleteReason (Just "test_deleted")
                    )

                suggestionResponse <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow scenario.scenarioRosterSlot.id <> "\"")

                createResponse <- withUserAndCurrentVenue scenario.scenarioActor scenario.scenarioVenue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = scenario.scenarioRosterSlot.id }
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                createResponse `responseStatusShouldBe` status302
                linkedEntries :: [TimesheetEntry] <-
                    query @TimesheetEntry
                        |> filterWhere (#sourceRosterSlotId, Just (unpackId scenario.scenarioRosterSlot.id))
                        |> orderByAsc #createdAt
                        |> fetch
                length linkedEntries `shouldBe` 2
                length (filter (isNothing . (.deletedAt)) linkedEntries) `shouldBe` 1

        it "lets only managers reassign roster-derived staff without changing date or source" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Immutable Venue"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- updateRecord (venueConfig |> set #staffTimesheetEditWindowDays 10000)
                manager <- createUserRecord "timesheet-suggestion-immutable-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosteredUser <- createUserRecord "timesheet-suggestion-immutable-rostered@example.com" "staff" True
                otherUser <- createUserRecord "timesheet-suggestion-immutable-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue rosteredUser Worker
                _ <- createVenueMembershipRecord venue otherUser Worker
                rosteredStaff <- createStaffRecord venue (Just rosteredUser) "Robin" "Rostered"
                otherStaff <- createStaffRecord venue (Just otherUser) "Sam" "Separate"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (rosteredStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                _ <- updateRecord (otherStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just rosteredStaff) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                creationResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                creationResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 1)
                entry <- query @TimesheetEntry |> fetchOne

                workerEditResponse <- withUserAndCurrentVenue rosteredUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams EditTimesheetEntryAction { timesheetEntryId = entry.id }
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                workerEditResponse `responseStatusShouldBe` status200
                workerEditResponse `responseBodyShouldContain` "<input type=\"hidden\" name=\"staffId\""
                workerEditResponse `responseBodyShouldNotContain` "<select name=\"staffId\""

                deniedWorkerUpdate <- withUserAndCurrentVenue rosteredUser venue.id do
                    callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam otherStaff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "09:00")
                        , ("endTime", "17:00")
                        ]
                deniedWorkerUpdate `responseStatusShouldBe` status403

                editResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams EditTimesheetEntryAction { timesheetEntryId = entry.id }
                            [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]
                editResponse `responseStatusShouldBe` status200
                editResponse `responseBodyShouldNotContain` "<strong>Roster-derived entry.</strong>"
                editResponse `responseBodyShouldNotContain` "This entry is a snapshot of a roster shift."
                editResponse `responseBodyShouldNotContain` "<span class=\"badge text-bg-info\">Rostered</span>"
                editResponse `responseBodyShouldContain` "<select name=\"staffId\""
                editResponse `responseBodyShouldContain` "Sam Separate"
                editResponse `responseBodyShouldContain` "<input type=\"hidden\" name=\"workedOn\""
                editResponse `responseBodyShouldNotContain` "<input type=\"date\" name=\"workedOn\""

                updateResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam otherStaff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-07")
                        , ("startTime", "10:00")
                        , ("endTime", "16:00")
                        ]
                updateResponse `responseStatusShouldBe` status302

                reassigned <- fetch entry.id
                reassigned.staffId `shouldBe` unpackId otherStaff.id
                testWorkedOn reassigned `shouldBe` fromGregorian 2025 1 7
                reassigned.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)
                testStartTime reassigned `shouldBe` TimeOfDay 10 0 0
                testEndTime reassigned `shouldBe` TimeOfDay 16 0 0

                deniedDateUpdate <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam otherStaff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-08")
                        , ("startTime", "10:00")
                        , ("endTime", "16:00")
                        ]
                deniedDateUpdate `responseStatusShouldBe` status403

                provenanceRetained <- fetch entry.id
                provenanceRetained.staffId `shouldBe` unpackId otherStaff.id
                testWorkedOn provenanceRetained `shouldBe` fromGregorian 2025 1 7
                provenanceRetained.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

        it "shows approved entries to staff with a disabled approved button" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Approved Staff Venue"
                manager <- createUserRecord "timesheet-approved-marker-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-approved-marker-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Ava" "Approved"
                _ <- createApprovedTimesheetEntryRecord venue worker manager (fromGregorian 2025 1 7)

                _ <- newRecord @UserPreference
                    |> set #userId (unpackId workerUser.id)
                    |> set #hideApproved False
                    |> createRecord
                response <- withUserAndCurrentVenue workerUser venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { anchorDate = tshow (testAnchorForOffset 0), operationalDate = tshow (addDays (toInteger 1 ) (testAnchorForOffset 0)) }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Ava Approved"
                response `responseBodyShouldContain` "data-timesheet-entry-approved=\"true\""
                response `responseBodyShouldContain` ">Approved</button>"
                response `responseBodyShouldContain` "disabled"
                response `responseBodyShouldNotContain` "UnapproveTimesheetEntry"

        it "omits the retired all-staff transport and toggle for workers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Worker Filter Venue"
                workerUser <- createUserRecord "timesheet-filter-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                _ <- createStaffRecord venue (Just workerUser) "Willa" "Worker"

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hide approved"
                response `responseBodyShouldContain` "Show suggestions"
                response `responseBodyShouldContain` "timesheet-side-panel"
                response `responseBodyShouldContain` "<h2 class=\"h5\">Settings</h2>"
                response `responseBodyShouldNotContain` "id=\"timesheet-staff-tab\""
                response `responseBodyShouldNotContain` "timesheet-staff-panel-entry"
                response `responseBodyShouldNotContain` ">Show all staff</span>"

        it "defaults managers to all authorized staff with all display categories visible" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Filter Venue"
                manager <- createUserRecord "timesheet-filter-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-filter-worker-a@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerAUser Worker
                managerStaff <- createStaffRecord venue (Just manager) "Mia" "Manager"
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Hours"
                _ <- createApprovedTimesheetEntryRecord venue managerStaff manager (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hide approved"
                response `responseBodyShouldNotContain` "Show all staff"
                response `responseBodyShouldContain` "btn btn-outline-success app-toggle-button"
                response `responseBodyShouldContain` "data-bepis-toggle-transport=\"toggle-transport:timesheet-hide-approved-toggle\""
                response `responseBodyShouldContain` "data-bepis-toggle-config=\""
                response `responseBodyShouldContain` "aria-pressed=\"false\""
                response `responseBodyShouldContain` "timesheet-entry-staff-name\">Ava Hours"
                response `responseBodyShouldContain` "timesheet-entry-card\" data-timesheet-entry-approved=\"true\""

        it "renders complete manager side-panel counts independently of filters and display preferences" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Side Panel Venue"
                manager <- createUserRecord "timesheet-side-panel-manager@example.com" "staff" True
                workerAUser <- createUserRecord "timesheet-side-panel-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-side-panel-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerAUser Worker
                _ <- createVenueMembershipRecord venue workerBUser Worker
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Counted"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Unfiltered"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel workerA
                _ <- makeStaffTimesheetProducing payLevel workerB
                _ <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createApprovedTimesheetEntryRecord venue workerA manager (fromGregorian 2025 1 8)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1"), ("staffFilterId", idToParam workerA.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "timesheet-side-panel"
                response `responseBodyShouldContain` "timesheet-week-header app-side-panel-header"
                response `responseBodyShouldContain` "timesheet-staff-panel-entry"
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-side-panel-root=\"true\""
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-side-panel-toggle=\"true\""
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-side-panel-tab=\"staff\""
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-staff-panel-sort-root=\"true\""
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-staff-highlight-source=\"staff:"
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-staff-highlight-member=\"staff:"
                response `responseBodyShouldContain` "data-bepis-timesheets-timesheet-staff-highlight-pin=\"staff:"
                response `responseBodyShouldContain` "Ava Counted"
                response `responseBodyShouldContain` "Bea Unfiltered"
                response `responseBodyShouldContain` "timesheet-staff-count-total\">2</span>"
                response `responseBodyShouldContain` "timesheet-staff-count-approved\">(1)</span>"
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                response `responseBodyShouldContain` cs (pathTo (EditStaffAction workerA.id))
                response `responseBodyShouldNotContain` "timesheet-entry-staff-name\">Bea Unfiltered"

        it "renders FrontendSurface refresh urls with only current staff filter state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Live Filter Url Venue"
                manager <- createUserRecord "timesheet-live-filter-url-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Lina" "Filtered"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffFilterId", idToParam staff.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldNotContain` "data-live-update-url="
                response `responseBodyShouldContain` cs ("staffFilterId=" <> tshow staff.id)

        it "filters manager timesheet views to a selected staff member" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Staff Filter Venue"
                manager <- createUserRecord "timesheet-staff-filter-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                workerAUser <- createUserRecord "timesheet-staff-filter-a@example.com" "staff" True
                workerBUser <- createUserRecord "timesheet-staff-filter-b@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerAUser Worker
                _ <- createVenueMembershipRecord venue workerBUser Worker
                workerA <- createStaffRecord venue (Just workerAUser) "Ava" "Filter"
                workerB <- createStaffRecord venue (Just workerBUser) "Bea" "Filter"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (workerA |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                _ <- updateRecord (workerB |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                entryA <- createTimesheetEntryRecord venue workerA (fromGregorian 2025 1 7)
                _ <- createTimesheetEntryRecord venue workerB (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 0)))
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        , ("staffFilterId", idToParam workerA.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"staffFilterId\""
                response `responseBodyShouldContain` "timesheet-entry-staff-name\">Ava Filter"
                response `responseBodyShouldNotContain` "timesheet-entry-staff-name\">Bea Filter"
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWindow?anchorDate="
                response `responseBodyShouldContain` cs ("&amp;staffFilterId=" <> tshow workerA.id <> "\"")
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWindow?anchorDate=2024-12-30&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWindow?anchorDate=2025-01-13&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` "timesheet-entry-card-link"
                response `responseBodyShouldContain` cs (pathTo (EditTimesheetEntryAction entryA.id))

        it "renders a shape bar for valid after-midnight timesheet entries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet After Midnight Venue"
                manager <- createUserRecord "timesheet-after-midnight-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Mia" "Manager"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 20)
                _ <-
                    entry
                        |> setTestStartTime (TimeOfDay 0 15 0)
                        |> setTestEndTime (TimeOfDay 4 0 0)
                        |> setTestHadBreak False
                        |> setTestBreakStartTime Nothing
                        |> setTestBreakEndTime Nothing
                        |> setTestBreakMinutes 0
                        |> updateRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowTimesheetWindowAction (tshow (testAnchorForOffset 2)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "12:15"
                response `responseBodyShouldContain` "4:00 AM"
                response `responseBodyShouldContain` "timesheet-shape-bar"
                response `responseBodyShouldContain` "timesheet-shape-segment-shift"

        it "renders Timesheets Settings forms against the canonical week path" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Settings Venue"
                manager <- createUserRecord "timesheet-settings-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWindowAction (tshow (testAnchorForOffset 2)))
                        [ ("anchorDate", "2025-01-20"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-toolbar=\"timesheets\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"quick\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"navigation\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"settings\""
                response `responseBodyShouldContain` "btn btn-outline-secondary app-week-nav-button"
                response `responseBodyShouldContain` "href=\"/Timesheets\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWindow?anchorDate=2025-01-13\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWindow?anchorDate=2025-01-27\""
                response `responseBodyShouldContain` "action=\"/ShowTimesheetWindow\""
                response `responseBodyShouldContain` "hx-get=\"/ShowTimesheetWindow\""
                response `responseBodyShouldContain` "name=\"anchorDate\" value=\"2025-01-20\""
                response `responseBodyShouldNotContain` "<form method=\"get\" action=\"/ShowTimesheetWindow?anchorDate="
                response `responseBodyShouldNotContain` "action=\"/ShowTimesheetWindow\" hx-get=\"/ShowTimesheetWindow?anchorDate="

        it "keeps comment-only edits from resetting approved timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Comments Venue"
                manager <- createUserRecord "timesheet-comments-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-comments-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                staff <- createStaffRecord venue (Just workerUser) "Cora" "Comment"
                today <- utctDay <$> getCurrentTime
                entry <- createApprovedTimesheetEntryRecord venue staff manager today

                workerResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("anchorDate", cs (tshow today))
                        , ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
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
                staffCommentedEntry.activePayCalculationId `shouldBe` entry.activePayCalculationId
                staffCommentedEntry.staffPayVersionId `shouldBe` entry.staffPayVersionId
                staffCommentedEntry.shiftTypePayVersionId `shouldBe` entry.shiftTypePayVersionId
                staffCommentedEntry.approvedAt `shouldBe` entry.approvedAt
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
                        [ ("anchorDate", cs (tshow today))
                        , ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
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
                _ <- createVenueMembershipRecord venue manager Manager
                approvedUser <- createUserRecord "timesheet-approved-worker@example.com" "staff" True
                pendingUser <- createUserRecord "timesheet-pending-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue approvedUser Worker
                _ <- createVenueMembershipRecord venue pendingUser Worker
                approvedStaff <- createStaffRecord venue (Just approvedUser) "Ada" "Approved"
                pendingStaff <- createStaffRecord venue (Just pendingUser) "Pia" "Pending"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (pendingStaff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                _ <- createApprovedTimesheetEntryRecord venue approvedStaff manager (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryAction
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            , ("staffId", idToParam pendingStaff.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2025-01-07")
                            , ("startTime", "10:15")
                            , ("endTime", "14:15")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2025-01-07\""
                response `responseBodyShouldContain` "Timesheet entry created"
                let hiddenCreateTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"operationalDate\":\"2025-01-07\"")
                hiddenCreateTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2025-01-07")

        it "keeps HTMX mutation refreshes on the explicit window" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                user <- createUserRecord "timesheet-htmx-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Tess" "Create"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "timesheet-create-client")
                        ] do
                            callActionWithParams CreateTimesheetEntryAction
                                [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                                , ("staffId", idToParam staff.id)
                                , ("shiftTypeId", idToParam shiftType.id)
                                , ("workedOn", "2025-01-07")
                                , ("startTime", "09:15")
                                , ("endTime", "17:15")
                                ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2025-01-07\""
                response `responseBodyShouldContain` "Timesheet entry created"
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let createTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                createTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"operationalDate\":\"2025-01-07\"")
                createTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2025-01-07")

                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                versionAfter `shouldBe` versionBefore

        it "editing a timesheet date refreshes both old and new day sections" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-date-move-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Tia" "Move"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders
                        [ ("HX-Request", "true")
                        , ("X-Live-Update-Client-Id", "timesheet-date-move-client")
                        ] do
                            callActionWithParams (UpdateTimesheetEntryAction entry.id)
                                [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                                , ("staffId", idToParam staff.id)
                                , ("shiftTypeId", idToParam shiftType.id)
                                , ("workedOn", "2025-01-08")
                                , ("startTime", "09:15")
                                , ("endTime", "17:15")
                                ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2025-01-07\""
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2025-01-08\""
                response `responseBodyShouldContain` "Timesheet entry updated"
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let moveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"operationalDate\":\"2025-01-07\"")
                moveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"operationalDate\":\"2025-01-08\"")
                moveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2025-01-07")
                moveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2025-01-08")

                updatedEntry <- fetch entry.id
                testWorkedOn updatedEntry `shouldBe` fromGregorian 2025 1 8
                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                versionAfter `shouldBe` versionBefore

        it "manager review actions bump the timesheet week scope version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-live-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                importedPayItem <- createImportedXeroPayItemRecord venue manager "Live approval" "live-approval" 30
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "timesheet-approve-client")] do
                        callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-2025-01-07\""
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let approveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"operationalDate\":\"2025-01-07\"")
                approveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-2025-01-07")
                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1)
                versionAfter `shouldBe` versionBefore

        it "writes an audit event when approving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                importedPayItem <- createImportedXeroPayItemRecord venue manager "Timesheet approval" "timesheet-approval" 30
                staff <- createStaffRecord venue Nothing "Tia" "Shift"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` True
                updatedEntry.approvedByUserId `shouldBe` Just (unpackId manager.id)
                updatedEntry.staffPayVersionId `shouldSatisfy` isJust
                updatedEntry.activePayCalculationId `shouldSatisfy` isJust
                calculation <- query @TimesheetPayCalculation |> fetchOne
                calculation.timesheetEntryId `shouldBe` unpackId entry.id
                calculation.calculationSource `shouldBe` "external_imported_pay_item"
                components <- query @TimesheetPayEarningsComponent |> fetch
                components `shouldSatisfy` (not . null)

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approved"
                version.timesheetEntryId `shouldBe` unpackId entry.id
                version.actorUserId `shouldBe` unpackId manager.id

                snapshot <- query @StaffPayVersion |> fetchOne
                updatedEntry.staffPayVersionId `shouldBe` Just (unpackId snapshot.id)
                snapshot.staffId `shouldBe` updatedEntry.staffId
                snapshot.payAssignmentMode `shouldBe` XeroRate
                shiftSnapshot <- query @ShiftTypePayVersion |> fetchOne
                shiftSnapshot.payAssignmentMode `shouldBe` AwardRate

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId manager.id
                auditEvent.eventType `shouldBe` "timesheet_approved"
                auditEvent.targetTable `shouldBe` "timesheet_entries"
                auditEvent.targetId `shouldBe` unpackId entry.id
                auditEvent.sourceChannel `shouldBe` "web"

                unapproveResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UnapproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]
                unapproveResponse `responseStatusShouldBe` status302
                unapprovedEntry <- fetch entry.id
                unapprovedEntry.activePayCalculationId `shouldBe` Nothing
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 1

                reapproveResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]
                reapproveResponse `responseStatusShouldBe` status302
                reapprovedEntry <- fetch entry.id
                reapprovedEntry.activePayCalculationId `shouldSatisfy` maybe False (/= calculation.id)
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 2

        it "uses effective manager authority with actual founder approval attribution" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Impersonated Manager Approval Venue"
                founder <- createUserRecordWithPlatformRole "timesheet-approval-founder@example.com" "staff" (Just SuperAdmin) True
                manager <- createUserRecord "timesheet-approval-effective-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Effective" "Manager"
                importedPayItem <- createImportedXeroPayItemRecord venue founder "Impersonated approval" "impersonated-approval" 30
                staff <- createStaffRecord venue Nothing "Approval" "Target"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    _ <- callActionWithParams
                        StartSupportImpersonationAction
                        [("userId", cs (inputValue manager.id))]
                    callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                response `responseStatusShouldBe` status302
                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` True
                updatedEntry.approvedByUserId `shouldBe` Just (unpackId founder.id)
                version <- query @TimesheetEntryVersion |> filterWhere (#versionAction, EntryVersionActionEnumApproved) |> fetchOne
                version.actorUserId `shouldBe` unpackId founder.id
                version.payload `shouldSatisfy` \case
                    Aeson.Object payload -> case AesonKeyMap.lookup "requestContext" payload of
                        Just (Aeson.Object requestContext) ->
                            AesonKeyMap.lookup "accessMode" requestContext == Just (Aeson.String "impersonation")
                                && AesonKeyMap.lookup "effectiveUserId" requestContext == Just (Aeson.toJSON manager.id)
                        _ -> False
                    _ -> False

        it "approves once under concurrent submissions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent approval venue"
                manager <- createUserRecord "concurrent-approval@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                importedPayItem <- createImportedXeroPayItemRecord venue manager "Concurrent approval" "concurrent-approval" 30
                staff <- createStaffRecord venue Nothing "Connie" "Approval"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                results <- runConcurrentActionsImmediately 8 do
                    withUserAndCurrentVenue manager venue.id do
                        callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                            [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                            ]

                lefts results `shouldSatisfy` null
                mapM_ (`responseStatusShouldBe` status302) (rights results)
                approvedEntry <- fetch entry.id
                approvedEntry.isApproved `shouldBe` True
                approvedEntry.activePayCalculationId `shouldSatisfy` isJust
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 1
                approvedVersions <- query @TimesheetEntryVersion
                    |> filterWhere (#versionAction, EntryVersionActionEnumApproved)
                    |> fetchCount
                approvedVersions `shouldBe` 1

        it "rolls back approval when required pay facts are missing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Missing pay facts venue"
                manager <- createUserRecord "missing-pay-facts@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Missing" "Facts"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

                response `responseStatusShouldBe` status302
                unchangedEntry <- fetch entry.id
                unchangedEntry.isApproved `shouldBe` False
                unchangedEntry.staffPayVersionId `shouldBe` Nothing
                unchangedEntry.activePayCalculationId `shouldBe` Nothing
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 0
                query @TimesheetEntryVersion |> fetchCount `shouldReturn` 0

        it "writes an audit event when unapproving a timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-unapprove@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Una" "Shift"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 8)
                recordPayrollAuditProvenance venue manager entry

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UnapproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")
                        ]

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
                assertPayrollAuditProvenanceRetained entry

        it "writes an audit event when editing resets a prior approval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-reset@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Ria" "Shift"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 9)
                recordPayrollAuditProvenance venue manager entry

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (UpdateTimesheetEntryAction entry.id)
                        [ ("anchorDate", "2025-01-06")
                        , ("rosterCalendarRevision", "1")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2025-01-09")
                        , ("startTime", "09:15")
                        , ("endTime", "17:15")
                        ]

                response `responseStatusShouldBe` status302

                updatedEntry <- fetch entry.id
                updatedEntry.isApproved `shouldBe` False
                parseTimeParam "09:15" `shouldBe` Just (testStartTime updatedEntry)
                parseTimeParam "17:15" `shouldBe` Just (testEndTime updatedEntry)

                version <- query @TimesheetEntryVersion |> fetchOne
                inputValue version.versionAction `shouldBe` "approval_reset"
                version.timesheetEntryId `shouldBe` unpackId entry.id

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "timesheet_approval_reset"
                auditEvent.targetId `shouldBe` unpackId entry.id
                assertPayrollAuditProvenanceRetained entry

        it "records a version row before deleting an unapproved timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Del" "Shift"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

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
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue Nothing "Ada" "Shift"
                entry <- createApprovedTimesheetEntryRecord venue staff manager (fromGregorian 2025 1 11)
                recordPayrollAuditProvenance venue manager entry

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (DeleteTimesheetEntryAction entry.id)
                        [("anchorDate", "2025-01-06"), ("rosterCalendarRevision", "1")]

                response `responseStatusShouldBe` status302

                retainedEntry <- fetch entry.id
                retainedEntry.deletedAt `shouldSatisfy` isJust
                retainedEntry.deletedByUserId `shouldBe` Just (unpackId manager.id)

                versionCount <- query @TimesheetEntryVersion |> fetchCount
                versionCount `shouldBe` 1
                assertPayrollAuditProvenanceRetained entry

recordPayrollAuditProvenance ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    TimesheetEntry ->
    IO ()
recordPayrollAuditProvenance venue actor entry = do
    now <- getCurrentTime
    let staffPayVersionId = fromMaybe (error "approved fixture missing staff pay version") entry.staffPayVersionId
        shiftTypePayVersionId = fromMaybe (error "approved fixture missing shift type pay version") entry.shiftTypePayVersionId
        approvedAt = fromMaybe (error "approved fixture missing approval timestamp") entry.approvedAt
        operationalDate = timesheetEntryOperationalDate entry
    exportJob <-
        newRecord @ExportJob
            |> set #venueId (unpackId venue.id)
            |> set #requestedByUserId (unpackId actor.id)
            |> set #exportType ("approved_timesheets_csv" :: Text)
            |> set #status ("ready" :: Text)
            |> set #expiresAt (addUTCTime 3600 now)
            |> createRecord
    _ <-
        newRecord @ExportJobEntry
            |> set #exportJobId (unpackId exportJob.id)
            |> set #timesheetEntryId (unpackId entry.id)
            |> set #staffPayVersionId staffPayVersionId
            |> set #shiftTypePayVersionId shiftTypePayVersionId
            |> set #entryUpdatedAtAtExport entry.updatedAt
            |> set #entryApprovedAtAtExport approvedAt
            |> createRecord
    connection <- createXeroConnectionRecord venue actor "timesheet-audit-provenance"
    submissionRun <-
        newRecord @XeroSubmissionRun
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #submittedByUserId (unpackId actor.id)
            |> set #payPeriodStart operationalDate
            |> set #payPeriodEnd operationalDate
            |> set #status XeroSubmissionRunStatusEnumSubmitted
            |> createRecord
    submission <-
        newRecord @XeroTimesheetSubmission
            |> set #xeroSubmissionRunId (unpackId submissionRun.id)
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #staffId entry.staffId
            |> set #xeroEmployeeId ("audit-employee" :: Text)
            |> set #payPeriodStart operationalDate
            |> set #payPeriodEnd operationalDate
            |> set #status XeroTimesheetSubmissionStatusEnumSubmitted
            |> set #idempotencyKey ("audit-provenance" :: Text)
            |> createRecord
    _ <-
        newRecord @XeroTimesheetSubmissionEntry
            |> set #xeroTimesheetSubmissionId (unpackId submission.id)
            |> set #timesheetEntryId (unpackId entry.id)
            |> set #staffPayVersionId staffPayVersionId
            |> set #shiftTypePayVersionId shiftTypePayVersionId
            |> set #entryUpdatedAtAtPreview entry.updatedAt
            |> set #entryApprovedAtAtPreview approvedAt
            |> createRecord
    pure ()

assertPayrollAuditProvenanceRetained :: (?modelContext :: ModelContext) => TimesheetEntry -> IO ()
assertPayrollAuditProvenanceRetained entry = do
    query @ExportJobEntry
        |> filterWhere (#timesheetEntryId, unpackId entry.id)
        |> fetchCount
        >>= (`shouldBe` 1)
    query @XeroTimesheetSubmissionEntry
        |> filterWhere (#timesheetEntryId, unpackId entry.id)
        |> fetchCount
        >>= (`shouldBe` 1)

data SuggestionActor = SuggestionWorker | SuggestionManager

data SuggestionEligibility
    = EnsureTimesheetProducing
    | PreserveStaffPayDefaults

data SuggestionApprovalFacts
    = NoSuggestionApproval
    | XeroSuggestionApproval Text Text Scientific
    | AwardSuggestionApprovalWithoutSealedFacts

data SuggestionIdentity = SuggestionIdentity
    { suggestionVenueName       :: Text
    , suggestionManagerEmail    :: Maybe Text
    , suggestionWorkerEmail     :: Text
    , suggestionWorkerFirstName :: Text
    , suggestionWorkerLastName  :: Text
    }

data SuggestionRosterFacts = SuggestionRosterFacts
    { suggestionShiftName       :: Text
    , suggestionSlotName        :: Text
    , suggestionWeekOffset      :: Int
    , suggestionDayOffset       :: Int
    , suggestionOperationalDate :: Day
    , suggestionStartTime       :: TimeOfDay
    , suggestionEndTime         :: TimeOfDay
    , suggestionDurationMinutes :: Int
    }

data SuggestionScenarioPlan = SuggestionScenarioPlan
    { suggestionIdentity      :: SuggestionIdentity
    , suggestionActor         :: SuggestionActor
    , suggestionEligibility   :: SuggestionEligibility
    , suggestionApprovalFacts :: SuggestionApprovalFacts
    , suggestionRosterFacts   :: SuggestionRosterFacts
    }

data SuggestionScenario = SuggestionScenario
    { scenarioVenue      :: Venue
    , scenarioActor      :: User
    , scenarioWorkerUser :: User
    , scenarioWorker     :: Staff
    , scenarioShiftType  :: ShiftType
    , scenarioRosterSlot :: RosterSlot
    }

createSuggestionScenario :: (?modelContext :: ModelContext) => SuggestionScenarioPlan -> IO SuggestionScenario
createSuggestionScenario plan = do
    let identity = plan.suggestionIdentity
    let rosterFacts = plan.suggestionRosterFacts
    venue <- createVenueWithConfig identity.suggestionVenueName
    manager <- forM identity.suggestionManagerEmail \email -> do
        user <- createUserRecord email "staff" True
        _ <- createVenueMembershipRecord venue user Manager
        pure user
    workerUser <- createUserRecord identity.suggestionWorkerEmail "staff" True
    _ <- createVenueMembershipRecord venue workerUser Worker
    worker <- createStaffRecord venue (Just workerUser) identity.suggestionWorkerFirstName identity.suggestionWorkerLastName
    payLevel <- createPayLevelRecord venue "Level 1"
    worker <- case plan.suggestionEligibility of
        EnsureTimesheetProducing -> makeStaffTimesheetProducing payLevel worker
        PreserveStaffPayDefaults -> pure worker
    shiftType <- createShiftTypeRecord venue payLevel rosterFacts.suggestionShiftName
    (worker, shiftType) <- case plan.suggestionApprovalFacts of
        XeroSuggestionApproval itemName itemCode itemOrder -> do
            approvalActor <- maybe (error "Xero suggestion approval requires a manager") pure manager
            importedPayItem <- createImportedXeroPayItemRecord venue approvalActor itemName itemCode itemOrder
            approvedWorker <- updateRecord (worker |> set #payAssignmentMode XeroRate |> set #importedXeroPayItemId (Just importedPayItem.id))
            approvedShiftType <- updateRecord (shiftType |> set #payAssignmentMode XeroRate |> set #overrideAwardLevelId Nothing |> set #importedXeroPayItemId (Just importedPayItem.id))
            pure (approvedWorker, approvedShiftType)
        NoSuggestionApproval -> pure (worker, shiftType)
        AwardSuggestionApprovalWithoutSealedFacts -> pure (worker, shiftType)
    rosterWeek <- createRosterWeekRecord venue rosterFacts.suggestionWeekOffset True
    rosterDay <- createRosterDayRecord rosterWeek rosterFacts.suggestionDayOffset
    slotName <- fetchSlotNameRecord venue rosterFacts.suggestionSlotName
    rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
        >>= updateRecord
            . set #shiftTypeId (Just (unpackId shiftType.id))
            . setTestDurationMinutes (Just rosterFacts.suggestionDurationMinutes)
            . setTestRosterSlotBoundaries rosterFacts.suggestionOperationalDate rosterFacts.suggestionStartTime rosterFacts.suggestionEndTime
    actor <- case plan.suggestionActor of
        SuggestionWorker -> pure workerUser
        SuggestionManager -> maybe (error "manager suggestion actor requires a manager") pure manager
    pure SuggestionScenario
        { scenarioVenue = venue
        , scenarioActor = actor
        , scenarioWorkerUser = workerUser
        , scenarioWorker = worker
        , scenarioShiftType = shiftType
        , scenarioRosterSlot = rosterSlot
        }

makeStaffTimesheetProducing :: (?modelContext :: ModelContext) => AwardLevel -> Staff -> IO Staff
makeStaffTimesheetProducing payLevel staff =
    staff
        |> set #payAssignmentMode AwardRate
        |> set #defaultAwardLevelId (Just payLevel.id)
        |> updateRecord
