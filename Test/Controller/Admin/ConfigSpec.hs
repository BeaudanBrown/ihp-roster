module Test.Controller.Admin.ConfigSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      unsafeEnumFromText)
import Application.Helper.Export (ExportJobType (..), exportJobTypeToText)
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminVenueSettingsResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekBoundaryConfigResource)
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey)
import Application.Helper.SurfaceResource
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.Helper.Xero
import Config
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
import Web.Admin.Mutations (adminVenueSettingsTouchedResources,
                            rosterEndTimesTouchedResources,
                            rosterTimePickerWindowTouchedResources,
                            rosterWeekStartsOnTouchedResources)
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                planSurfaceInvalidations)
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "AdminController" do
        it "allows venue owners to access admin config screens" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                owner <- createUserRecord "owner-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"

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
                response `responseBodyShouldNotContain` "Exports"
                response `responseBodyShouldContain` "id=\"invites-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"venue-settings-collapse\" class=\"accordion-collapse collapse\""
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
                        , rosterWeekBoundaryConfigResource venueId
                        , timesheetWeekBoundaryConfigResource venueId
                        ]

        it "plans roster content refreshes for roster-affecting venue config resources" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Roster Config Planning Venue"
                admin <- createUserRecord "admin-roster-config-planning@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                let venueId = unpackId venue.id
                let scope = RosterLive.rosterWeekLiveScope venueId (unpackId rosterGroup.id) 0
                let rosterContentFragments =
                        [ RosterLive.rosterContentLiveFragment
                        , RosterLive.rosterGridToolbarLiveFragment
                        , RosterLive.rosterGridFrameLiveFragment
                        , RosterLive.rosterDayColumnsLiveFragment
                        , RosterLive.rosterDayRailLiveFragment
                        , RosterLive.rosterWageRailLiveFragment
                        , RosterLive.rosterSlotsGridLiveFragment
                        ]
                let subscription =
                        SurfaceSubscription
                            { subscriptionScope = scope
                            , subscriptionScopeKey = surfaceScopeKey scope
                            , subscriptionFragmentKeys = rosterContentFragments
                            }
                let planFragments resource = withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                        withCurrentControllerContext do
                            pure
                                [ (target.targetScope, target.targetFragments)
                                | target <- planSurfaceInvalidations (Set.singleton resource) [subscription]
                                ]

                planFragments (rosterEndTimesConfigResource venueId)
                    `shouldReturn` [(scope, rosterContentFragments)]
                planFragments (rosterWeekBoundaryConfigResource venueId)
                    `shouldReturn` [(scope, rosterContentFragments)]

        it "shows the Xero header button and page to super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Super Admin Venue"
                superAdmin <- createUserRecordWithPlatformRole "xero-super-admin@example.com" "staff" (Just SuperAdminRole) True

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
                _ <- createVenueMembershipRecord venue venueAdmin "venue_admin"

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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                        , ("colourKey", "")
                        , ("isActive", "true")
                        ]
                createResponse `responseStatusShouldBe` status302
                createdShiftType <- query @ShiftType
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#name, "Imported Pay Rate Shift" :: Text)
                    |> fetchOne
                createdShiftType.overrideAwardLevelId `shouldBe` Nothing
                createdShiftType.importedXeroPayItemId `shouldBe` Just importedPayItem.id

        it "hides archived imported Xero pay items from shift type dropdowns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Archived Imported Pay Item Venue"
                admin <- createUserRecord "admin-archived-imported-pay-items@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                venueSettingsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ShowAdminVenueSettingsFragmentAction
                venueSettingsResponse `responseStatusShouldBe` status200
                venueSettingsResponse `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface=\""
                venueSettingsResponse `responseBodyShouldContain` "admin-venue-config"
                venueSettingsResponse `responseBodyShouldContain` "hx-post=\"/UpdateVenueConfig\""
                venueSettingsResponse `responseBodyShouldContain` "hx-target=\"#admin-venue-settings-fragment\""
                venueSettingsResponse `responseBodyShouldContain` "hx-swap=\"none\""
                venueSettingsResponse `responseBodyShouldContain` "hx-push-url=\"false\""
                venueSettingsResponse `responseBodyShouldContain` "data-bepis-surface-action=\"update-venue-config\""
                venueSettingsResponse `responseBodyShouldNotContain` "Roster week starts on"
                venueSettingsResponse `responseBodyShouldNotContain` "admin-roster-week-starts-on"
                venueSettingsResponse `responseBodyShouldNotContain` "name=\"rosterWeekStartsOn\""
                venueSettingsResponse `responseBodyShouldNotContain` "Automatically create pending timesheets"
                venueSettingsResponse `responseBodyShouldNotContain` "autoTimesheetCreationEnabled"
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
                exportsResponse `responseBodyShouldNotContain` "id=\"app\""

        it "creates export jobs through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Export Fragment Mutation Venue"
                admin <- createUserRecord "admin-export-fragment-mutation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

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
                response `responseBodyShouldContain` "id=\"admin-exports-fragment\" hx-swap-oob=\"outerHTML\""
                response `responseBodyShouldContain` "approved-timesheets-2025-01-06-to-2025-01-12.csv"
                response `responseBodyShouldNotContain` "id=\"app\""
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminExportsLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "serves shift type and roster group add/update through targeted admin fragments" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Mutation Fragment Venue"
                admin <- createUserRecord "admin-mutation-fragments@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                            , ("colourKey", "")
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
                            , ("colourKey", "")
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                        , ("colourKey", "")
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
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 86000 && seconds < 87000)

        it "hides accepted and expired venue invitations after one week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invite Retention Venue"
                admin <- createUserRecord "admin-invite-retention@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                now <- getCurrentTime
                let daysAgo days = addUTCTime (negate (days * 24 * 60 * 60)) now

                _ <- createVenueInvitationRecord venue (Just admin) "active-pending@example.com" "worker"
                _ <- createVenueInvitationRecord venue (Just admin) "recent-expired@example.com" "worker"
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-3600) now))
                _ <- createVenueInvitationRecord venue (Just admin) "old-expired@example.com" "worker"
                    >>= updateRecord . set #expiresAt (Just (daysAgo 8))
                _ <- createVenueInvitationRecord venue (Just admin) "recent-accepted@example.com" "worker"
                    >>= updateRecord
                        . set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                        . set #acceptedAt (Just (daysAgo 3))
                _ <- createVenueInvitationRecord venue (Just admin) "old-accepted@example.com" "worker"
                    >>= updateRecord
                        . set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Unhighlighted Shift")
                        , ("payRateSelection", "")
                        , ("colourKey", "")
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                activeShiftType <-
                    createShiftTypeRecord venue level "Active Shift"
                        >>= updateRecord . set #colourKey "palette-1"
                inactiveShiftType <-
                    createShiftTypeRecord venue level "Inactive Shift"
                        >>= updateRecord . set #isActive False . set #colourKey activeShiftType.colourKey

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction inactiveShiftType.id)
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Inactive Shift")
                        , ("payRateSelection", cs ("award:" <> tshow level.id))
                        , ("colourKey", cs activeShiftType.colourKey)
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                level <- createPayLevelRecord venue "Level 1"
                firstShiftType <-
                    createShiftTypeRecord venue level "First Shift"
                        >>= updateRecord . set #colourKey "palette-3"
                secondShiftType <-
                    createShiftTypeRecord venue level "Second Shift"
                        >>= updateRecord . set #colourKey "palette-2"

                createResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Manual Colour Shift")
                        , ("payRateSelection", "")
                        , ("colourKey", "palette-4")
                        , ("isActive", "true")
                        ]
                createResponse `responseStatusShouldBe` status302
                createdShiftType <- query @ShiftType |> filterWhere (#name, "Manual Colour Shift") |> fetchOne
                createdShiftType.colourKey `shouldBe` "palette-4"

                duplicateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateShiftTypeAction secondShiftType.id)
                            [ ("showInactiveShiftTypes", "false")
                            , ("name", "Second Shift")
                            , ("payRateSelection", cs ("award:" <> tshow level.id))
                            , ("colourKey", cs firstShiftType.colourKey)
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
                        , ("colourKey", cs firstShiftType.colourKey)
                        , ("isActive", "true")
                        ]
                duplicateCreateResponse `responseStatusShouldBe` status302
                duplicateCreatedShiftType <- query @ShiftType |> filterWhere (#name, "Another Manual Colour Shift") |> fetchOne
                duplicateCreatedShiftType.colourKey `shouldBe` firstShiftType.colourKey

        it "rejects invalid invite emails without creating invitations or broadcasting admin changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invalid Invite Venue"
                admin <- createUserRecord "admin-invalid-invite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                pageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction AdminAction
                pageResponse `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\""
                pageResponse `responseBodyShouldContain` "admin-venue-config"
                pageResponse `responseBodyShouldContain` "hx-post=\"/UpdateVenueConfig\""
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-venue-settings-fragment\""
                pageResponse `responseBodyShouldContain` "hx-swap=\"none\""
                pageResponse `responseBodyShouldContain` "Valid shift window"
                pageResponse `responseBodyShouldContain` "name=\"timePickerStart\" value=\"06:00\""
                pageResponse `responseBodyShouldContain` "name=\"timePickerEnd\" value=\"05:45\""
                pageResponse `responseBodyShouldNotContain` "Roster week starts on"
                pageResponse `responseBodyShouldNotContain` "admin-roster-week-starts-on"
                pageResponse `responseBodyShouldNotContain` "name=\"rosterWeekStartsOn\""

                versionBefore <- currentLiveUpdateVersion (AdminLive.adminVenueConfigLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateVenueConfigAction
                            [ ("configField", "rosterEndTimesEnabled")
                            , ("rosterEndTimesEnabled", "true")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "id=\"admin-venue-settings-fragment\" hx-swap-oob=\"outerHTML\""
                response `responseBodyShouldContain` "checked=\"checked\""
                response `responseBodyShouldNotContain` "id=\"app\""
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.rosterEndTimesEnabled `shouldBe` True
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminVenueConfigLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "updates non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-update@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                        , ("colourKey", cs shiftType.colourKey)
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

        it "updates the roster week start before venue history exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-week-start@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [ ("configField", "rosterWeekStartsOn")
                        , ("rosterWeekStartsOn", "2")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                venueConfig.rosterWeekStartsOn `shouldBe` 2
                venueConfig.weekOffsetEpoch `shouldBe` defaultWeekOffsetEpochForStartDay 2

        it "toggles roster end times without changing the roster week start" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-roster-end-times@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [ ("configField", "rosterEndTimesEnabled")
                        , ("rosterEndTimesEnabled", "true")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.rosterEndTimesEnabled `shouldBe` True
                venueConfig.rosterWeekStartsOn `shouldBe` originalConfig.rosterWeekStartsOn

        it "updates the venue time picker window without changing the roster week start" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-time-picker-window@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [ ("configField", "timePickerWindow")
                        , ("timePickerStart", "09:00")
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [ ("configField", "timePickerWindow")
                        , ("timePickerStart", "09:10")
                        , ("timePickerEnd", "09:10")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.timePickerStartMinuteOfDay `shouldBe` originalConfig.timePickerStartMinuteOfDay
                venueConfig.timePickerFinalSelectableMinuteOfDay `shouldBe` originalConfig.timePickerFinalSelectableMinuteOfDay

        it "ignores the retired automatic-timesheet venue setting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-auto-timesheets@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                originalConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams UpdateVenueConfigAction
                        [ ("configField", "autoTimesheetCreationEnabled")
                        , ("autoTimesheetCreationEnabled", "true")
                        ]

                response `responseStatusShouldBe` status302

                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                venueConfig.autoTimesheetCreationEnabled `shouldBe` False
                venueConfig.rosterWeekStartsOn `shouldBe` originalConfig.rosterWeekStartsOn

        it "rejects updates to config rows outside the current venue" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "admin-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"
                foreignLevel <- createPayLevelRecord venueB "Foreign Level"
                foreignShiftType <- createShiftTypeRecord venueB foreignLevel "Foreign Shift"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (UpdateShiftTypeAction foreignShiftType.id)
                        [ ("showInactiveShiftTypes", "false")
                        , ("name", "Should Not Work")
                        , ("payRateSelection", "")
                        , ("colourKey", "")
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"

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
                        , ("colourKey", "")
                        , ("isActive", "true")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                versions <- query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch
                map (.createdByUserId) versions `shouldBe` [unpackId admin.id]

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
