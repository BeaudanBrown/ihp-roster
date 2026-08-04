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
import Application.Helper.WeekBoundaries (venueWeekOffsetForDay)
import Application.VenueTime (RepeatedTimeOccurrence (..))
import Application.VenueTime.Model (ShiftBoundaryInput (..),
                                    applyRosterSlotBoundaries,
                                    authoritativeBreakElapsedSeconds,
                                    authoritativeBreakStartLocalTime,
                                    authoritativeBreakStartOccurrence,
                                    authoritativeElapsedSeconds,
                                    resolveShiftBoundaries,
                                    storedInstantOccurrence,
                                    timesheetEntryElapsedSeconds)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as AesonKeyMap
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
import Web.Timesheets.Suggestion (TimesheetSuggestion (..),
                                  newTimesheetEntryFromSuggestion)
import Web.Types
import qualified Web.View.Timesheets.Index as TimesheetsView

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "TimesheetsController" do
        it "redirects unauthenticated users through shared controller middleware" $ withContext do
            let entryId = Id "00000000-0000-0000-0000-000000000000"
            actionResponsesShouldHaveStatus status302
                [ ("index", callAction TimesheetsAction)
                , ("week", callAction ShowTimesheetWeekAction { weekOffset = 0 })
                , ("day fragment", callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 })
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
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWeekWeekOffset = 0 }
                        let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing }
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
                response `responseBodyShouldContain` "data-bepis-surface-action=\"navigate-timesheet-week\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-timesheet-hide-approved\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-timesheet-show-suggestions\""
                response `responseBodyShouldNotContain` "timesheet-week-shell-sync-custom-htmx"
                response `responseBodyShouldNotContain` "Pay preview"
                response `responseBodyShouldNotContain` "timesheet-wage-preview"

        it "resets This week navigation canonically and ignores retired display params" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Current Week Venue"
                user <- createUserRecord "timesheet-current-week@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Current" "Week"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                today <- utctDay <$> getCurrentTime
                let expectedOffset = venueWeekOffsetForDay venueConfig today

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams TimesheetsAction
                        [ ("weekOffset", "0")
                        , ("showApproved", "true")
                        , ("showAllStaff", "false")
                        , ("showTimesheetSuggestions", "false")
                        ]

                response `responseStatusShouldBe` status302
                let location = cs <$> lookup "Location" (responseHeaders response)
                location `shouldSatisfy` maybe False (Text.isInfixOf ("weekOffset=" <> tshow expectedOffset))
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showApproved")
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showAllStaff")
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showSuggestions")

                legacyWeekResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 4 }
                        [ ("showApproved", "true")
                        , ("showAllStaff", "false")
                        , ("showSuggestions", "false")
                        , ("hideApproved", "false")
                        , ("showTimesheetSuggestions", "false")
                        ]
                legacyWeekResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders legacyWeekResponse)
                    `shouldBe` Just "http://localhost/ShowTimesheetWeek?weekOffset=4"

        it "ignores retired direct-route display params" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Partial Route Venue"
                user <- createUserRecord "timesheet-partial-route@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Partial" "Route"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams TimesheetsAction [("showApproved", "true")]

                response `responseStatusShouldBe` status302
                let location = cs <$> lookup "Location" (responseHeaders response)
                location `shouldSatisfy` maybe False (Text.isInfixOf "weekOffset=")
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showApproved")
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showAllStaff")
                location `shouldSatisfy` maybe False (not . Text.isInfixOf "showSuggestions")

        it "persists display preferences globally and returns authoritative clean-url fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Preference Venue"
                user <- createUserRecord "timesheet-preferences@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Perry" "Preferences"

                hideResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams ToggleTimesheetHideApprovedAction
                        [("weekOffset", "2"), ("hideApproved", "false")]

                hideResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders hideResponse)
                    `shouldBe` Just "http://localhost/ShowTimesheetWeek?weekOffset=2"

                suggestionResponse <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ToggleTimesheetShowSuggestionsAction
                            [("weekOffset", "2"), ("showTimesheetSuggestions", "false")]

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
                    callAction ShowTimesheetWeekAction { weekOffset = 2 }
                reloaded `responseStatusShouldBe` status200
                reloaded `responseBodyShouldContain` "name=\"hideApproved\" value=\"false\""
                reloaded `responseBodyShouldContain` "name=\"showTimesheetSuggestions\" value=\"false\""
                reloaded `responseBodyShouldNotContain` "showApproved="
                reloaded `responseBodyShouldNotContain` "showAllStaff="

        it "builds typed FrontendSurface mount metadata for the current timesheet query state" $ withContext do
            withCurrentControllerContext do
                let venueId = fromMaybe (error "invalid test UUID") (UUID.fromString "00000000-0000-0000-0000-000000000123")
                let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = venueId, timesheetWeekWeekOffset = 2 }
                let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing }
                let impl = timesheetsSurfaceImpl scope mountState
                let mountConfig = impl.surfaceImplMountConfig
                let fragmentKeys = map (.mountedFragmentKey) mountConfig.mountFragments
                let fragmentTargets = map (.mountedFragmentTargetId) mountConfig.mountFragments
                let fragmentUrls = map (.mountedFragmentUrl) mountConfig.mountFragments

                impl.surfaceImplName `shouldBe` "timesheets"
                mountConfig.mountSurfaceName `shouldBe` "timesheets"
                mountConfig.mountScopeKey `shouldBe` "timesheets:00000000-0000-0000-0000-000000000123:2"
                mountConfig.mountState `shouldBe` Aeson.object
                    ["staffFilterId" Aeson..= (Nothing :: Maybe Text)]
                fragmentKeys
                    `shouldBe` [TimesheetsLive.timesheetToolbarLiveFragment, TimesheetsLive.timesheetDayColumnsLiveFragment]
                        <> map TimesheetsLive.timesheetDaySectionLiveFragment [0 .. 6]
                fragmentTargets `shouldBe` ["timesheet-week-toolbar", "timesheet-day-columns"] <> map (\dayOffset -> "timesheet-day-section-" <> tshow dayOffset) [0 .. 6]
                fragmentUrls `shouldSatisfy` all (Text.isInfixOf "weekOffset=2")
                fragmentUrls `shouldSatisfy` all (not . Text.isInfixOf "showApproved")
                fragmentUrls `shouldSatisfy` all (not . Text.isInfixOf "showAllStaff")
                fragmentUrls `shouldSatisfy` all (not . Text.isInfixOf "showSuggestions")

        it "records touched resources for timesheet entry mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Touched Timesheet Venue"
                staff <- createStaffRecord venue Nothing "Tim" "Touched"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let weekOffset = venueWeekOffsetForDay venueConfig (testWorkedOn entry)

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
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createStaffRecord venue (Just user) "Tara" "Target"

                (response, fragmentRef) <- withUserAndCurrentVenue user venue.id do
                    withCurrentControllerContext do
                        let scope = TimesheetWeekScopeValue { timesheetWeekVenueId = unpackId venue.id, timesheetWeekWeekOffset = 0 }
                        let mountState = TimesheetsMountStateValue { timesheetsMountStaffFilterId = Nothing }
                        let daySectionRef =
                                timesheetsCandidateMountedFragments scope mountState
                                    |> find (\fragment -> fragment.mountedFragmentKey == TimesheetsLive.timesheetDaySectionLiveFragment 0)
                                    |> fromMaybe (error "Expected day section fragment ref")
                        callAction ShowTimesheetWeekAction { weekOffset = 0 }
                        response <- callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 0 }
                        pure (response, daySectionRef)

                liveFragmentResponseShouldRenderTarget response fragmentRef

        it "renders unified toolbar and day-columns fragments for HTMX week navigation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet HTMX Fragment Venue"
                manager <- createUserRecord "timesheet-htmx-fragment-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams ShowTimesheetWeekAction { weekOffset = 1 }
                            [ ("weekOffset", "1")
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
                _ <- createVenueMembershipRecord venue manager Manager
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
                superAdmin <- createUserRecordWithPlatformRole "timesheet-super-admin@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "timesheet-super-admin-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                staff <- createStaffRecord venue (Just worker) "Tess" "Worker"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel staff
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
                entry <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> fetchOne
                testHadBreak entry `shouldBe` False

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
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-05")
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
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Just SecondOccurrence
                timesheetEntryElapsedSeconds entry `shouldBe` 90 * 60

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
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-05")
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
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Just FirstOccurrence
                storedInstantOccurrence entry.timezone entry.endsAt `shouldBe` Just SecondOccurrence
                timesheetEntryElapsedSeconds entry `shouldBe` 60 * 60

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
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam staff.id)
                        , ("shiftTypeId", idToParam shiftType.id)
                        , ("workedOn", "2026-04-05")
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
                storedInstantOccurrence entry.timezone breakStart `shouldBe` Just FirstOccurrence
                storedInstantOccurrence entry.timezone breakEnd `shouldBe` Just SecondOccurrence
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
                            [ ("weekOffset", "0")
                            , ("staffId", idToParam staff.id)
                            , ("shiftTypeId", idToParam shiftType.id)
                            , ("workedOn", "2026-10-04")
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
                            [ ("weekOffset", "0")
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
                            [ ("weekOffset", "0")
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
                            [ ("weekOffset", "0")
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
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                response `responseBodyShouldContain` "name=\"endTime\" value=\"13:00\""
                response `responseBodyShouldContain` "data-bepis-time-picker-config="
                response `responseBodyShouldContain` "&quot;rangeStart&quot;:&quot;09:00&quot;"
                response `responseBodyShouldContain` "&quot;rangeEnd&quot;:&quot;13:00&quot;"

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
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]
                weekResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (ShowTimesheetWeekAction 0) []

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

                formResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryAction
                            [("weekOffset", "0"), ("workedOn", "2025-01-07")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldNotContain` "Rory RosterOnly"
                formResponse `responseBodyShouldNotContain` "Roster-only shift"
                formResponse `responseBodyShouldContain` "Timesheet shift"

                let createParams staffId shiftTypeId =
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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
                        materializeTimesheetSuggestionMutation 0 eligibleSuggestion tamperedEntry
                lockedRevalidation `shouldBe` Nothing
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
                _ <- createVenueMembershipRecord venue user Manager
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
                _ <- createVenueMembershipRecord venue user Manager
                staff <- createStaffRecord venue Nothing "Tess" "Delete"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 7)

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (EditTimesheetEntryAction entry.id)
                            [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }
                workerResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }

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
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }
                workerResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

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

        it "shows future live-roster suggestions immediately" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Future Suggestion Venue"
                workerUser <- createUserRecord "timesheet-future-suggestion-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Faye" "Future"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 3 True
                rosterDay <- createRosterDayRecord rosterWeek 4
                slotName <- fetchSlotNameRecord venue "Late"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 31) (TimeOfDay 12 0 0) (TimeOfDay 20 0 0)
                        |> setTestDurationMinutes (Just 480)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 3 }
                        [("weekOffset", "3")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "hides suggestions from the persisted user preference with clean week navigation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Filter Venue"
                manager <- createUserRecord "timesheet-suggestion-filter-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-filter-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Fiona" "Filtered"
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Lunch"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                _ <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 10 0 0) (TimeOfDay 16 0 0)
                        |> setTestDurationMinutes (Just 360)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                _ <- newRecord @UserPreference
                    |> set #userId (unpackId manager.id)
                    |> set #showTimesheetSuggestions False
                    |> createRecord
                response <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowTimesheetWeekAction { weekOffset = 0 }

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Show suggestions"
                response `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")
                response `responseBodyShouldContain` "name=\"showTimesheetSuggestions\" value=\"false\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=1\""
                response `responseBodyShouldNotContain` "showApproved="
                response `responseBodyShouldNotContain` "showAllStaff="

        it "quick-creates one unapproved snapshot from an authorized roster suggestion" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Create Venue"
                workerUser <- createUserRecord "timesheet-suggestion-create-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Quinn" "QuickCreate"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0)
                        |> setTestDurationMinutes (Just 375)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                malformedResponse <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                            [ ("weekOffset", "0")
                            , ("hadBreak", "not-a-boolean")
                            ]

                malformedResponse `responseStatusShouldBe` status200
                malformedResponse `responseBodyShouldContain` "Had break must be true or false"
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                response <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.venueId `shouldBe` unpackId venue.id
                entry.staffId `shouldBe` unpackId worker.id
                entry.shiftTypeId `shouldBe` unpackId shiftType.id
                testWorkedOn entry `shouldBe` fromGregorian 2025 1 7
                testStartTime entry `shouldBe` TimeOfDay 9 0 0
                testEndTime entry `shouldBe` TimeOfDay 15 15 0
                testHadBreak entry `shouldBe` True
                testBreakStartTime entry `shouldBe` Just (TimeOfDay 14 30 0)
                testBreakEndTime entry `shouldBe` Just (TimeOfDay 15 0 0)
                testBreakMinutes entry `shouldBe` 30
                entry.isApproved `shouldBe` False
                entry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)
                version <- query @TimesheetEntryVersion |> fetchOne
                version.payload `shouldBe` Aeson.object
                    [ "source" Aeson..= ("roster_suggestion" :: Text)
                    , "rosterSlotId" Aeson..= tshow rosterSlot.id
                    ]

        it "quick-approves a manager's roster suggestion atomically" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Quick Approve Venue"
                manager <- createUserRecord "timesheet-suggestion-quick-approve-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-quick-approve-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                importedPayItem <- createImportedXeroPayItemRecord venue manager "Suggestion approval" "suggestion-approval" 31
                worker <- createStaffRecord venue (Just workerUser) "Quinn" "Approve"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                payLevel <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #overrideAwardLevelId Nothing . set #importedXeroPayItemId (Just importedPayItem.id)
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0)
                        |> setTestDurationMinutes (Just 375)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
                        , ("approveSuggestion", "true")
                        ]

                response `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                entry.isApproved `shouldBe` True
                entry.approvedByUserId `shouldBe` Just (unpackId manager.id)
                entry.activePayCalculationId `shouldSatisfy` isJust
                query @TimesheetEntryVersion |> fetchCount >>= (`shouldBe` 2)
                query @AuditEvent |> filterWhere (#eventType, auditEventTypeText TimesheetApprovedAudit) |> fetchCount >>= (`shouldBe` 1)

        it "rolls back quick suggestion creation when manager approval fails" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Approval Rollback Venue"
                manager <- createUserRecord "timesheet-suggestion-approval-rollback-manager@example.com" "staff" True
                workerUser <- createUserRecord "timesheet-suggestion-approval-rollback-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Rollback" "Approval"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
                rosterWeek <- createRosterWeekRecord venue 0 True
                rosterDay <- createRosterDayRecord rosterWeek 1
                slotName <- fetchSlotNameRecord venue "Early"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just worker) 0
                rosterSlot <- updateRecord
                    ( rosterSlot
                        |> setTestRosterSlotBoundaries (fromGregorian 2025 1 7) (TimeOfDay 9 0 0) (TimeOfDay 15 15 0)
                        |> setTestDurationMinutes (Just 375)
                        |> set #shiftTypeId (Just (unpackId shiftType.id))
                    )

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "64")
                        ]
                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 64 } surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Just SecondOccurrence
                timesheetEntryElapsedSeconds entry `shouldBe` 90 * 60
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
                        [ ("weekOffset", "64")
                        ]

                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 64 } surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                storedInstantOccurrence entry.timezone entry.startsAt `shouldBe` Just FirstOccurrence
                storedInstantOccurrence entry.timezone entry.endsAt `shouldBe` Just SecondOccurrence
                timesheetEntryElapsedSeconds entry `shouldBe` 60 * 60
                let shapeSegments = TimesheetsView.timesheetShapeSegments TimesheetsView.defaultTimesheetTimelineScale entry
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

        it "projects a Sunday after-midnight roster shift into the following timesheet week" $ withContext do
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
                        |> setTestRosterSlotBoundaries (fromGregorian 2026 4 5) (TimeOfDay 2 0 0) (TimeOfDay 4 0 0)
                    )
                let surfaceParams =
                        [ ("weekOffset", "65")
                        ]

                suggestionResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 65 } surfaceParams

                suggestionResponse `responseStatusShouldBe` status200
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createdResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id } surfaceParams

                createdResponse `responseStatusShouldBe` status302
                entry <- query @TimesheetEntry |> fetchOne
                testWorkedOn entry `shouldBe` fromGregorian 2026 4 6
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
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("weekOffset", "0")]
                workerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                workerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                deniedResponse <- withUserAndCurrentVenue workerAUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("weekOffset", "0")]
                deniedResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [("weekOffset", "0"), ("staffFilterId", idToParam workerA.id)]
                managerResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotA.id <> "\"")
                managerResponse `responseBodyShouldNotContain` cs ("data-timesheet-suggestion-id=\"" <> tshow slotB.id <> "\"")

                -- URL filters limit presentation, not the manager's venue-wide
                -- Timesheets authority over an otherwise eligible source.
                createdResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = slotB.id }
                        [("weekOffset", "0")]
                createdResponse `responseStatusShouldBe` status302
                createdEntry <- query @TimesheetEntry |> fetchOne
                createdEntry.staffId `shouldBe` unpackId workerB.id

        it "rejects materialization when the roster source changes after projection" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Stale Venue"
                workerUser <- createUserRecord "timesheet-suggestion-stale-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Stella" "Stale"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
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

                materializationResult <- withUserAndCurrentVenue workerUser venue.id do
                    withCurrentControllerContext do
                        suggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlot.id >>= maybe (expectationFailure "Expected initial suggestion" >> error "unreachable") pure
                        _ <- updateRecord (rosterSlot |> setTestEndTime (Just (TimeOfDay 18 0 0)) |> setTestDurationMinutes (Just 540))
                        let entry = newTimesheetEntryFromSuggestion (unpackId venue.id) suggestion
                        materializeTimesheetSuggestionMutation 0 suggestion entry

                materializationResult `shouldBe` Nothing
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "materializes a suggestion idempotently under concurrent submissions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Concurrent Venue"
                workerUser <- createUserRecord "timesheet-suggestion-concurrent-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Connie" "Concurrent"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
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

                results <- runConcurrentTimesheetActions 8 do
                    withUserAndCurrentVenue workerUser venue.id do
                        callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                            [("weekOffset", "0")]

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
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Edie" "Editor"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
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

                formResponse <- withUserAndCurrentVenue workerUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams NewTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                            [("weekOffset", "0")]

                formResponse `responseStatusShouldBe` status200
                formResponse `responseBodyShouldContain` "This form starts from the current roster shift"
                formResponse `responseBodyShouldNotContain` "<span class=\"badge text-bg-info\">Rostered</span>"
                formResponse `responseBodyShouldContain` "name=\"staffId\""
                formResponse `responseBodyShouldNotContain` "<select name=\"staffId\""
                formResponse `responseBodyShouldContain` "name=\"startTime\" value=\"09:00\""
                formResponse `responseBodyShouldContain` "name=\"endTime\" value=\"17:00\""

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [ ("weekOffset", "0")
                        , ("staffId", idToParam worker.id)
                        , ("shiftTypeId", idToParam shiftType.id)
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
                entry.sourceRosterSlotId `shouldBe` Just (unpackId rosterSlot.id)

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
                            [ ("weekOffset", "0")
                            , ("workedOn", "2025-01-07")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "This creates a separate timesheet entry"
                response `responseBodyShouldNotContain` "The rostered suggestion will remain"
                response `responseBodyShouldContain` cs (pathTo CreateTimesheetEntryAction)
                response `responseBodyShouldNotContain` cs (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id })

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryAction
                        [ ("weekOffset", "0")
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
                        [("weekOffset", "0")]
                refreshedResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

        it "restores a suggestion after its linked entry is soft-deleted and preserves both snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Suggestion Restore Venue"
                workerUser <- createUserRecord "timesheet-suggestion-restore-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue workerUser Worker
                worker <- createStaffRecord venue (Just workerUser) "Rory" "Restore"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- makeStaffTimesheetProducing payLevel worker
                shiftType <- createShiftTypeRecord venue payLevel "Day"
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
                oldEntry <-
                    newRecord @TimesheetEntry
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId worker.id)
                        |> set #shiftTypeId (unpackId shiftType.id)
                        |> setTestWorkedOn (fromGregorian 2025 1 7)
                        |> setTestStartTime (TimeOfDay 9 0 0)
                        |> setTestEndTime (TimeOfDay 17 0 0)
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
                        [("weekOffset", "0")]
                suggestionResponse `responseBodyShouldContain` cs ("data-timesheet-suggestion-id=\"" <> tshow rosterSlot.id <> "\"")

                createResponse <- withUserAndCurrentVenue workerUser venue.id do
                    callActionWithParams CreateTimesheetEntryFromSuggestionAction { rosterSlotId = rosterSlot.id }
                        [("weekOffset", "0")]

                createResponse `responseStatusShouldBe` status302
                linkedEntries :: [TimesheetEntry] <-
                    query @TimesheetEntry
                        |> filterWhere (#sourceRosterSlotId, Just (unpackId rosterSlot.id))
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
                        [("weekOffset", "0")]
                creationResponse `responseStatusShouldBe` status302
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 1)
                entry <- query @TimesheetEntry |> fetchOne

                workerEditResponse <- withUserAndCurrentVenue rosteredUser venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams EditTimesheetEntryAction { timesheetEntryId = entry.id }
                            [("weekOffset", "0")]
                workerEditResponse `responseStatusShouldBe` status200
                workerEditResponse `responseBodyShouldContain` "<input type=\"hidden\" name=\"staffId\""
                workerEditResponse `responseBodyShouldNotContain` "<select name=\"staffId\""

                deniedWorkerUpdate <- withUserAndCurrentVenue rosteredUser venue.id do
                    callActionWithParams UpdateTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("weekOffset", "0")
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
                            [("weekOffset", "0")]
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
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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
                    callAction ShowTimesheetDaySectionFragmentAction { weekOffset = 0, dayOffset = 1 }

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
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"showAllStaff\""
                response `responseBodyShouldContain` "Hide approved"
                response `responseBodyShouldContain` "Show suggestions"
                response `responseBodyShouldNotContain` ">Show all staff</span>"

        it "defaults managers to all authorized staff and applies persisted display preferences" $ withContext do
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
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Hide approved"
                response `responseBodyShouldNotContain` "Show all staff"
                response `responseBodyShouldContain` "btn btn-outline-success app-toggle-button"
                response `responseBodyShouldContain` "data-bepis-toggle-transport=\"toggle-transport:timesheet-hide-approved-toggle\""
                response `responseBodyShouldContain` "data-bepis-toggle-config=\""
                response `responseBodyShouldContain` "aria-pressed=\"true\""
                response `responseBodyShouldContain` "aria-pressed=\"true\""
                response `responseBodyShouldContain` "timesheet-entry-staff-name\">Ava Hours"
                response `responseBodyShouldNotContain` "timesheet-entry-card\" data-timesheet-entry-approved=\"true\""

        it "renders FrontendSurface refresh urls with only current staff filter state" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Live Filter Url Venue"
                manager <- createUserRecord "timesheet-live-filter-url-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                staff <- createStaffRecord venue (Just manager) "Lina" "Filtered"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("weekOffset", "0")
                        , ("staffFilterId", idToParam staff.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface-config=\""
                response `responseBodyShouldNotContain` "data-live-update-url="
                response `responseBodyShouldContain` cs ("staffFilterId=" <> tshow staff.id)
                response `responseBodyShouldNotContain` "showApproved="
                response `responseBodyShouldNotContain` "showAllStaff="
                response `responseBodyShouldNotContain` "showSuggestions="

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
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 0 }
                        [ ("weekOffset", "0")
                        , ("staffFilterId", idToParam workerA.id)
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "name=\"staffFilterId\""
                response `responseBodyShouldContain` "timesheet-entry-staff-name\">Ava Filter"
                response `responseBodyShouldNotContain` "timesheet-entry-staff-name\">Bea Filter"
                response `responseBodyShouldContain` cs ("href=\"/Timesheets?weekOffset=0&amp;staffFilterId=" <> tshow workerA.id <> "\"")
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=-1&amp;staffFilterId=" <> tshow workerA.id)
                response `responseBodyShouldContain` cs ("href=\"/ShowTimesheetWeek?weekOffset=1&amp;staffFilterId=" <> tshow workerA.id)
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
                _ <- createVenueMembershipRecord venue manager Manager
                _ <- createStaffRecord venue (Just manager) "Mia" "Manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowTimesheetWeekAction { weekOffset = 2 }
                        [ ("weekOffset", "2")
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-week-toolbar=\"timesheets\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"quick\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"navigation\""
                response `responseBodyShouldContain` "data-week-toolbar-section=\"settings\""
                response `responseBodyShouldContain` "btn btn-outline-secondary app-week-nav-button"
                response `responseBodyShouldContain` "href=\"/Timesheets?weekOffset=0\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=1\""
                response `responseBodyShouldContain` "href=\"/ShowTimesheetWeek?weekOffset=3\""
                response `responseBodyShouldContain` "action=\"/ShowTimesheetWeek\""
                response `responseBodyShouldContain` "hx-get=\"/ShowTimesheetWeek\""
                response `responseBodyShouldContain` "name=\"weekOffset\" value=\"2\""
                response `responseBodyShouldNotContain` "<form method=\"get\" action=\"/ShowTimesheetWeek?weekOffset="
                response `responseBodyShouldNotContain` "action=\"/ShowTimesheetWeek\" hx-get=\"/ShowTimesheetWeek?weekOffset="

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
                            [ ("weekOffset", "0")
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
                _ <- createVenueMembershipRecord venue user Worker
                staff <- createStaffRecord venue (Just user) "Tess" "Create"
                payLevel <- createPayLevelRecord venue "Level 1"
                _ <- updateRecord (staff |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just payLevel.id))
                shiftType <- createShiftTypeRecord venue payLevel "Ordinary"

                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)

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

                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)
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

                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)

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
                testWorkedOn updatedEntry `shouldBe` fromGregorian 2025 1 8
                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)
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

                versionBefore <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "timesheet-approve-client")] do
                        callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                            [ ("weekOffset", "0")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "id=\"timesheet-day-section-1\""
                response `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let approveTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"timesheet-day-section\"")
                approveTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"dayOffset\":1")
                approveTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "timesheet-day-section-1")
                versionAfter <- currentLiveUpdateVersion (TimesheetsLive.timesheetWeekLiveScope (unpackId venue.id) 0)
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
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
                        ]
                unapproveResponse `responseStatusShouldBe` status302
                unapprovedEntry <- fetch entry.id
                unapprovedEntry.activePayCalculationId `shouldBe` Nothing
                query @TimesheetPayCalculation |> fetchCount `shouldReturn` 1

                reapproveResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
                        , ("showApproved", "false")
                        , ("showAllStaff", "true")
                        , ("showSuggestions", "true")
                        ]

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

                results <- runConcurrentTimesheetActions 8 do
                    withUserAndCurrentVenue manager venue.id do
                        callActionWithParams ApproveTimesheetEntryAction { timesheetEntryId = entry.id }
                            [ ("weekOffset", "0")
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
                        [ ("weekOffset", "0")
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

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UnapproveTimesheetEntryAction { timesheetEntryId = entry.id }
                        [ ("weekOffset", "0")
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

        it "writes an audit event when editing resets a prior approval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Timesheet Venue"
                manager <- createUserRecord "timesheet-reset@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
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
                parseTimeParam "09:15" `shouldBe` Just (testStartTime updatedEntry)
                parseTimeParam "17:15" `shouldBe` Just (testEndTime updatedEntry)

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
                _ <- createVenueMembershipRecord venue manager Manager
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
                _ <- createVenueMembershipRecord venue manager Manager
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

makeStaffTimesheetProducing :: (?modelContext :: ModelContext) => AwardLevel -> Staff -> IO Staff
makeStaffTimesheetProducing payLevel staff =
    staff
        |> set #payAssignmentMode AwardRate
        |> set #defaultAwardLevelId (Just payLevel.id)
        |> updateRecord

runConcurrentTimesheetActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentTimesheetActions count action = do
    vars <- mapM (const newEmptyMVar) [1 .. count]
    _ <- mapM (\var -> forkIO (try action >>= putMVar var)) vars
    mapM takeMVar vars
