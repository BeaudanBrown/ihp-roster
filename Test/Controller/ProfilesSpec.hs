module Test.Controller.ProfilesSpec where

import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      currentLiveUpdateVersion)
import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection (..),
                                                 encodeShiftPreferenceKey)
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

        it "denies super-admin access to staff profile setup" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Profile Venue"
                superAdmin <- createUserRecordWithPlatformRole "profile-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status403

        it "does not let super-admin create a staff row through profile update" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Profile Update Venue"
                superAdmin <- createUserRecordWithPlatformRole "profile-update-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("firstName", "Support")
                        , ("lastName", "Admin")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Casey")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "3")
                        ]

                response `responseStatusShouldBe` status403
                staffExists <-
                    query @Staff
                        |> filterWhere (#venueId, unpackId venue.id)
                        |> filterWhere (#userId, Just (unpackId superAdmin.id))
                        |> fetchExists
                staffExists `shouldBe` False

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
                response `responseBodyShouldContain` "Profile Details"
                response `responseBodyShouldContain` "Leave Requests"
                response `responseBodyShouldContain` "id=\"profile-leave-requests-content\""
                response `responseBodyShouldContain` "id=\"profile-leave-request-form-fragment\""
                response `responseBodyShouldContain` "id=\"profile-leave-requests-list-fragment\""
                response `responseBodyShouldContain` "responseContext\" value=\"profile\""
                response `responseBodyShouldContain` "action=\"/CreateLeaveRequest?responseContext=profile&amp;section=leave\""
                response `responseBodyShouldContain` "hx-post=\"/CreateLeaveRequest?responseContext=profile&amp;section=leave\""
                response `responseBodyShouldContain` "hx-target=\"#profile-leave-request-form-fragment\""
                response `responseBodyShouldContain` "name=\"preferredName\""
                response `responseBodyShouldContain` "Emergency Contact Name"
                response `responseBodyShouldContain` "Ideal Shifts Per Week"
                response `responseBodyShouldContain` "Login email is read-only here for now."

        it "renders an empty profile onboarding form for a user with membership but no staff row yet" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Onboarding Venue"
                user <- createUserRecord "profile-onboarding@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Profile Details"
                response `responseBodyShouldContain` "name=\"firstName\""
                response `responseBodyShouldContain` "name=\"lastName\""
                response `responseBodyShouldContain` "name=\"phone\""
                response `responseBodyShouldContain` "name=\"emergencyContactName\""
                response `responseBodyShouldContain` "name=\"emergencyContactPhone\""

        it "hides the dedicated leave header link for workers while keeping profile leave content available" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-worker-header@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Taylor" "Worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/EditProfile\">profile</a>"
                response `responseBodyShouldContain` "href=\"/Timesheets\">timesheets</a>"
                response `responseBodyShouldContain` "id=\"profile-leave-requests-content\""
                response `responseBodyShouldNotContain` "href=\"/LeaveRequests\">leave</a>"

        it "shows the dedicated leave header link for managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-manager-header@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createStaffRecord venue (Just user) "Morgan" "Manager"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/LeaveRequests\">leave</a>"

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

        it "creates a linked staff row on the first successful profile submission" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Bootstrap Venue"
                user <- createUserRecord "profile-bootstrap@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("firstName", "Taylor")
                        , ("lastName", "Smith")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Casey Smith")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "3")
                        ]

                response `responseStatusShouldBe` status302

                staff <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#userId, Just (unpackId user.id)) |> fetchOne
                memberships <- query @VenueMembership |> filterWhere (#userId, unpackId user.id) |> fetch
                rosterGroups <- query @StaffRosterGroup |> filterWhere (#staffId, unpackId staff.id) |> fetch
                refreshedUser <- fetch user.id

                staff.firstName `shouldBe` "Taylor"
                staff.lastName `shouldBe` "Smith"
                staff.phone `shouldBe` "0400000000"
                length memberships `shouldBe` 1
                length rosterGroups `shouldBe` 1
                refreshedUser.isProfileCompleted `shouldBe` True

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
