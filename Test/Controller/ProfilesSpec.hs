module Test.Controller.ProfilesSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole))
import Application.Helper.LiveUpdate
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection (..),
                                                 encodeShiftPreferenceKey,
                                                 shiftPreferenceEndHourParamName,
                                                 shiftPreferenceStartHourParamName)
import Application.Helper.SurfaceResource
import Config
import qualified Data.Set as Set
import qualified Data.Text as Text
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
import Web.FrontController ()
import Web.Profiles.Mutations (fetchProfileRosterInvalidationTargets,
                               fetchProfileRosterInvalidationTargetsForScopes,
                               profileUpdateTouchedResources)
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

        it "redirects unauthenticated users away from profile leave fragments" $ withContext do
            response <- callAction ShowProfileleaveRequestsContentLiveFragmentAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users away from profile content fragments" $ withContext do
            response <- callAction ShowprofileContentLiveFragmentAction
            response `responseStatusShouldBe` status302

        it "denies super-admin access to staff profile setup" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Profile Venue"
                superAdmin <- createUserRecordWithPlatformRole "profile-super-admin@example.com" "staff" (Just SuperAdminRole) True

                response <- withUserAndCurrentVenue superAdmin venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Support"

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

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldBe` Just "http://localhost/Support"
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
                staff <- createStaffRecord venue (Just user) "Taylor" "Smith"
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #weekdayIndex 2
                        |> set #preferredStartHour 6
                        |> set #preferredEndHour 17
                        |> createRecord

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "hx-post=\"/UpdateProfile\""
                response `responseBodyShouldContain` "hx-target=\"#profile-details\""
                response `responseBodyShouldContain` "hx-target=\"#profile-preferences\""
                response `responseBodyShouldContain` "hx-swap=\"outerHTML show:none\""
                response `responseBodyShouldContain` "Profile Details"
                response `responseBodyShouldContain` "Unavailability"
                response `responseBodyShouldContain` "id=\"profile-live-surface\""
                response `responseBodyShouldContain` "data-bepis-surface=\"profile\""
                response `responseBodyShouldContain` "profile-details-section"
                response `responseBodyShouldContain` "profile-preferences-section"
                response `responseBodyShouldContain` "ShowprofileContentLiveFragment"
                response `responseBodyShouldContain` "profile-details-form"
                response `responseBodyShouldContain` "profile:"
                response `responseBodyShouldContain` "id=\"profile-leave-requests-content\""
                response `responseBodyShouldNotContain` "data-live-update-surface=\""
                response `responseBodyShouldContain` "profile-leave-requests-content"
                response `responseBodyShouldContain` "id=\"profile-leave-request-form-fragment\""
                response `responseBodyShouldContain` "id=\"profile-leave-requests-list-fragment\""
                response `responseBodyShouldContain` "responseContext\" value=\"profile\""
                response `responseBodyShouldContain` "action=\"/CreateLeaveRequest?responseContext=profile&amp;section=leave\""
                response `responseBodyShouldContain` "hx-post=\"/CreateLeaveRequest?responseContext=profile&amp;section=leave\""
                response `responseBodyShouldContain` "hx-target=\"#profile-leave-request-form-fragment\""
                response `responseBodyShouldContain` "name=\"preferredName\""
                response `responseBodyShouldContain` "Emergency Contact Name"
                response `responseBodyShouldContain` "Ideal # Shifts"
                response `responseBodyShouldContain` "id=\"idealShiftsPerWeek\""
                response `responseBodyShouldContain` "<option value=\"0\""
                response `responseBodyShouldContain` "<option value=\"7\""
                response `responseBodyShouldContain` "Available"
                response `responseBodyShouldContain` "<th scope=\"col\" class=\"shift-preference-table__available\">Available</th>"
                response `responseBodyShouldNotContain` "<th scope=\"col\" class=\"shift-preference-table__start-time\">Start time</th>"
                response `responseBodyShouldContain` "style=\"--preference-start: 5.556%; --preference-end: 66.667%;\""
                response `responseBodyShouldContain` "class=\"shift-preference-window is-unavailable\""
                response `responseBodyShouldContain` ">Mon<"
                response `responseBodyShouldContain` "shift-preference-availability-button"
                response `responseBodyShouldContain` "timesheet-approval-toggle"
                response `responseBodyShouldContain` "btn-outline-success"
                response `responseBodyShouldContain` "app-toggle-button"
                response `responseBodyShouldContain` "aria-pressed=\"false\""
                response `responseBodyShouldContain` "class=\"visually-hidden app-toggle-button-input\" type=\"checkbox\""
                response `responseBodyShouldNotContain` "<th scope=\"col\">Day</th>"
                response `responseBodyShouldNotContain` "table-responsive"
                response `responseBodyShouldNotContain` "Tick available days and choose the preferred shift start window"
                response `responseBodyShouldNotContain` "Login email is read-only here for now."

                fragmentResponse <- withUserAndCurrentVenue user venue.id do
                    callAction ShowProfileleaveRequestsContentLiveFragmentAction
                fragmentResponse `responseStatusShouldBe` status200
                fragmentResponse `responseBodyShouldContain` "id=\"profile-leave-requests-content\""
                fragmentResponse `responseBodyShouldNotContain` "data-live-update-surface=\""
                fragmentResponse `responseBodyShouldNotContain` "id=\"app\""

                profileFragmentResponse <- withUserAndCurrentVenue user venue.id do
                    callAction ShowprofileContentLiveFragmentAction
                profileFragmentResponse `responseStatusShouldBe` status200
                profileFragmentResponse `responseBodyShouldContain` "id=\"profile-details\""
                profileFragmentResponse `responseBodyShouldContain` "id=\"profile-details-form\""
                profileFragmentResponse `responseBodyShouldNotContain` "id=\"profile-live-surface\""
                profileFragmentResponse `responseBodyShouldNotContain` "id=\"app\""

        it "keeps profile accordions closed by default and opens explicit sections" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Accordion Venue"
                user <- createUserRecord "profile-accordion@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Taylor" "Accordion"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"profile-details-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"profile-security-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"profile-leave-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"profile-rsa-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldNotContain` "accordion-collapse collapse show"

                securityResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                securityResponse `responseStatusShouldBe` status200
                securityResponse `responseBodyShouldContain` "id=\"profile-security-collapse\" class=\"accordion-collapse collapse show\""

        it "renders profile RSA without a duplicate inner RSA heading" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile RSA Chrome Venue"
                user <- createUserRecord "profile-rsa-chrome@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Riley" "RSA"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "rsa")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Upload and scan PDF"
                response `responseBodyShouldNotContain` "Upload a Responsible Service of Alcohol statement of attainment."
                response `responseBodyShouldNotContain` "<h5 class=\"mb-1\">RSA</h5>"

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
                response `responseBodyShouldContain` "name=\"idealShiftsPerWeek\""
                response `responseBodyShouldContain` "name=\"shiftPreferenceKeys\""

        it "hides the dedicated leave header link for workers while keeping profile leave content available" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-worker-header@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createStaffRecord venue (Just user) "Taylor" "Worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/EditProfile\""
                response `responseBodyShouldContain` "<span>profile</span>"
                response `responseBodyShouldContain` "href=\"/Timesheets\""
                response `responseBodyShouldContain` "<span>timesheets</span>"
                response `responseBodyShouldContain` "id=\"profile-leave-requests-content\""
                response `responseBodyShouldNotContain` "href=\"/LeaveRequests\""

        it "shows the dedicated unavailability header link for managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-manager-header@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "manager"
                _ <- createStaffRecord venue (Just user) "Morgan" "Manager"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction EditProfileAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "href=\"/LeaveRequests\""
                response `responseBodyShouldContain` "<span>unavailability</span>"

        it "saves submitted shift preferences from the preferences form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-preferences@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Taylor" "Smith"
                let preferenceKey =
                        encodeShiftPreferenceKey 1

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("section", "preferences")
                        , ("shiftPreferenceKeys", cs preferenceKey)
                        , (cs (shiftPreferenceStartHourParamName preferenceKey), "12")
                        , (cs (shiftPreferenceEndHourParamName preferenceKey), "20")
                        ]

                response `responseStatusShouldBe` status302

                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetch
                map (.weekdayIndex) preferences `shouldBe` [1]
                map (.preferredStartHour) preferences `shouldBe` [12]
                map (.preferredEndHour) preferences `shouldBe` [20]

        it "records touched resources for profile updates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Touched Venue"
                user <- createUserRecord "profile-touched@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Taylor" "Touched"

                Set.fromList (profileUpdateTouchedResources staff)
                    `shouldBe` Set.fromList
                        [ staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)
                        ]

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

        it "saves shift preferences after profile creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Bootstrap Preferences Venue"
                user <- createUserRecord "profile-bootstrap-preferences@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"
                let preferenceKey = encodeShiftPreferenceKey 2

                profileResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("firstName", "Taylor")
                        , ("lastName", "Smith")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Casey Smith")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        ]

                profileResponse `responseStatusShouldBe` status302

                staff <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#userId, Just (unpackId user.id)) |> fetchOne

                preferencesResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UpdateProfileAction
                        [ ("section", "preferences")
                        , ("shiftPreferenceKeys", cs preferenceKey)
                        , (cs (shiftPreferenceStartHourParamName preferenceKey), "8")
                        , (cs (shiftPreferenceEndHourParamName preferenceKey), "14")
                        ]

                preferencesResponse `responseStatusShouldBe` status302

                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetch

                map (.weekdayIndex) preferences `shouldBe` [2]
                map (.preferredStartHour) preferences `shouldBe` [8]
                map (.preferredEndHour) preferences `shouldBe` [14]

        it "normalizes profile text and rejects oversized names before saving" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Validation Venue"
                user <- createUserRecord "profile-validation@example.com" "staff" False
                _ <- createVenueMembershipRecord venue user "worker"
                let oversizedName = Text.replicate 81 "A"

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams UpdateProfileAction
                            [ ("firstName", cs oversizedName)
                            , ("lastName", "  Smith  ")
                            , ("preferredName", "   ")
                            , ("phone", "  0400000000  ")
                            , ("emergencyContactName", "Casey Smith")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "3")
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "is longer than 80 characters"
                staffExists <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> fetchExists
                staffExists `shouldBe` False

        it "returns an HTMX profile fragment update instead of redirecting" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Profile Venue"
                user <- createUserRecord "profile-htmx@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                staff <- createStaffRecord venue (Just user) "Taylor" "Smith"
                profileVersionBefore <- currentLiveUpdateVersion (profileLiveScope (unpackId venue.id) (unpackId staff.id))

                response <- withUserAndCurrentVenue user venue.id do
                    withRequestHeaders [("HX-Request", "true"), ("X-Live-Update-Client-Id", "profile-htmx-client")] do
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
                response `responseBodyShouldContain` "id=\"profile-details\""
                response `responseBodyShouldContain` "Profile updated"
                response `responseBodyShouldContain` "hx-swap-oob=\"innerHTML\""
                profileVersionAfter <- currentLiveUpdateVersion (profileLiveScope (unpackId venue.id) (unpackId staff.id))
                profileVersionAfter `shouldBe` profileVersionBefore

        it "selects profile roster invalidation targets from active roster week scopes" $ withContext do
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
                invalidationTargets `shouldBe` []

                activeInvalidationTargets <-
                    fetchProfileRosterInvalidationTargetsForScopes
                        venue.id
                        staff
                        [ (unpackId venue.id, unpackId frontGroup.id, 0)
                        , (unpackId venue.id, unpackId backGroup.id, 0)
                        ]

                let frontEntry = find (\(rosterGroupId, weekOffset, _) -> rosterGroupId == frontGroup.id && weekOffset == 0) activeInvalidationTargets
                let backEntry = find (\(rosterGroupId, weekOffset, _) -> rosterGroupId == backGroup.id && weekOffset == 0) activeInvalidationTargets

                fmap (\(_, _, rowKeys) -> rowKeys) frontEntry `shouldBe` Just [(unpackId frontDay.id, assignedSlot.rowIndex)]
                backEntry `shouldBe` Nothing

                frontVersionBefore <- currentLiveUpdateVersion (rosterWeekLiveScope (unpackId venue.id) (unpackId frontGroup.id) 0)
                backVersionBefore <- currentLiveUpdateVersion (rosterWeekLiveScope (unpackId venue.id) (unpackId backGroup.id) 0)
                profileVersionBefore <- currentLiveUpdateVersion (profileLiveScope (unpackId venue.id) (unpackId staff.id))

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
                frontVersionAfter <- currentLiveUpdateVersion (rosterWeekLiveScope (unpackId venue.id) (unpackId frontGroup.id) 0)
                backVersionAfter <- currentLiveUpdateVersion (rosterWeekLiveScope (unpackId venue.id) (unpackId backGroup.id) 0)
                profileVersionAfter <- currentLiveUpdateVersion (profileLiveScope (unpackId venue.id) (unpackId staff.id))

                frontVersionAfter `shouldBe` frontVersionBefore
                backVersionAfter `shouldBe` backVersionBefore
                profileVersionAfter `shouldBe` profileVersionBefore
