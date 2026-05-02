module Test.Controller.Admin.ConfigSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
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
import Web.Controller.Admin ()
import Web.FrontController ()
import Web.Routes
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
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "href=\"/Xero\""
                response `responseBodyShouldNotContain` "Venue Config"

        it "shows the Xero header button and page to super admins" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Xero Super Admin Venue"
                superAdmin <- createUserRecordWithPlatformRole "xero-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withPasskeyVerifiedUserAndCurrentVenue superAdmin venue.id do
                    callAction XeroAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/Xero\""
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
                    callActionWithParams ShowAdminShiftTypesFragmentAction
                        [("showInactiveShiftTypes", "false")]
                hiddenShiftTypesResponse `responseStatusShouldBe` status200
                hiddenShiftTypesResponse `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "data-live-update-surface=\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "admin_shift_types"
                hiddenShiftTypesResponse `responseBodyShouldContain` "&quot;deferUntilBlur&quot;:true"
                hiddenShiftTypesResponse `responseBodyShouldContain` "&quot;kind&quot;:&quot;focused_field&quot;"
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-get=\"/ShowAdminShiftTypesFragment?showInactiveShiftTypes=true\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                hiddenShiftTypesResponse `responseBodyShouldContain` "Active Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "btn btn-outline-secondary w-100"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "Inactive Shift"
                hiddenShiftTypesResponse `responseBodyShouldNotContain` "id=\"app\""

                visibleShiftTypesResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminShiftTypesFragmentAction
                        [("showInactiveShiftTypes", "true")]
                visibleShiftTypesResponse `responseStatusShouldBe` status200
                visibleShiftTypesResponse `responseBodyShouldContain` "Inactive Shift"
                visibleShiftTypesBody <- responseBody visibleShiftTypesResponse
                (cs visibleShiftTypesBody :: String) `shouldContainInOrder` ["Active Shift", "Inactive Shift"]
                visibleShiftTypesResponse `responseBodyShouldContain` "checked=\"checked\""

                hiddenRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminRosterGroupsFragmentAction
                        [("showInactiveRosterGroups", "false")]
                hiddenRosterGroupsResponse `responseStatusShouldBe` status200
                hiddenRosterGroupsResponse `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "data-live-update-surface=\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "admin_roster_groups"
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-get=\"/ShowAdminRosterGroupsFragment?showInactiveRosterGroups=true\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                hiddenRosterGroupsResponse `responseBodyShouldContain` "Active Group"
                hiddenRosterGroupsResponse `responseBodyShouldNotContain` "Inactive Group"

                visibleRosterGroupsResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams ShowAdminRosterGroupsFragmentAction
                        [("showInactiveRosterGroups", "true")]
                visibleRosterGroupsResponse `responseStatusShouldBe` status200
                visibleRosterGroupsResponse `responseBodyShouldContain` "Inactive Group"
                visibleRosterGroupsBody <- responseBody visibleRosterGroupsResponse
                (cs visibleRosterGroupsBody :: String) `shouldContainInOrder` ["Active Group", "Inactive Group"]
                visibleRosterGroupsResponse `responseBodyShouldContain` "checked=\"checked\""

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
                pageResponse `responseBodyShouldContain` "admin_shift_types"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-shift-types-fragment\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveShiftTypes\" value=\"true\""
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateShiftType?shiftTypeId=" <> tshow shiftType.id <> "\"")
                pageResponse `responseBodyShouldContain` "hx-trigger=\"input changed delay:600ms, blur changed\""
                pageResponse `responseBodyShouldContain` "hx-trigger=\"change\""
                pageResponse `responseBodyShouldContain` "hx-include=\"closest form\""
                pageResponse `responseBodyShouldContain` "data-admin-shift-type-field-key=\""
                pageResponse `responseBodyShouldContain` "hx-post=\"/CreateRosterGroup\""
                pageResponse `responseBodyShouldContain` "admin_roster_groups"
                pageResponse `responseBodyShouldContain` "hx-target=\"#admin-roster-groups-fragment\""
                pageResponse `responseBodyShouldContain` "name=\"showInactiveRosterGroups\" value=\"true\""
                pageResponse `responseBodyShouldContain` ("hx-post=\"/UpdateRosterGroup?rosterGroupId=" <> tshow rosterGroup.id)

                shiftTypesVersionBefore <- currentLiveUpdateVersion AdminShiftTypesScope { venueId = unpackId venue.id }
                xeroVersionBefore <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                createShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateShiftTypeAction
                            [ ("name", "Fragment Shift")
                            , ("isActive", "true")
                            , ("overrideAwardLevelId", idToParam level.id)
                            , ("showInactiveShiftTypes", "true")
                            ]
                createShiftResponse `responseStatusShouldBe` status200
                createShiftResponse `responseBodyShouldContain` "id=\"admin-shift-types-fragment\""
                createShiftResponse `responseBodyShouldContain` "Fragment Shift"
                createShiftResponse `responseBodyShouldContain` "checked=\"checked\""
                createShiftResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                createShiftResponse `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                createShiftResponse `responseBodyShouldNotContain` "id=\"app\""
                shiftTypesVersionAfter <- currentLiveUpdateVersion AdminShiftTypesScope { venueId = unpackId venue.id }
                shiftTypesVersionAfter `shouldBe` (shiftTypesVersionBefore + 1)
                xeroVersionAfterCreateShift <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                xeroVersionAfterCreateShift `shouldBe` (xeroVersionBefore + 1)

                updateShiftResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateShiftTypeAction shiftType.id)
                            [ ("name", "Updated Fragment Shift")
                            , ("isActive", "false")
                            , ("overrideAwardLevelId", "")
                            , ("showInactiveShiftTypes", "true")
                            ]
                updateShiftResponse `responseStatusShouldBe` status200
                updateShiftResponse `responseBodyShouldContain` "Updated Fragment Shift"
                updateShiftResponse `responseBodyShouldContain` "inactive"
                updateShiftResponse `responseBodyShouldNotContain` "id=\"admin-xero-fragment\""
                updateShiftResponse `responseBodyShouldNotContain` "hx-swap-oob=\"outerHTML\""
                xeroVersionAfterUpdateShift <- currentLiveUpdateVersion AdminXeroScope { venueId = unpackId venue.id }
                xeroVersionAfterUpdateShift `shouldBe` (xeroVersionAfterCreateShift + 1)

                rosterGroupsVersionBefore <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
                createRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterGroupAction
                            [ ("name", "Fragment Group")
                            , ("isActive", "true")
                            , ("showInactiveRosterGroups", "true")
                            ]
                createRosterGroupResponse `responseStatusShouldBe` status200
                createRosterGroupResponse `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                createRosterGroupResponse `responseBodyShouldContain` "Fragment Group"
                createRosterGroupResponse `responseBodyShouldContain` "Archived Group"
                createRosterGroupResponse `responseBodyShouldContain` "checked=\"checked\""
                createRosterGroupResponse `responseBodyShouldNotContain` "id=\"app\""
                rosterGroupsVersionAfter <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
                rosterGroupsVersionAfter `shouldBe` (rosterGroupsVersionBefore + 1)

                updateRosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                            [ ("name", "Updated Fragment Group")
                            , ("isActive", "true")
                            , ("showInactiveRosterGroups", "true")
                            ]
                updateRosterGroupResponse `responseStatusShouldBe` status200
                updateRosterGroupResponse `responseBodyShouldContain` "Updated Fragment Group"
                updateRosterGroupResponse `responseBodyShouldContain` tshow inactiveRosterGroup.id

        it "creates venue-scoped non-pay config rows from the admin page" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Venue"
                admin <- createUserRecord "admin-create@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                inviteNow <- getCurrentTime

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateRosterGroupAction
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                createdRosterGroup <- query @RosterGroup |> filterWhere (#name, "Back of House") |> fetchOne

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
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
                createdInvitation.venueId `shouldBe` unpackId venue.id
                createdInvitation.invitedByUserId `shouldBe` Just (unpackId admin.id)
                createdInvitation.acceptedAt `shouldBe` Nothing
                inputValue createdInvitation.inviteRole `shouldBe` "worker"
                inputValue createdInvitation.status `shouldBe` "pending"
                inputValue createdInvitation.deliveryStatus `shouldSatisfy` (`elem` ["queued", "sent", "failed"])
                inviteExpiryDeltaSeconds `shouldSatisfy` (\seconds -> seconds > 86000 && seconds < 87000)

        it "rejects invalid invite emails without creating invitations or broadcasting admin changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Invalid Invite Venue"
                admin <- createUserRecord "admin-invalid-invite@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Default Group" 0 True

                versionBefore <- currentLiveUpdateVersion AdminInvitesScope { venueId = unpackId venue.id }
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateVenueInvitationAction
                            [ ("email", "not-an-email")
                            , ("rosterGroupId", idToParam rosterGroup.id)
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"admin-invites-fragment\""
                invitationCount <- query @VenueInvitation |> fetchCount
                invitationCount `shouldBe` 0
                versionAfter <- currentLiveUpdateVersion AdminInvitesScope { venueId = unpackId venue.id }
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

                versionBefore <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                            [ ("name", "Only Group")
                            , ("isActive", "false")
                            , ("showInactiveRosterGroups", "true")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"admin-roster-groups-fragment\""
                unchangedRosterGroup <- fetch rosterGroup.id
                unchangedRosterGroup.isActive `shouldBe` True
                versionAfter <- currentLiveUpdateVersion AdminRosterGroupsScope { venueId = unpackId venue.id }
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
                    callAction (MoveRosterGroupUpAction rosterGroup.id)
                moveGroupUpResponse `responseStatusShouldBe` status302

                rosterGroupResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateRosterGroupAction rosterGroup.id)
                        [ ("name", "Back of House Updated")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateShiftTypeAction shiftType.id)
                        [ ("name", "Kitchen Updated")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", idToParam overrideLevel.id)
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
                        [("rosterWeekStartsOn", "2")]

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
                        [ ("name", "Should Not Work")
                        , ("isActive", "false")
                        , ("overrideAwardLevelId", "")
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
                        [ ("name", "Back of House")
                        , ("isActive", "true")
                        ]
                rosterGroupResponse `responseStatusShouldBe` status302
                query @ShiftTypePayVersion |> fetch `shouldReturn` []

                _ <- createPayLevelRecordWithRates venue "Level 2" 31.50 3.15 6.30 1 1.25 1.50

                shiftTypeResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateShiftTypeAction
                        [ ("name", "Supervisor")
                        , ("isActive", "true")
                        , ("overrideAwardLevelId", "")
                        ]
                shiftTypeResponse `responseStatusShouldBe` status302
                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                (query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch >>= pure . map (.payrollLabel)) `shouldReturn` ["Supervisor"]

                versions <- query @ShiftTypePayVersion |> orderByDesc #createdAt |> fetch
                map (.createdByUserId) versions `shouldBe` [unpackId admin.id]

shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    case mapM markerPosition needles of
        Nothing -> expectationFailure ("Expected body to contain all markers in order: " ++ cs (show needles))
        Just positions -> positions `shouldSatisfy` ordered
    where
        markerPosition marker = List.findIndex (List.isPrefixOf marker) (List.tails haystack)
        ordered positions = positions == List.sort positions
