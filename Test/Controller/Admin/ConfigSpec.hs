module Test.Controller.Admin.ConfigSpec where

import Application.Helper.Export (ExportJobType (..), exportJobTypeToText)
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource,
                                                                   adminVenueSettingsResource,
                                                                   xeroConnectionResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekBoundaryConfigResource,
                                                                        timesheetWeekResource)
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.RosterOffsetCompatibility (defaultWeekOffsetEpochForStartDay)
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey)
import Application.Helper.SurfaceResource
import Application.Helper.Xero
import Config
import qualified Control.Concurrent.Async as Async
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteString.Lazy.Char8 as LByteString
import qualified Data.IORef as IORef
import qualified Data.List as List
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (NominalDiffTime, addUTCTime, diffUTCTime,
                        getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import qualified Test.XeroMock as XeroMock
import Web.Admin.Mutations (RosterWindowStartDayImpact (..),
                            adminVenueSettingsTouchedResources,
                            confirmRosterWindowStartDayMutation,
                            previewRosterWindowStartDayMutation,
                            rosterEndTimesTouchedResources,
                            rosterTimePickerWindowTouchedResources,
                            rosterWeekStartsOnTouchedResources,
                            shiftTypePayResources)
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidations)
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "AdminController" do
        it "allows venue owners to access admin config screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                owner <- createUserRecord "owner-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner VenueOwner

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster Groups"
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-page\""
                response `responseBodyShouldContain` "id=\"admin-page-content-fragment\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-invites\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-venue-config\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-shift-types\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-roster-groups\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-exports\""
                response `responseBodyShouldContain` ">Exports<"
                response `responseBodyShouldContain` "id=\"invites-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"venue-settings-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"exports-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"shift-types-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"roster-groups-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldNotContain` "accordion-collapse collapse show"
                response `responseBodyShouldContain` "href=\"/Xero\""
                response `responseBodyShouldNotContain` "Venue Config"

        it "records setting-specific touched resources for admin config mutations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Touched Venue"
                let venueId = unpackId venue.id

                Set.fromList (adminVenueSettingsTouchedResources venue.id)
                    `shouldBe` Set.fromList [adminVenueSettingsResource venueId]
                Set.fromList (rosterEndTimesTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [ adminVenueSettingsResource venueId
                        , rosterEndTimesConfigResource venueId
                        ]
                Set.fromList (rosterTimePickerWindowTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [ adminVenueSettingsResource venueId
                        , timePickerConfigResource venueId
                        ]
                Set.fromList (rosterWeekStartsOnTouchedResources venue.id)
                    `shouldBe` Set.fromList
                        [ adminVenueSettingsResource venueId
                        , adminExportsResource venueId
                        , rosterWeekBoundaryConfigResource venueId
                        , timesheetWeekBoundaryConfigResource venueId
                        , xeroConnectionResource venueId
                        ]

        it "touches active roster and Timesheet views after shift-type pay changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Shift Type Pay Resource Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                otherVenue <- createVenueWithConfig "Other Shift Type Resource Venue"
                otherGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId otherVenue.id) |> fetchOne
                let venueId = unpackId venue.id
                    resources = shiftTypePayResources venueId
                        [ (venueId, unpackId rosterGroup.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        , (unpackId otherVenue.id, unpackId otherGroup.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        ]
                        [ (venueId, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        , (unpackId otherVenue.id, testAnchorForOffset 0, addDays 7 (testAnchorForOffset 0), 1)
                        ]

                Set.fromList resources `shouldBe` Set.fromList
                    [ rosterWeekResource (unpackId rosterGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                    , rosterSlotsContentResource (unpackId rosterGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                    , timesheetWeekResource venueId (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))
                    ]

        it "plans non-overlapping roster refreshes for roster-affecting venue config resources" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Roster Config Planning Venue"
                admin <- createUserRecord "admin-roster-config-planning@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let venueId = unpackId venue.id
                let scope = RosterLive.rosterWeekLiveScope venueId (unpackId rosterGroup.id) (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0)) 1
                let mountedFragments =
                        [ RosterLive.rosterContentLiveFragment
                        , RosterLive.rosterGridToolbarLiveFragment
                        , RosterLive.rosterGridFrameLiveFragment
                        , RosterLive.rosterDayColumnsLiveFragment
                        , RosterLive.rosterDayRailLiveFragment
                        , RosterLive.rosterWageRailLiveFragment
                        , RosterLive.rosterSlotsGridLiveFragment
                        ]
                let expectedFragments =
                        [ RosterLive.rosterGridToolbarLiveFragment
                        , RosterLive.rosterGridFrameLiveFragment
                        ]
                let subscription =
                        SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = mountedFragments
                            , subscriptionRenderedDependencyWatermark = 0
                            }
                let planFragments resource = withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withCurrentControllerContext do
                            pure
                                [ (target.targetScope, target.targetFragments)
                                | target <- planSurfaceInvalidations (Set.singleton resource) [subscription]
                                ]

                planFragments (rosterEndTimesConfigResource venueId)
                    `shouldReturn` [(scope, expectedFragments)]
                planFragments (rosterWeekBoundaryConfigResource venueId)
                    `shouldReturn` [(scope, expectedFragments)]
                let templateFragment = RosterLive.rosterTemplateLibraryLiveFragment (unpackId admin.id)
                let templateSubscription = subscription { subscriptionFragmentKeys = [templateFragment] }
                withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        pure
                            [ (target.targetScope, target.targetFragments)
                            | target <- planSurfaceInvalidations (Set.singleton (rosterWeekBoundaryConfigResource venueId)) [templateSubscription]
                            ]
                    `shouldReturn` [(scope, [templateFragment])]

        it "shows the Xero header button and page to super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Super Admin Venue"
                superAdmin <- createUserRecordWithPlatformRole "xero-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/Xero\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-xero-page\""
                response `responseBodyShouldContain` "id=\"admin-xero-page-content-fragment\""
                response `responseBodyShouldContain` "data-bepis-surface=\"admin-xero\""
                response `responseBodyShouldContain` "id=\"admin-xero-fragment\""
                response `responseBodyShouldContain` "Connect Xero"

        it "hides and blocks the Xero header button for venue admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Venue Admin Tab Venue"
                venueAdmin <- createUserRecord "xero-venue-admin-tab@example.com" "staff" True
                _ <- createVenueMembershipRecord venue venueAdmin VenueAdmin

                adminResponse <- withPasskeyVerifiedUserAndCurrentVenue venueAdmin venue.id do
                    callAction AdminAction
                xeroResponse <- withPasskeyVerifiedUserAndCurrentVenue venueAdmin venue.id do
                    callAction XeroAction

                adminResponse `responseStatusShouldBe` status200
                adminResponse `responseBodyShouldNotContain` "href=\"/Xero\""
                adminResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                xeroResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders xeroResponse) `shouldBe` Just "http://localhost/RosterWeeks"

        it "shows active imported Xero pay items in shift type dropdowns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Imported Pay Item Venue"
                admin <- createUserRecord "admin-imported-pay-items@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue level "Custom Rate Shift"
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Imported Bar Rate" "imported-bar-rate" 42.50

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowadminShiftTypesLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                response `responseBodyShouldContain` "Pay Rate"
                response `responseBodyShouldContain` (cs ("<option value=\"xero:" <> inputValue importedPayItem.id <> "\""))
                response `responseBodyShouldContain` "Xero imported rates"
                response `responseBodyShouldContain` "Imported Bar Rate"
                response `responseBodyShouldContain` "42.5/hr"
                responseBodyText <- responseBody response
                (cs responseBodyText :: String) `shouldContainInOrder` ["Award rates", "Level 1", "Xero imported rates", "Imported Bar Rate"]

                createResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Imported Pay Rate Shift")
                        , ("payRateSelection", cs ("xero:" <> tshow importedPayItem.id))
                        , ("colourKey", "no_colour")
                        , ("isActive", "true")
                        ]
                createResponse `responseStatusShouldBe` status302
                createdShiftType <- query @ShiftType
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#name, "Imported Pay Rate Shift" :: Text)
                    |> fetchOne
                createdShiftType.overrideAwardLevelId `shouldBe` Nothing
                createdShiftType.importedXeroPayItemId `shouldBe` Just importedPayItem.id
                createdShiftType.payAssignmentMode `shouldBe` XeroRate

        it "creates a roster-only shift type from the pay dropdown" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster Only Shift Type Venue"
                admin <- createUserRecord "roster-only-shift-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Roster only")
                        , ("payRateSelection", "roster-only")
                        , ("colourKey", "no_colour")
                        , ("isActive", "true")
                        ]
                response `responseStatusShouldBe` status302
                shiftType <- query @ShiftType |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#name, "Roster only" :: Text) |> fetchOne
                shiftType.payAssignmentMode `shouldBe` RosterOnly
                shiftType.overrideAwardLevelId `shouldBe` Nothing
                shiftType.importedXeroPayItemId `shouldBe` Nothing

        it "hides archived imported Xero pay items from shift type dropdowns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Archived Imported Pay Item Venue"
                admin <- createUserRecord "admin-archived-imported-pay-items@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue level "Custom Rate Shift"
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Archived Bar Rate" "archived-bar-rate" 42.50
                now <- getCurrentTime
                _ <- importedPayItem
                    |> set #archivedAt (Just now)
                    |> set #archivedByUserId (Just (unpackId admin.id))
                    |> set #archiveReason (Just ("Test archive" :: Text))
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowadminShiftTypesLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Pay Rate"
                response `responseBodyShouldNotContain` "Archived Bar Rate"

        it "serves inactive toggles through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Fragment Venue"
                admin <- createUserRecord "admin-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                _ <- createShiftTypeRecord venue level "Active Shift"
                inactiveShiftType <- createShiftTypeRecord venue level "Inactive Shift"
                _ <- inactiveShiftType
                    |> set #isActive False
                    |> updateRecord
                _ <- createVenueRosterGroupWithDefaults venue "Active Group" 10 True
                _ <- createVenueRosterGroupWithDefaults venue "Inactive Group" 20 False

                hiddenShiftTypesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowadminShiftTypesLiveFragmentAction
                        [("showInactiveShiftTypes", "false")]
                hiddenShiftTypesResponse `responseStatusShouldBe` status200
                hiddenShiftTypesResponse `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "data-bepis-surface=\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "admin-shift-types"
                hiddenShiftTypesResponse `responseBodyShouldContain` "&quot;fieldNameFallback&quot;:true"
                hiddenShiftTypesResponse `responseBodyShouldContain` "&quot;kind&quot;:&quot;focused-field&quot;"
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-get=\"/ShowadminShiftTypesLiveFragment?showInactiveShiftTypes=true\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "Active Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "btn btn-outline-secondary w-100"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "Inactive Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "id=\"app\""

                visibleShiftTypesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowadminShiftTypesLiveFragmentAction
                        [("showInactiveShiftTypes", "true")]
                visibleShiftTypesResponse `responseStatusShouldBe` status200
                visibleShiftTypesResponse `responseBodyShouldContain` "Inactive Shift"
                visibleShiftTypesBody <- responseBody visibleShiftTypesResponse
                (cs visibleShiftTypesBody :: String) `shouldContainInOrder` ["Active Shift", "Inactive Shift"]
                visibleShiftTypesResponse `responseBodyShouldContain` "checked=\"checked\""

                hiddenRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowadminRosterGroupsLiveFragmentAction
                        [("showInactiveRosterGroups", "false")]
                hiddenRosterGroupsResponse `responseStatusShouldBe` status200
                hiddenRosterGroupsResponse `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "data-bepis-surface=\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "admin-roster-groups"
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-get=\"/ShowadminRosterGroupsLiveFragment?showInactiveRosterGroups=true\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "Active Group"
                hiddenRosterGroupsResponse `responseBodyShouldNotContain` "Inactive Group"

                visibleRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowadminRosterGroupsLiveFragmentAction
                        [("showInactiveRosterGroups", "true")]
                visibleRosterGroupsResponse `responseStatusShouldBe` status200
                visibleRosterGroupsResponse `responseBodyShouldContain` "Inactive Group"
                visibleRosterGroupsBody <- responseBody visibleRosterGroupsResponse
                (cs visibleRosterGroupsBody :: String) `shouldContainInOrder` ["Active Group", "Inactive Group"]
                visibleRosterGroupsResponse `responseBodyShouldContain` "checked=\"checked\""

        it "serves venue settings and export admin fragments through typed surfaces" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Expansion Fragment Venue"
                admin <- createUserRecord "admin-expansion-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                venueSettingsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminVenueSettingsFragmentAction
                venueSettingsResponse `responseStatusShouldBe` status200
                venueSettingsResponse `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface=\""
                venueSettingsResponse `responseBodyShouldContain` "admin-venue-config"
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/UpdateRosterTimePickerWindow\""
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/UpdateMinutePrecisionShiftTimesEnabled\""
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/UpdateUnavailableStaffWarningThreshold\""
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/UpdateRosterEndTimesEnabled\""
                venueSettingsResponse `responseBodyShouldContain` "hx-target=\"#admin-venue-settings-fragment\""
                venueSettingsResponse `responseBodyShouldContain` "hx-swap=\"none\""
                venueSettingsResponse `responseBodyShouldContain` "hx-push-url=\"false\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-roster-time-picker-window\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-minute-precision-shift-times-enabled\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-unavailable-staff-warning-threshold\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-roster-end-times-enabled\""
                venueSettingsResponse `responseBodyShouldContain` "Roster window start day"
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/PreviewRosterWindowStartDay\""
                venueSettingsResponse `responseBodyShouldContain` "name=\"rosterWeekStartsOn\""
                venueSettingsResponse `responseBodyShouldContain` "Preview impact"
                venueSettingsResponse `responseBodyShouldNotContain` "hx-confirm="
                venueSettingsResponse `responseBodyShouldNotContain` "Automatically create pending timesheets"
                venueSettingsResponse `responseBodyShouldNotContain` "autoTimesheetCreationEnabled"
                venueSettingsResponse `responseBodyShouldNotContain` "name=\"configField\""
                venueSettingsResponse `responseBodyShouldNotContain` "update-venue-config"
                venueSettingsResponse `responseBodyShouldNotContain` "id=\"app\""

                exportsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowadminExportsLiveFragmentAction

                exportsResponse `responseStatusShouldBe` status200
                exportsResponse `responseBodyShouldContain` "id=\"admin-exports-fragment\""
                exportsResponse `responseBodyShouldContain` "data-bepis-surface=\""
                exportsResponse `responseBodyShouldContain` "admin-exports"
                exportsResponse `responseBodyShouldContain` "hx-post=\"/CreateExportJob\""
                exportsResponse `responseBodyShouldContain` "hx-target=\"#admin-exports-fragment\""
                exportsResponse `responseBodyShouldContain` "hx-swap=\"none\""
                exportsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"create-export-job\""
                exportsResponse `responseBodyShouldContain` "Staff Hours CSV"
                exportsResponse `responseBodyShouldContain` "Download CSV"
                exportsResponse `responseBodyShouldContain` "Export week navigation"
                exportsResponse `responseBodyShouldContain` "anchorDate="
                exportsResponse `responseBodyShouldNotContain` "weekOffset="
                exportsResponse `responseBodyShouldNotContain` "Recent Exports"
                exportsResponse `responseBodyShouldNotContain` "Approved Timesheets CSV"
                exportsResponse `responseBodyShouldContain` "Hourly Breakdown ZIP"
                exportsResponse `responseBodyShouldContain` "Download staff hours"
                exportsResponse `responseBodyShouldContain` "Download wage totals"
                exportsResponse `responseBodyShouldContain` "Payroll Earnings CSV"
                exportsResponse `responseBodyShouldNotContain` "admin-export-range-start"
                exportsResponse `responseBodyShouldNotContain` "admin-export-range-end"
                exportsResponse `responseBodyShouldNotContain` "id=\"app\""

        it "redirects targeted export generation to its immediate download" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Export Fragment Mutation Venue"
                admin <- createUserRecord "admin-export-fragment-mutation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                versionBefore <- currentLiveUpdateVersion (AdminLive.adminExportsLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateExportJobAction
                            [ ("exportType", cs (exportJobTypeToText ApprovedTimesheetsCsv))
                            , ("rangeStart", "2025-01-06")
                            , ("rangeEnd", "2025-01-12")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                lookup "HX-Redirect" (responseHeaders response) `shouldSatisfy` maybe False (Text.isInfixOf "/DownloadExportJob" . cs)
                response `responseBodyShouldNotContain` "id=\"admin-exports-fragment\""
                response `responseBodyShouldNotContain` "id=\"app\""
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminExportsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "serves shift type and roster group add/update through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Mutation Fragment Venue"
                admin <- createUserRecord "admin-mutation-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Starter Shift"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Starter Group" 10 True
                inactiveRosterGroup <- createVenueRosterGroupWithDefaults venue "Archived Group" 20 False

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams AdminAction [("showInactiveRosterGroups", "true"), ("showInactiveShiftTypes", "true")]
                pageResponse `responseBodyShouldContain` "hx-post=\"/CreateShiftType\""
                pageResponse `responseBodyShouldContain` "admin-shift-types"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveShiftTypes\" value=\"true\""
                pageResponse `responseBodyShouldContain` "id=\"new-shift-type-active\""
                pageResponse `responseBodyShouldContain` "name=\"isActive\" value=\"true\""
                pageResponse `responseBodyShouldContain` "type=\"hidden\" name=\"isActive\" value=\"false\""
                pageResponse `responseBodyShouldContain` ("id=\"shift-type-active-" <> tshow shiftType.id <> "\"")
                pageResponse `responseBodyShouldContain` "btn btn-outline-success app-toggle-button"
                pageResponse `responseBodyShouldContain` "data-bepis-toggle-transport=\""
                pageResponse `responseBodyShouldContain` "data-bepis-toggle-config=\""
                pageResponse `responseBodyShouldContain` "aria-pressed=\"true\""
                pageResponse `responseBodyShouldContain` "role=\"switch\" aria-checked=\"true\""
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateShiftType?shiftTypeId=" <> tshow shiftType.id <> "\"")
                pageResponse `responseBodyShouldContain` "hx-trigger=\"input changed delay:600ms, blur changed\""
                pageResponse `responseBodyShouldContain` "hx-trigger=\"change\""
                pageResponse `responseBodyShouldContain` "hx-include=\"closest form\""
                pageResponse `responseBodyShouldContain` "data-admin-shift-type-field-key=\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"create-shift-type\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-shift-type\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"autosave-shift-type-name\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"autosave-shift-type-selection\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-inactive-shift-types\""
                pageResponse `responseBodyShouldContain` "name=\"colourKey\""
                pageResponse `responseBodyShouldContain` "Optional Colour"
                pageBody <- responseBody pageResponse
                let newPayRateSelectTag = openingTagWithId "new-shift-type-pay-rate" pageBody
                let newColourSelectTag = openingTagWithId "new-shift-type-colour" pageBody
                newPayRateSelectTag `shouldNotContain` "hx-"
                newColourSelectTag `shouldNotContain` "hx-"
                pageResponse `responseBodyShouldContain` "hx-post=\"/CreateRosterGroup\""
                pageResponse `responseBodyShouldContain` "admin-roster-groups"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                pageResponse `responseBodyShouldContain` "hx-swap=\"none\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveRosterGroups\" value=\"true\""
                pageResponse `responseBodyShouldContain` "id=\"new-roster-group-active\""
                pageResponse `responseBodyShouldContain` ("id=\"roster-group-active-" <> tshow rosterGroup.id <> "\"")
                pageResponse `responseBodyShouldNotContain` "app-status-info\">Default</span>"
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateRosterGroup?rosterGroupId=" <> tshow rosterGroup.id)
                pageResponse `responseBodyShouldContain` "hx-push-url=\"false\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"create-roster-group\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-roster-group\""
                pageResponse `responseBodyShouldContain` "data-bepis-surface-action=\"toggle-inactive-roster-groups\""

                shiftTypesVersionBefore <- currentLiveUpdateVersion (AdminLive.adminShiftTypesLiveScope (unpackId venue.id))
                xeroVersionBefore <- currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                createShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateShiftTypeAction
                            [ ("showInactiveShiftTypes", "true")
                            , ("name", "Fragment Shift")
                            , ("payRateSelection", cs ("award:" <> tshow level.id))
                            , ("colourKey", "no_colour")
                            , ("isActive", "true")
                            ]
                createShiftResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders createShiftResponse) `shouldBe` Just "none"
                createShiftResponse `responseBodyShouldNotContain` "id=\"admin-shift-types-fragment\""
                createShiftResponse `responseBodyShouldNotContain` "Fragment Shift"
                createShiftResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                createShiftResponse `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                createShiftResponse `responseBodyShouldNotContain` "id=\"app\""
                let createShiftTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders createShiftResponse)
                createShiftTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                createShiftTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-shift-types\"")
                createShiftTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-shift-types-fragment")
                shiftTypesVersionAfter <- currentLiveUpdateVersion (AdminLive.adminShiftTypesLiveScope (unpackId venue.id))
                shiftTypesVersionAfter `shouldBe` shiftTypesVersionBefore
                xeroVersionAfterCreateShift <- currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                xeroVersionAfterCreateShift `shouldBe` xeroVersionBefore

                moveShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (MoveShiftTypeDownAction shiftType.id)
                            [("showInactiveShiftTypes", "true")]
                moveShiftResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders moveShiftResponse) `shouldBe` Just "none"
                moveShiftResponse `responseBodyShouldNotContain` "id=\"admin-shift-types-fragment\""
                moveShiftResponse `responseBodyShouldNotContain` "Fragment Shift"
                moveShiftResponse `responseBodyShouldNotContain` "id=\"app\""
                let moveShiftTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders moveShiftResponse)
                moveShiftTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-shift-types\"")
                moveShiftTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-shift-types-fragment")
                shiftTypesVersionAfterMove <- currentLiveUpdateVersion (AdminLive.adminShiftTypesLiveScope (unpackId venue.id))
                shiftTypesVersionAfterMove `shouldBe` shiftTypesVersionAfter

                updateShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateShiftTypeAction shiftType.id)
                            [ ("showInactiveShiftTypes", "true")
                            , ("name", "Updated Fragment Shift")
                            , ("payRateSelection", "")
                            , ("colourKey", "no_colour")
                            , ("isActive", "false")
                            ]
                updateShiftResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders updateShiftResponse) `shouldBe` Just "none"
                updateShiftResponse `responseBodyShouldNotContain` "Updated Fragment Shift"
                updateShiftResponse `responseBodyShouldNotContain` "inactive"
                updateShiftResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                updateShiftResponse `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                let updateShiftTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders updateShiftResponse)
                updateShiftTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-shift-types\"")
                updateShiftTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-shift-types-fragment")
                xeroVersionAfterUpdateShift <- currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                xeroVersionAfterUpdateShift `shouldBe` xeroVersionAfterCreateShift

                rosterGroupsVersionBefore <- currentLiveUpdateVersion (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                createRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterGroupAction
                            [ ("showInactiveRosterGroups", "true")
                            , ("name", "Fragment Group")
                            , ("isActive", "true")
                            ]
                createRosterGroupResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders createRosterGroupResponse) `shouldBe` Just "none"
                createRosterGroupResponse `responseBodyShouldNotContain` "id=\"admin-roster-groups-fragment\""
                createRosterGroupResponse `responseBodyShouldNotContain` "Fragment Group"
                createRosterGroupResponse `responseBodyShouldNotContain` "Archived Group"
                createRosterGroupResponse `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                createRosterGroupResponse `responseBodyShouldNotContain` "id=\"app\""
                let createRosterGroupTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders createRosterGroupResponse)
                createRosterGroupTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                createRosterGroupTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-roster-groups\"")
                createRosterGroupTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-roster-groups-fragment")
                rosterGroupsVersionAfter <- currentLiveUpdateVersion (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                rosterGroupsVersionAfter `shouldBe` rosterGroupsVersionBefore

                moveRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (MoveRosterGroupUpAction rosterGroup.id)
                            [("showInactiveRosterGroups", "true")]
                moveRosterGroupResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders moveRosterGroupResponse) `shouldBe` Just "none"
                moveRosterGroupResponse `responseBodyShouldNotContain` "id=\"admin-roster-groups-fragment\""
                moveRosterGroupResponse `responseBodyShouldNotContain` "Fragment Group"
                moveRosterGroupResponse `responseBodyShouldNotContain` "id=\"app\""
                let moveRosterGroupTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders moveRosterGroupResponse)
                moveRosterGroupTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-roster-groups\"")
                moveRosterGroupTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-roster-groups-fragment")
                rosterGroupsVersionAfterMove <- currentLiveUpdateVersion (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                rosterGroupsVersionAfterMove `shouldBe` rosterGroupsVersionAfter

                updateRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                            [ ("showInactiveRosterGroups", "true")
                            , ("name", "Updated Fragment Group")
                            , ("isActive", "true")
                            ]
                updateRosterGroupResponse `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders updateRosterGroupResponse) `shouldBe` Just "none"
                updateRosterGroupResponse `responseBodyShouldNotContain` "Updated Fragment Group"
                updateRosterGroupResponse `responseBodyShouldNotContain` tshow inactiveRosterGroup.id
                let updateRosterGroupTriggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders updateRosterGroupResponse)
                updateRosterGroupTriggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-roster-groups\"")
                updateRosterGroupTriggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-roster-groups-fragment")

        it "creates venue-scoped non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                inviteNow <- getCurrentTime

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("showInactiveRosterGroups", "false")
                        , ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Supervisor")
                        , ("payRateSelection", "")
                        , ("colourKey", "no_colour")
                        , ("isActive", "true")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                inviteResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateVenueInvitationAction
                        [ ("email", "new-worker@example.com")
                        , ("rosterGroupId", idToParam createdRosterGroup.id)
                        ]
                inviteResponse `responseStatusShouldBe` status302

                createdShiftType <- query @ShiftType |> filterWhere (#name, "Supervisor") |> fetchOne
                createdInvitation <- query @VenueInvitation |> filterWhere (#email, "new-worker@example.com") |> fetchOne
                let inviteExpiryDeltaSeconds = diffUTCTime (fromMaybe inviteNow createdInvitation.expiresAt) inviteNow

                createdRosterGroup.venueId `shouldBe` unpackId venue.id
                createdRosterGroup.sortOrder `shouldBe` 1
                createdRosterGroup.isActive `shouldBe` True
                createdShiftType.name `shouldBe` "Supervisor"
                createdShiftType.overrideAwardLevelId `shouldBe` Nothing
                createdShiftType.isActive `shouldBe` True
                createdShiftType.colourKey `shouldBe` blankShiftTypeColourKey
                createdInvitation.venueId `shouldBe` unpackId venue.id
                createdInvitation.invitedByUserId `shouldBe` Just (unpackId admin.id)
                createdInvitation.acceptedAt `shouldBe` Nothing
                inputValue createdInvitation.inviteRole `shouldBe` "worker"
                inputValue createdInvitation.status `shouldBe` "pending"
                inputValue createdInvitation.deliveryStatus `shouldSatisfy` (`elem` ["queued", "sent", "failed"])
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 1209500 && seconds < 1210100)

        it "shows expired pending invitations and corrected-email renewal controls in Admin" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Expired Invite Lifecycle Venue"
                admin <- createUserRecord "admin-expired-invite-lifecycle@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                now <- getCurrentTime
                invitation <- createVenueInvitationRecord venue (Just admin) "expired-admin-lifecycle@example.com" Worker
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Expired"
                response `responseBodyShouldContain` cs (pathTo (RenewVenueInvitationAction invitation.id))
                response `responseBodyShouldContain` "name=\"email\""
                response `responseBodyShouldContain` "value=\"expired-admin-lifecycle@example.com\""

        it "renews an invitation from Admin with a corrected fresh link" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Renew Invite Venue"
                admin <- createUserRecord "admin-renew-invite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                now <- getCurrentTime
                original <- createVenueInvitationRecord venue (Just admin) "old-admin-invite@example.com" Worker
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isDefault, True)
                    |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (RenewVenueInvitationAction original.id)
                        [ ("email", "corrected-admin-invite@example.com")
                        , ("rosterGroupId", idToParam rosterGroup.id)
                        ]

                response `responseStatusShouldBe` status302
                revokedOriginal <- fetch original.id
                inputValue revokedOriginal.status `shouldBe` "revoked"
                replacement <- query @VenueInvitation
                    |> filterWhere (#email, "corrected-admin-invite@example.com")
                    |> fetchOne
                replacement.id `shouldNotBe` original.id
                replacement.staffId `shouldBe` Nothing
                inputValue replacement.status `shouldBe` "pending"
                inputValue replacement.deliveryStatus `shouldBe` "queued"
                query @AppJob
                    |> filterWhere (#relatedId, Just (unpackId replacement.id))
                    |> fetchCount
                    >>= (`shouldBe` 1)

        it "rejects invalid corrected Admin renewal emails without replacing or queueing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invalid Email Renew Venue"
                admin <- createUserRecord "admin-invalid-email-renew@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                original <- createVenueInvitationRecord venue (Just admin) "valid-admin-renewal@example.com" Worker
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isDefault, True)
                    |> fetchOne
                let invalidEmails =
                        [ "   "
                        , "not-an-email"
                        , Text.replicate 250 "a" <> "@example.com"
                        , "<script>alert(1)</script>@example.com"
                        ]

                forM_ invalidEmails \invalidEmail -> do
                    response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        callActionWithParams (RenewVenueInvitationAction original.id)
                            [ ("email", cs invalidEmail)
                            , ("rosterGroupId", idToParam rosterGroup.id)
                            ]
                    response `responseStatusShouldBe` status302
                    unchangedAfterSubmission <- fetch original.id
                    (inputValue unchangedAfterSubmission.status <> ":" <> invalidEmail)
                        `shouldBe` ("pending:" <> invalidEmail)

                unchanged <- fetch original.id
                inputValue unchanged.status `shouldBe` "pending"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> fetchCount >>= (`shouldBe` 0)

        it "renews from Admin with the original email when no correction is submitted" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Same Email Renew Venue"
                admin <- createUserRecord "admin-same-email-renew@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                original <- createVenueInvitationRecord venue (Just admin) "same-email-admin-invite@example.com" Worker
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isDefault, True)
                    |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (RenewVenueInvitationAction original.id)
                        [("rosterGroupId", idToParam rosterGroup.id)]

                response `responseStatusShouldBe` status302
                replacement <- query @VenueInvitation
                    |> filterWhere (#email, original.email)
                    |> filterWhere (#status, original.status)
                    |> fetchOne
                replacement.id `shouldNotBe` original.id

        it "rejects cross-venue Admin invitation renewal" $ withContext do
            withCleanDb do
                currentVenue <- createVenueWithConfig "Admin Renew Current Venue"
                foreignVenue <- createVenueWithConfig "Admin Renew Foreign Venue"
                admin <- createUserRecord "admin-cross-venue-renew@example.com" "staff" True
                _ <- createVenueMembershipRecord currentVenue admin VenueAdmin
                ensureTestUserHasPasskey admin
                foreignInvitation <- createVenueInvitationRecord foreignVenue Nothing "foreign-admin-renew@example.com" Worker

                response <- withPasskeyVerifiedUserAndCurrentVenue admin currentVenue.id do
                    callAction (RenewVenueInvitationAction foreignInvitation.id)

                response `responseStatusShouldBe` status403
                unchanged <- fetch foreignInvitation.id
                inputValue unchanged.status `shouldBe` "pending"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)

        it "hides accepted and expired venue invitations after one week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invite Retention Venue"
                admin <- createUserRecord "admin-invite-retention@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                now <- getCurrentTime
                let daysAgo days = addUTCTime (negate (days * 24 * 60 * 60)) now

                _ <- createVenueInvitationRecord venue (Just admin) "active-pending@example.com" Worker
                _ <- createVenueInvitationRecord venue (Just admin) "recent-expired@example.com" Worker
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-3600) now))
                _ <- createVenueInvitationRecord venue (Just admin) "old-expired@example.com" Worker
                    >>= updateRecord . set #expiresAt (Just (daysAgo 8))
                _ <- createVenueInvitationRecord venue (Just admin) "recent-accepted@example.com" Worker
                    >>= updateRecord
                        . set #status (Accepted)
                        . set #acceptedAt (Just (daysAgo 3))
                _ <- createVenueInvitationRecord venue (Just admin) "old-accepted@example.com" Worker
                    >>= updateRecord
                        . set #status (Accepted)
                        . set #acceptedAt (Just (daysAgo 8))

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "active-pending@example.com"
                pageResponse `responseBodyShouldContain` "recent-expired@example.com"
                pageResponse `responseBodyShouldContain` "recent-accepted@example.com"
                pageResponse `responseBodyShouldNotContain` "old-expired@example.com"
                pageResponse `responseBodyShouldNotContain` "old-accepted@example.com"

        it "defaults shift type colours to blank and renders a no-colour option" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Shift Colour Venue"
                admin <- createUserRecord "admin-shift-colours@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Unhighlighted Shift")
                        , ("payRateSelection", "")
                        , ("colourKey", "no_colour")
                        , ("isActive", "true")
                        ]
                response `responseStatusShouldBe` status302

                createdShiftType <- query @ShiftType |> filterWhere (#name, "Unhighlighted Shift") |> fetchOne
                createdShiftType.colourKey `shouldBe` blankShiftTypeColourKey

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction
                pageResponse `responseBodyShouldContain` "No colour"
                pageResponse `responseBodyShouldNotContain` "Default overflow"
                pageResponse `responseBodyShouldNotContain` "Default reusable"
                pageResponse `responseBodyShouldNotContain` "(in use)"

        it "keeps colours when reactivated shift types collide with active types" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Shift Reactivation Colour Venue"
                admin <- createUserRecord "admin-reactivate-shift-colours@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                activeShiftType <-
                    createShiftTypeRecord venue level "Active Shift"
                        >>= updateRecord . set #colourKey Palette1
                inactiveShiftType <-
                    createShiftTypeRecord venue level "Inactive Shift"
                        >>= updateRecord . set #isActive False . set #colourKey activeShiftType.colourKey

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction inactiveShiftType.id)
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Inactive Shift")
                        , ("payRateSelection", cs ("award:" <> tshow level.id))
                        , ("colourKey", cs (inputValue activeShiftType.colourKey))
                        , ("isActive", "true")
                        ]
                response `responseStatusShouldBe` status302

                reactivatedShiftType <- fetch inactiveShiftType.id
                reactivatedShiftType.isActive `shouldBe` True
                reactivatedShiftType.colourKey `shouldBe` activeShiftType.colourKey

        it "lets admins intentionally reuse shift type colours" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Manual Shift Colour Venue"
                admin <- createUserRecord "admin-manual-shift-colours@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                firstShiftType <-
                    createShiftTypeRecord venue level "First Shift"
                        >>= updateRecord . set #colourKey Palette3
                secondShiftType <-
                    createShiftTypeRecord venue level "Second Shift"
                        >>= updateRecord . set #colourKey Palette2

                createResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Manual Colour Shift")
                        , ("payRateSelection", "")
                        , ("colourKey", "palette_4")
                        , ("isActive", "true")
                        ]
                createResponse `responseStatusShouldBe` status302
                createdShiftType <- query @ShiftType |> filterWhere (#name, "Manual Colour Shift") |> fetchOne
                createdShiftType.colourKey `shouldBe` Palette4

                duplicateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateShiftTypeAction secondShiftType.id)
                            [ ("showInactiveShiftTypes", "false")
                            , ("name", "Second Shift")
                            , ("payRateSelection", cs ("award:" <> tshow level.id))
                            , ("colourKey", cs (inputValue firstShiftType.colourKey))
                            , ("isActive", "true")
                            ]
                duplicateResponse `responseStatusShouldBe` status200
                duplicatedSecondShiftType <- fetch secondShiftType.id
                duplicatedSecondShiftType.colourKey `shouldBe` firstShiftType.colourKey

                duplicateCreateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Another Manual Colour Shift")
                        , ("payRateSelection", "")
                        , ("colourKey", cs (inputValue firstShiftType.colourKey))
                        , ("isActive", "true")
                        ]
                duplicateCreateResponse `responseStatusShouldBe` status302
                duplicateCreatedShiftType <- query @ShiftType |> filterWhere (#name, "Another Manual Colour Shift") |> fetchOne
                duplicateCreatedShiftType.colourKey `shouldBe` firstShiftType.colourKey

        it "directs generic invites for active trial staff email to the trial renewal workflow" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Trial Email Guard Venue"
                admin <- createUserRecord "admin-trial-email-guard@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Guarded" "Trial"
                _ <- createVenueInvitationRecord venue (Just admin) "guarded-trial@example.com" Worker
                    >>= updateRecord
                        . set #staffId (Just staff.id)
                        . set #status (Revoked)
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#isDefault, True)
                    |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateVenueInvitationAction
                            [ ("email", "guarded-trial@example.com")
                            , ("rosterGroupId", idToParam rosterGroup.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Use the trial-staff renewal workflow"
                query @VenueInvitation |> fetchCount >>= (`shouldBe` 1)

        it "rejects invalid invite emails without creating invitations or broadcasting admin changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invalid Invite Venue"
                admin <- createUserRecord "admin-invalid-invite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Default Group" 0 True

                versionBefore <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateVenueInvitationAction
                            [ ("email", "not-an-email")
                            , ("rosterGroupId", idToParam rosterGroup.id)
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "id=\"admin-invites-fragment\" hx-swap-oob=\"outerHTML\""
                invitationCount <- query @VenueInvitation |> fetchCount
                invitationCount `shouldBe` 0
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "keeps at least one active roster group when admins edit config" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Last Group Venue"
                admin <- createUserRecord "admin-last-group@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <-
                    query @RosterGroup
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> filterWhere (#isActive, True)
                        |> fetchOne

                versionBefore <- currentLiveUpdateVersion (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                            [ ("showInactiveRosterGroups", "true")
                            , ("name", "Only Group")
                            , ("isActive", "false")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldNotContain` "id=\"admin-roster-groups-fragment\""
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"admin-roster-groups\"")
                triggerHeader `shouldSatisfy` maybe False (not . Text.isInfixOf "admin-roster-groups-fragment")
                unchangedRosterGroup <- fetch rosterGroup.id
                unchangedRosterGroup.isActive `shouldBe` True
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminRosterGroupsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "updates venue settings through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue Settings Fragment Venue"
                admin <- createUserRecord "admin-venue-settings-fragment@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction
                pageResponse `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\""
                pageResponse `responseBodyShouldContain` "admin-venue-config"
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateRosterTimePickerWindow\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateMinutePrecisionShiftTimesEnabled\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateUnavailableStaffWarningThreshold\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateRosterEndTimesEnabled\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateDefaultStaffPayRate\""
                pageResponse `responseBodyShouldContain` "Default staff rate"
                pageResponse `responseBodyShouldContain` "name=\"defaultStaffAwardLevelId\""
                pageResponse `responseBodyShouldContain` "No Timesheets (roster only)"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-venue-settings-fragment\""
                pageResponse `responseBodyShouldContain` "hx-swap=\"none\""
                pageResponse `responseBodyShouldContain` "Valid shift window"
                pageResponse `responseBodyShouldContain` "Minute-precision shift times"
                pageResponse `responseBodyShouldContain` "Unavailable-staff warning threshold"
                pageResponse `responseBodyShouldContain` "name=\"unavailableStaffWarningThreshold\""
                pageResponse `responseBodyShouldContain` "value=\"\""
                pageResponse `responseBodyShouldContain` "Disabled"
                pageResponse `responseBodyShouldContain` "name=\"timePickerStart\" value=\"06:00\""
                pageResponse `responseBodyShouldContain` "name=\"timePickerEnd\" value=\"05:45\""
                pageResponse `responseBodyShouldContain` "Roster window start day"
                pageResponse `responseBodyShouldContain` "hx-post=\"/PreviewRosterWindowStartDay\""
                pageResponse `responseBodyShouldContain` "name=\"rosterWeekStartsOn\""

                versionBefore <- currentLiveUpdateVersion (AdminLive.adminVenueConfigLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateRosterEndTimesEnabledAction
                            [("rosterEndTimesEnabled", "true")]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\" hx-swap-oob=\"outerHTML\""
                response `responseBodyShouldContain` "checked=\"checked\""
                response `responseBodyShouldNotContain` "id=\"app\""
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.rosterEndTimesEnabled `shouldBe` True
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminVenueConfigLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "configures the venue default staff rate and rejects unavailable or unauthorized choices" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Default Staff Rate Venue"
                admin <- createUserRecord "admin-default-staff-rate@example.com" "staff" True
                manager <- createUserRecord "manager-default-staff-rate@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue manager Manager
                awardLevel <- createPayLevelRecordWithRates venue "Default Staff Level" 32.75 3.25 6.50 1 1.25 1.50
                unavailableLevel <- createPayLevelRecordWithRates venue "Permanent-only Staff Level" 32.75 3.25 6.50 1 1.25 1.50
                unavailableCasualRates <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId unavailableLevel.id)
                    |> filterWhere (#employmentBasis, Casual)
                    |> fetch
                deleteRecords unavailableCasualRates

                awardResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateDefaultStaffPayRateAction
                        [("defaultStaffAwardLevelId", cs (tshow awardLevel.id))]
                awardResponse `responseStatusShouldBe` status302
                awardConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                awardConfig.defaultStaffPayAssignmentMode `shouldBe` AwardRate
                awardConfig.defaultStaffAwardLevelId `shouldBe` Just awardLevel.id

                unavailableResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateDefaultStaffPayRateAction
                        [("defaultStaffAwardLevelId", cs (tshow unavailableLevel.id))]
                unavailableResponse `responseStatusShouldBe` status302
                unchangedConfig <- fetch awardConfig.id
                unchangedConfig.defaultStaffAwardLevelId `shouldBe` Just awardLevel.id

                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams UpdateDefaultStaffPayRateAction
                        [("defaultStaffAwardLevelId", "")]
                managerResponse `responseStatusShouldBe` status302
                managerRejectedConfig <- fetch awardConfig.id
                managerRejectedConfig.defaultStaffPayAssignmentMode `shouldBe` AwardRate

                rosterOnlyResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateDefaultStaffPayRateAction
                        [("defaultStaffAwardLevelId", "")]
                rosterOnlyResponse `responseStatusShouldBe` status302
                rosterOnlyConfig <- fetch awardConfig.id
                rosterOnlyConfig.defaultStaffPayAssignmentMode `shouldBe` RosterOnly
                rosterOnlyConfig.defaultStaffAwardLevelId `shouldBe` Nothing

        it "configures, disables, and validates the unavailable-staff warning threshold" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Availability Threshold Venue"
                admin <- createUserRecord "admin-availability-threshold@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                auditCountBefore <- query @AuditEvent |> fetchCount
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                enabledResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateUnavailableStaffWarningThresholdAction
                            [("unavailableStaffWarningThreshold", "3")]

                enabledResponse `responseStatusShouldBe` status200
                enabledResponse `responseBodyShouldContain` "value=\"3\""
                enabledConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                enabledConfig.unavailableStaffWarningThreshold `shouldBe` Just 3
                enabledConfig.updatedAt `shouldSatisfy` (> originalConfig.updatedAt)

                invalidResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateUnavailableStaffWarningThresholdAction
                        [("unavailableStaffWarningThreshold", "101")]
                invalidResponse `responseStatusShouldBe` status302
                unchangedConfig <- fetch enabledConfig.id
                unchangedConfig.unavailableStaffWarningThreshold `shouldBe` Just 3

                zeroResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateUnavailableStaffWarningThresholdAction
                        [("unavailableStaffWarningThreshold", "0")]
                zeroResponse `responseStatusShouldBe` status302
                zeroRejectedConfig <- fetch enabledConfig.id
                zeroRejectedConfig.unavailableStaffWarningThreshold `shouldBe` Just 3

                boundaryResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateUnavailableStaffWarningThresholdAction
                        [("unavailableStaffWarningThreshold", "100")]
                boundaryResponse `responseStatusShouldBe` status302
                boundaryConfig <- fetch enabledConfig.id
                boundaryConfig.unavailableStaffWarningThreshold `shouldBe` Just 100

                disabledResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateUnavailableStaffWarningThresholdAction []
                disabledResponse `responseStatusShouldBe` status302
                disabledConfig <- fetch enabledConfig.id
                disabledConfig.unavailableStaffWarningThreshold `shouldBe` Nothing
                auditCountAfter <- query @AuditEvent |> fetchCount
                auditCountAfter `shouldBe` auditCountBefore

        it "updates non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Kitchen"
                overrideLevel <- createPayLevelRecord venue "Level 2"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 5 True

                moveGroupUpResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (MoveRosterGroupUpAction rosterGroup.id) [("showInactiveRosterGroups", "false")]
                moveGroupUpResponse `responseStatusShouldBe` status302

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                        [ ("showInactiveRosterGroups", "false")
                        , ("name", "Back of House Updated")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Kitchen Updated")
                        , ("payRateSelection", cs ("award:" <> tshow overrideLevel.id))
                        , ("colourKey", cs (inputValue shiftType.colourKey))
                        , ("isActive", "false")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302

                updatedShiftType <- fetch shiftType.id
                updatedRosterGroup <- fetch rosterGroup.id
                defaultRosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                updatedRosterGroup.name `shouldBe` "Back of House Updated"
                updatedRosterGroup.sortOrder `shouldBe` 0
                updatedRosterGroup.isActive `shouldBe` True
                get #id defaultRosterGroup `shouldBe` get #id updatedRosterGroup
                updatedShiftType.name `shouldBe` "Kitchen Updated"
                updatedShiftType.overrideAwardLevelId `shouldBe` Just overrideLevel.id
                updatedShiftType.isActive `shouldBe` False

        it "previews and confirms the exact mixed-publication impact" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Roster window impact venue"
                admin <- createUserRecord "roster-window-impact-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                slotName <- query @SlotName
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> fetchOne
                _ <- createRosterWeekRecord venue 0 True
                _ <- createRosterWeekRecord venue 1 True
                allRosterDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> orderByAsc #operationalDate
                    |> fetch
                forM_ (List.drop 8 allRosterDays) (updateRecord . set #publicationState Draft)
                let rosterDays = List.take 8 allRosterDays
                let (firstRosterDay, remainingRosterDays) = case rosterDays of
                        firstDay : remainingDays -> (firstDay, remainingDays)
                        [] -> error "Expected dated roster fixture days"
                firstShift <- createRosterSlotRecord firstRosterDay slotName Nothing 0

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                preview <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation venueConfig 2
                preview `shouldSatisfy` either (const False) (const True)
                let Right initialImpact = preview
                initialImpact.mixedPublishedWindowCount `shouldBe` 1
                initialImpact.affectedPublishedDayCount `shouldBe` 1
                initialImpact.affectedShiftCount `shouldBe` 1

                secondShift <- createRosterSlotRecord firstRosterDay slotName Nothing 1
                staleConfirmation <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        confirmRosterWindowStartDayMutation venueConfig initialImpact
                staleConfirmation `shouldBe` Left "The roster calendar impact changed. Review the refreshed confirmation and try again."
                unchangedConfig <- fetch venueConfig.id
                unchangedConfig.rosterWeekStartsOn `shouldBe` venueConfig.rosterWeekStartsOn
                fetch firstRosterDay.id >>= (\day -> day.publicationState `shouldBe` Published)

                Right currentImpact <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation venueConfig 2
                currentImpact.affectedShiftCount `shouldBe` 2
                confirmed <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        confirmRosterWindowStartDayMutation venueConfig currentImpact
                confirmed `shouldSatisfy` either (const False) (const True)
                updatedConfig <- fetch venueConfig.id
                updatedConfig.rosterWeekStartsOn `shouldBe` 2
                updatedConfig.rosterCalendarRevision `shouldBe` venueConfig.rosterCalendarRevision + 1
                fetch firstRosterDay.id >>= (\day -> day.publicationState `shouldBe` Draft)
                fetch firstShift.id `shouldReturn` firstShift
                fetch secondShift.id `shouldReturn` secondShift
                mapM fetch (map (.id) remainingRosterDays) >>= (\days -> days `shouldSatisfy` all ((== Published) . (.publicationState)))

        it "serializes concurrent roster window start-day confirmations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent roster window venue"
                admin <- createUserRecord "concurrent-roster-window-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                Right impact <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation venueConfig 2
                let confirm = withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withCurrentControllerContext do
                            confirmRosterWindowStartDayMutation venueConfig impact
                (firstResult, secondResult) <- Async.concurrently confirm confirm
                length (filter (either (const False) (const True)) [firstResult, secondResult]) `shouldBe` 1
                [message] <- pure [failure | Left failure <- [firstResult, secondResult]]
                message `shouldBe` "The roster calendar changed. Review the refreshed setting and try again."
                updatedConfig <- fetch venueConfig.id
                updatedConfig.rosterWeekStartsOn `shouldBe` 2
                updatedConfig.rosterCalendarRevision `shouldBe` venueConfig.rosterCalendarRevision + 1

        it "normalizes partial Published windows to Draft under a proposed start day" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Publication normalization venue"
                admin <- createUserRecord "publication-normalization-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                secondGroup <- createVenueRosterGroupWithDefaults venue "Second publication group" 1 False
                otherVenue <- createVenueWithConfig "Other publication venue"
                otherGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId otherVenue.id)
                    |> fetchOne
                forM_ (zip [0 :: Int ..] [fromGregorian 2025 1 6 .. fromGregorian 2025 1 13]) \(dayOffset, operationalDate) ->
                    newRecord @RosterDay
                        |> set #venueId (unpackId venue.id)
                        |> set #rosterGroupId (unpackId rosterGroup.id)
                        |> set #operationalDate operationalDate
                        |> set #publicationState Published
                        |> set #dayOffset (dayOffset `mod` 7)
                        |> createRecord
                _ <- newRecord @RosterDay
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId secondGroup.id)
                    |> set #operationalDate (fromGregorian 2025 1 7)
                    |> set #publicationState Published
                    |> createRecord
                otherPublishedDay <- newRecord @RosterDay
                    |> set #venueId (unpackId otherVenue.id)
                    |> set #rosterGroupId (unpackId otherGroup.id)
                    |> set #operationalDate (fromGregorian 2025 1 6)
                    |> set #publicationState Published
                    |> createRecord

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                Right initialImpact <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation venueConfig 2
                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        confirmRosterWindowStartDayMutation venueConfig initialImpact

                normalizedDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> orderByAsc #operationalDate
                    |> fetch
                map (\day -> (day.operationalDate, day.publicationState)) normalizedDays
                    `shouldBe` [ (fromGregorian 2025 1 6, Draft)
                               , (fromGregorian 2025 1 7, Published)
                               , (fromGregorian 2025 1 8, Published)
                               , (fromGregorian 2025 1 9, Published)
                               , (fromGregorian 2025 1 10, Published)
                               , (fromGregorian 2025 1 11, Published)
                               , (fromGregorian 2025 1 12, Published)
                               , (fromGregorian 2025 1 13, Published)
                               ]
                normalizedSecondGroup <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId secondGroup.id)
                    |> fetchOne
                normalizedSecondGroup.publicationState `shouldBe` Draft
                fetch otherPublishedDay.id >>= (\day -> day.publicationState `shouldBe` Published)

                updatedConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                Right reverseImpact <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation updatedConfig 1
                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        confirmRosterWindowStartDayMutation updatedConfig reverseImpact
                reversedDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                    |> fetch
                reversedDays `shouldSatisfy` all ((== Draft) . (.publicationState))

        it "previews roster window start-day impact before explicit confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin roster window preview venue"
                admin <- createUserRecord "admin-roster-window-preview@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                initialConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                malformedResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams PreviewRosterWindowStartDayAction
                        [("rosterWeekStartsOn", "not-a-weekday")]
                malformedResponse `responseStatusShouldBe` status302
                fetch initialConfig.id >>= (\config -> config.rosterWeekStartsOn `shouldBe` initialConfig.rosterWeekStartsOn)

                previewResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams PreviewRosterWindowStartDayAction
                            [ ("rosterWeekStartsOn", "2")
                            , ("rosterCalendarRevision", cs (tshow initialConfig.rosterCalendarRevision))
                            ]

                previewResponse `responseStatusShouldBe` status200
                previewResponse `responseBodyShouldContain` "Confirm roster window start day"
                previewResponse `responseBodyShouldContain` "id=\"admin-roster-window-start-day-setting\""
                previewResponse `responseBodyShouldNotContain` "hx-swap-oob"
                previewResponse `responseBodyShouldContain` "Tuesday"
                previewResponse `responseBodyShouldContain` "Mixed Published windows"
                previewResponse `responseBodyShouldContain` "Published days returning to Draft"
                previewResponse `responseBodyShouldContain` "Shifts on affected days"
                previewResponse `responseBodyShouldContain` "name=\"mixedPublishedWindowCount\" value=\"0\""
                previewResponse `responseBodyShouldContain` "hx-post=\"/UpdateRosterWeekStartsOn\""
                unchangedConfig <- fetch initialConfig.id
                unchangedConfig.rosterWeekStartsOn `shouldBe` initialConfig.rosterWeekStartsOn

                confirmResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateRosterWeekStartsOnAction
                            [ ("rosterWeekStartsOn", "2")
                            , ("rosterCalendarRevision", cs (tshow initialConfig.rosterCalendarRevision))
                            , ("currentRosterWindowStartDay", cs (tshow initialConfig.rosterWeekStartsOn))
                            , ("mixedPublishedWindowCount", "0")
                            , ("affectedPublishedDayCount", "0")
                            , ("affectedShiftCount", "0")
                            ]
                confirmResponse `responseStatusShouldBe` status200
                confirmResponse `responseBodyShouldContain` "id=\"admin-roster-window-start-day-setting\""
                confirmResponse `responseBodyShouldNotContain` "hx-swap-oob"
                lookup "HX-Trigger" (responseHeaders confirmResponse) `shouldSatisfy` isJust
                confirmedConfig <- fetch initialConfig.id
                confirmedConfig.rosterWeekStartsOn `shouldBe` 2

        it "updates the roster week start after venue history exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-week-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                _ <- newRecord @RosterDay
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #operationalDate (fromGregorian 2025 1 6)
                    |> set #publicationState Draft
                    |> createRecord

                initialConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateRosterWeekStartsOnAction
                        [ ("rosterWeekStartsOn", "2")
                        , ("rosterCalendarRevision", cs (tshow initialConfig.rosterCalendarRevision))
                        , ("currentRosterWindowStartDay", cs (tshow initialConfig.rosterWeekStartsOn))
                        , ("mixedPublishedWindowCount", "0")
                        , ("affectedPublishedDayCount", "0")
                        , ("affectedShiftCount", "0")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                venueConfig.rosterWeekStartsOn `shouldBe` 2
                venueConfig.weekOffsetEpoch `shouldBe` defaultWeekOffsetEpochForStartDay 2
                venueConfig.rosterCalendarRevision `shouldSatisfy` (> initialConfig.rosterCalendarRevision)

        it "rejects a stale roster week-start confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin stale calendar venue"
                admin <- createUserRecord "admin-stale-week-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staleConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                Right interveningImpact <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        previewRosterWindowStartDayMutation staleConfig 3
                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withCurrentControllerContext do
                        confirmRosterWindowStartDayMutation staleConfig interveningImpact

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateRosterWeekStartsOnAction
                        [ ("rosterWeekStartsOn", "2")
                        , ("rosterCalendarRevision", cs (tshow staleConfig.rosterCalendarRevision))
                        , ("currentRosterWindowStartDay", cs (tshow staleConfig.rosterWeekStartsOn))
                        , ("mixedPublishedWindowCount", "0")
                        , ("affectedPublishedDayCount", "0")
                        , ("affectedShiftCount", "0")
                        ]

                response `responseStatusShouldBe` status302
                currentConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                currentConfig.rosterWeekStartsOn `shouldBe` 3

        it "toggles roster end times without changing the roster week start" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-roster-end-times@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateRosterEndTimesEnabledAction
                        [("rosterEndTimesEnabled", "true")]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.rosterEndTimesEnabled `shouldBe` True
                venueConfig.rosterWeekStartsOn `shouldBe` originalConfig.rosterWeekStartsOn

        it "toggles minute-precision shift and timesheet entry" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Minute Precision Venue"
                admin <- createUserRecord "admin-minute-precision@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateMinutePrecisionShiftTimesEnabledAction
                        [("minutePrecisionShiftTimesEnabled", "true")]

                response `responseStatusShouldBe` status302
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.minutePrecisionShiftTimesEnabled `shouldBe` True

        it "updates the venue time picker window without changing the roster week start" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-time-picker-window@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateRosterTimePickerWindowAction
                        [ ("timePickerStart", "09:00")
                        , ("timePickerEnd", "02:00")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.timePickerStartMinuteOfDay `shouldBe` 540
                venueConfig.timePickerFinalSelectableMinuteOfDay `shouldBe` 120
                venueConfig.rosterWeekStartsOn `shouldBe` originalConfig.rosterWeekStartsOn

        it "rejects invalid venue time picker windows" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-time-picker-window-invalid@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateRosterTimePickerWindowAction
                        [ ("timePickerStart", "09:10")
                        , ("timePickerEnd", "09:10")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.timePickerStartMinuteOfDay `shouldBe` originalConfig.timePickerStartMinuteOfDay
                venueConfig.timePickerFinalSelectableMinuteOfDay `shouldBe` originalConfig.timePickerFinalSelectableMinuteOfDay

        it "rejects updates to config rows outside the current venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueAdmin
                _ <- createVenueMembershipRecord venueB admin VenueAdmin
                foreignLevel <- createPayLevelRecord venueB "Foreign Level"
                foreignShiftType <- createShiftTypeRecord venueB foreignLevel "Foreign Shift"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdateShiftTypeAction foreignShiftType.id)
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Should Not Work")
                        , ("payRateSelection", "")
                        , ("colourKey", "no_colour")
                        , ("isActive", "false")
                        ]

                response `responseStatusShouldBe` status403

                unchangedShiftType <- fetch foreignShiftType.id
                unchangedShiftType.name `shouldBe` "Foreign Shift"
                unchangedShiftType.isActive `shouldBe` True

        it "versions payroll-relevant FWC-backed config changes while skipping roster-only edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-save@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("showInactiveRosterGroups", "false")
                        , ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                query @ShiftTypePayVersion |> fetch `shouldReturn` []

                _ <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Supervisor")
                        , ("payRateSelection", "")
                        , ("colourKey", "no_colour")
                        , ("isActive", "true")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                versions <- query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch
                map (.createdByUserId) versions `shouldBe` [unpackId admin.id]
                map (.payAssignmentMode) versions `shouldBe` [StaffDefault]

openingTagWithId :: Text -> LByteString.ByteString -> String
openingTagWithId elementId body =
    cs ("<select" <> afterSelect <> Text.takeWhile (/= '>') rest <> ">")
  where
    bodyText = cs body :: Text
    token = "id=\"" <> elementId <> "\""
    (beforeToken, rest) = Text.breakOn token bodyText
    (_, afterSelect) = Text.breakOnEnd "<select" beforeToken

shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    case mapM markerPosition needles of
        Nothing -> expectationFailure ("Expected body to contain all markers in order: " ++ cs (show needles))
        Just positions -> positions `shouldSatisfy` ordered
    where
        markerPosition marker = List.findIndex (List.isPrefixOf marker) (List.tails haystack)
        ordered positions = positions == List.sort positions
