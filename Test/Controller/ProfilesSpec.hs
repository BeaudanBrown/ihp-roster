module Test.Controller.ProfilesSpec where

import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.StaffShiftPreferences (encodeShiftPreferenceKey,
                                                 ShiftPreferenceSelection (..))
import Config
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
import Web.Controller.Profiles (fetchProfileRosterInvalidationTargets)
import Web.Controller.Profiles ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "ProfilesController" do
        it "redirects unauthenticated users away from edit profile" $ withContext do
            response <- callAction EditProfileAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users away from update profile" $ withContext do
            response <- callActionWithParams UpdateProfileAction
                [ ("firstName", "Taylor")
                , ("lastName", "Smith")
                , ("phone", "0400000000")
                , ("emergencyContactName", "Casey Smith")
                , ("emergencyContactPhone", "0411111111")
                , ("idealShiftsPerWeek", "3")
                ]
            response `responseStatusShouldBe` status302

        it "renders the profile form with in-place HTMX submission" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-native-submit@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Taylor" "Smith"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "hx-post=\"/UpdateProfile\""
                response `responseBodyShouldContain` "hx-target=\"#profile-content-fragment\""
                response `responseBodyShouldContain` "name=\"preferredName\""
                response `responseBodyShouldContain` "Emergency Contact Name"
                response `responseBodyShouldContain` "Ideal Shifts Per Week"
                response `responseBodyShouldContain` "Login email is read-only here for now."

        it "saves submitted shift preferences from the profile form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-preferences@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Taylor" "Smith"
                rosterGroup <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                _ <- createStaffRosterGroupRecord staff rosterGroup
                slotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
                let preferenceKey =
                        encodeShiftPreferenceKey
                            ShiftPreferenceSelection
                                { rosterGroupId = rosterGroup.id
                                , weekdayIndex = 1
                                , slotNameId = slotName.id
                                }

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("firstName", "Taylor")
                        , ("lastName", "Smith")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Casey Smith")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "3")
                        , ("shiftPreferenceKeys", cs preferenceKey)
                        ]

                response `responseStatusShouldBe` status302

                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetch
                map (.rosterGroupId) preferences `shouldBe` [unpackId rosterGroup.id]
                map (.slotNameId) preferences `shouldBe` [unpackId slotName.id]
                map (.weekdayIndex) preferences `shouldBe` [1]

        it "returns an HTMX profile fragment update instead of redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Taylor" "Smith"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateProfileAction
                            [ ("firstName", "Taylor")
                            , ("lastName", "Smith")
                            , ("preferredName", "Tay")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Casey Smith")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "3")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"profile-content-fragment\""
                response `responseBodyShouldContain` "Profile updated"
                response `responseBodyShouldContain` "hx-swap-oob=\"innerHTML\""

        it "invalidates only impacted roster week scopes and includes the assigned row fragment for profile updates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-roster-invalidation@example.com" "staff" True
                manager <- createUserRecord "profile-roster-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just user) "Taylor" "Smith"
                frontGroup <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 2 False
                _ <- createStaffRosterGroupRecord staff frontGroup
                frontSlotName <- fetchSlotNameRecordForRosterGroup frontGroup "Early"
                frontWeek <- createRosterWeekRecordForRosterGroup venue frontGroup 0 False
                backWeek <- createRosterWeekRecordForRosterGroup venue backGroup 0 False
                frontDay <- createRosterDayRecord frontWeek 0
                _ <- createRosterDayRecord backWeek 0
                assignedSlot <- createRosterSlotRecord frontDay frontSlotName (Just staff) 0

                invalidationTargets <- fetchProfileRosterInvalidationTargets venue.id staff

                let frontEntry = find (\(rosterGroupId, weekOffset, _) -> rosterGroupId == frontGroup.id && weekOffset == 0) invalidationTargets
                let backEntry = find (\(rosterGroupId, weekOffset, _) -> rosterGroupId == backGroup.id && weekOffset == 0) invalidationTargets

                fmap (\(_, _, rowKeys) -> rowKeys) frontEntry `shouldBe` Just [(unpackId frontDay.id, assignedSlot.rowIndex)]
                backEntry `shouldBe` Nothing

                frontVersionBefore <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId frontGroup.id, weekOffset = 0 }
                backVersionBefore <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId backGroup.id, weekOffset = 0 }

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "profile-update-client")] do
                        callActionWithParams UpdateProfileAction
                            [ ("firstName", "Taylor")
                            , ("lastName", "Updated")
                            , ("preferredName", "")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Casey Smith")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "4")
                            ]

                response `responseStatusShouldBe` status200
                frontVersionAfter <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId frontGroup.id, weekOffset = 0 }
                backVersionAfter <- currentLiveUpdateVersion RosterWeekScope { venueId = unpackId venue.id, rosterGroupId = unpackId backGroup.id, weekOffset = 0 }

                frontVersionAfter `shouldBe` (frontVersionBefore + 1)
                backVersionAfter `shouldBe` backVersionBefore
