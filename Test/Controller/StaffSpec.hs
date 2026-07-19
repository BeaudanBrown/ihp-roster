module Test.Controller.StaffSpec where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekResource)
import qualified Application.Helper.LiveUpdate as LiveUpdate
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.Helper.StaffShiftPreferences (encodeShiftPreferenceKey,
                                                 shiftPreferenceEndHourParamName,
                                                 shiftPreferenceStartHourParamName)
import Application.Helper.SurfaceResource
import Application.InvitationDelivery.Job (venueInvitationDeliveryJobKind)
import Config
import qualified Data.List as List
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
import Web.Controller.Staff ()
import Web.FrontController ()
import Web.Routes
import Web.Staff.Mutations (staffCreateTouchedResources,
                            staffRosterGroupResources,
                            staffUpdateTouchedResources)
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "StaffController" do
        let sampleStaffId = Id "6f9638dc-f13c-4ed3-b4f1-a2f860532cab"
        it "redirects unauthenticated users from edit staff form" $ withContext do
            response <- callActionWithParams (EditStaffAction sampleStaffId) [("weekOffset", "7")]
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from update staff" $ withContext do
            response <- callActionWithParams (UpdateStaffAction sampleStaffId)
                [ ("section", "profile")
                , ("firstName", "Test")
                , ("lastName", "User")
                , ("preferredName", "")
                , ("phone", "0400000000")
                , ("emergencyContactName", "Casey User")
                , ("emergencyContactPhone", "0411111111")
                , ("idealShiftsPerWeek", "3")
                , ("weekOffset", "7")
                ]
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from new trial staff form" $ withContext do
            response <- callAction NewStaffAction
            response `responseStatusShouldBe` status302

        it "labels the trial staff dialog as add trial" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Dialog Venue"
                manager <- createUserRecord "trial-staff-dialog-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction NewStaffAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Add Trial"
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "lets managers create active casual trial staff placeholders with selected roster groups" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Venue"
                manager <- createUserRecord "trial-staff-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Trial")
                        , ("lastName", "Placeholder")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "2")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow frontOfHouse.id))
                        , ("rosterGroupIds", cs (tshow backOfHouse.id))
                        ]

                response `responseStatusShouldBe` status302
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#firstName, "Trial" :: Text)
                    |> filterWhere (#lastName, "Placeholder" :: Text)
                    |> fetchOne
                staff.userId `shouldBe` Nothing
                staff.isActive `shouldBe` True
                staff.employmentBasis `shouldBe` Casual
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                sort (map (.rosterGroupId) assignments) `shouldBe` sort [unpackId frontOfHouse.id, unpackId backOfHouse.id]

        it "prevents non-managers from creating trial staff placeholders" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Worker Venue"
                worker <- createUserRecord "trial-staff-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker "worker"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue worker venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Blocked")
                        , ("lastName", "Trial")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "1")
                        , ("isActive", "on")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                exists <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#firstName, "Blocked" :: Text) |> fetchExists
                exists `shouldBe` False

        it "rejects cross-venue roster group ids when creating trial staff placeholders" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Staff Current Venue"
                otherVenue <- createVenueWithConfig "Trial Staff Other Venue"
                manager <- createUserRecord "trial-staff-cross-venue-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                otherGroup <- createVenueRosterGroupWithDefaults otherVenue "Other Venue Group" 1 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        CreateStaffAction
                        [ ("firstName", "Cross")
                        , ("lastName", "Venue")
                        , ("phone", "Trial placeholder")
                        , ("emergencyContactName", "Trial placeholder")
                        , ("emergencyContactPhone", "Trial placeholder")
                        , ("idealShiftsPerWeek", "1")
                        , ("isActive", "on")
                        , ("rosterGroupIds", cs (tshow otherGroup.id))
                        ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Choose roster groups from the current venue."
                exists <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#firstName, "Cross" :: Text) |> fetchExists
                exists `shouldBe` False

        it "records touched resources for trial staff creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Create Touched Venue"
                staff <- createStaffRecord venue Nothing "Trace" "Trial"

                Set.fromList (staffCreateTouchedResources staff)
                    `shouldBe` Set.fromList
                        [ staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)

                        ]

        it "records touched resources for staff updates" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Touched Venue"
                staff <- createStaffRecord venue Nothing "Sam" "Touched"

                Set.fromList (staffUpdateTouchedResources staff)
                    `shouldBe` Set.fromList
                        [ staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)
                        ]

        it "touches active roster weeks for every previous and newly selected staff group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Group Resource Venue"
                previousGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                selectedGroup <- createVenueRosterGroupWithDefaults venue "Selected Group" 1 False
                otherVenue <- createVenueWithConfig "Other Staff Group Resource Venue"
                otherGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId otherVenue.id) |> filterWhere (#isDefault, True) |> fetchOne
                let activeScopes =
                        [ (unpackId venue.id, unpackId previousGroup.id, 0)
                        , (unpackId venue.id, unpackId selectedGroup.id, 1)
                        , (unpackId otherVenue.id, unpackId otherGroup.id, 0)
                        ]

                let resources = staffRosterGroupResources (unpackId venue.id) activeScopes [previousGroup.id, selectedGroup.id]

                Set.fromList resources
                    `shouldBe` Set.fromList
                        [ rosterWeekResource (unpackId previousGroup.id) 0
                        , rosterWeekResource (unpackId selectedGroup.id) 1
                        ]

        it "invalidates roster content and staff list resources for HTMX roster-launched staff edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-modal-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-modal-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                _ <- createVenueMembershipRecord venue linkedUser "worker"
                _ <- createRosterWeekRecord venue 0 False
                staff <- createStaffRecord venue (Just linkedUser) "Alpha" "Crew"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateStaffAction staff.id)
                            [ ("section", "profile")
                            , ("firstName", "Updated")
                            , ("lastName", "Crew")
                            , ("preferredName", "")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Morgan Crew")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "4")
                            , ("isActive", "on")
                            , ("weekOffset", "0")
                            , ("rosterGroupIds", cs (tshow rosterGroup.id))
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                response `responseBodyShouldContain` "Staff member updated"
                response `responseBodyShouldContain` "id=\"toast-overlay-mount\""
                response `responseBodyShouldNotContain` "id=\"roster-content\""
                let triggerHeader = cs <$> lookup "HX-Trigger" (responseHeaders response)
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "bepis:live-fragments-refresh")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-content\"")
                triggerHeader `shouldSatisfy` maybe False (Text.isInfixOf "\"kind\":\"roster-staff-panel\"")

        it "hides trial staff invitation email from the staff details form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Field Venue"
                manager <- createUserRecord "staff-trial-invite-field-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Trial" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "name=\"invitationEmail\""
                response `responseBodyShouldNotContain` "Send an invite link to claim this trial staff profile."

        it "keeps pending trial invites out of the staff details form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Pending Invite Field Venue"
                manager <- createUserRecord "staff-pending-invite-field-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Pending" "Invite"
                _ <- createVenueInvitationRecord venue (Just manager) "pending-trial-invite@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldNotContain` "Pending invite"
                response `responseBodyShouldNotContain` "pending-trial-invite@example.com"
                response `responseBodyShouldNotContain` "name=\"invitationEmail\""

        it "opens the dedicated invitation dialog for adoptable trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Dialog Venue"
                manager <- createUserRecord "staff-trial-invite-dialog-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Trial" "Dialog"
                _ <- createVenueInvitationRecord venue (Just manager) "pending-dialog@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (NewTrialStaffInvitationAction staff.id)
                            [ ("weekOffset", "3")
                            , ("rosterGroupId", cs (tshow rosterGroup.id))
                            ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite trial staff"
                response `responseBodyShouldNotContain` "app-staff-edit-dialog"
                response `responseBodyShouldContain` "id=\"trial-staff-invite-form\""
                response `responseBodyShouldContain` "pending-dialog@example.com"
                response `responseBodyShouldContain` "name=\"weekOffset\" value=\"3\""

        it "rejects opening the invitation dialog for linked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Linked Invite Dialog Venue"
                manager <- createUserRecord "staff-linked-invite-dialog-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-linked-invite-dialog-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just linkedUser) "Linked" "Dialog"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (NewTrialStaffInvitationAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Only active trial staff without a linked login can be invited."
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\""
                response `responseBodyShouldNotContain` "id=\"trial-staff-invite-form\""

        it "keeps invalid invitation emails in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Invalid Trial Invite Venue"
                manager <- createUserRecord "staff-invalid-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Invalid" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", "not-an-email")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite trial staff"
                response `responseBodyShouldContain` "Enter a valid email address."
                response `responseBodyShouldContain` "value=\"not-an-email\""
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "requires an invitation email in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Missing Trial Invite Email Venue"
                manager <- createUserRecord "staff-missing-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Missing" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (CreateTrialStaffInvitationAction staff.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invite email is required."
                response `responseBodyShouldContain` "id=\"trial-staff-invite-form\""
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "rejects oversized invitation emails in the dedicated dialog" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Oversized Trial Invite Email Venue"
                manager <- createUserRecord "staff-oversized-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Oversized" "Invite"
                let oversizedEmail = Text.replicate 250 "a" <> "@example.com"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", cs oversizedEmail)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Email must be 254 characters or fewer."
                response `responseBodyShouldContain` cs oversizedEmail
                response `responseBodyShouldNotContain` "Edit Staff Member"

        it "lets managers create worker adoption invitations for current-venue trial staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Trial Invite Venue"
                manager <- createUserRecord "staff-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Trial" "Invite"
                versionBefore <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (CreateTrialStaffInvitationAction staff.id)
                            [("invitationEmail", "trial-invite-claim@example.com")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation sent to trial-invite-claim@example.com"
                response `responseBodyShouldContain` "id=\"toast-overlay-mount\""
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldNotContain` "Edit Staff Member"
                invitation <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "trial-invite-claim@example.com" :: Text)
                    |> fetchOne
                invitation.staffId `shouldBe` Just staff.id
                inputValue invitation.inviteRole `shouldBe` "worker"
                inputValue invitation.status `shouldBe` "pending"
                appJob <- query @AppJob
                    |> filterWhere (#relatedTable, Just ("venue_invitations" :: Text))
                    |> filterWhere (#relatedId, Just (unpackId invitation.id))
                    |> fetchOne
                appJob.jobKind `shouldBe` venueInvitationDeliveryJobKind
                versionAfter <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "closes the dedicated dialog after resending a trial staff invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Resend Trial Invite Venue"
                manager <- createUserRecord "staff-resend-trial-invite-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Resend" "Invite"
                invitation <- createVenueInvitationRecord venue (Just manager) "resend-trial-invite@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callAction (ResendTrialStaffInvitationAction invitation.id)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation resent to resend-trial-invite@example.com"
                response `responseBodyShouldContain` "id=\"dialog-overlay-mount\" hx-swap-oob=\"innerHTML\""
                response `responseBodyShouldNotContain` "Invite trial staff"

        it "prevents non-managers from creating trial staff adoption invitations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Worker Invite Venue"
                worker <- createUserRecord "staff-worker-invite-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker "worker"
                staff <- createStaffRecord venue Nothing "Worker" "Invite"

                response <- withUserAndCurrentVenue worker venue.id do
                    callActionWithParams
                        (CreateTrialStaffInvitationAction staff.id)
                        [("invitationEmail", "worker-invite-claim@example.com")]

                response `responseStatusShouldBe` status302
                exists <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "worker-invite-claim@example.com" :: Text)
                    |> fetchExists
                exists `shouldBe` False

        it "rejects adoption invitations for linked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Linked Invite Venue"
                manager <- createUserRecord "staff-linked-invite-manager@example.com" "staff" True
                linkedUser <- createUserRecord "staff-linked-invite-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue (Just linkedUser) "Linked" "Invite"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (CreateTrialStaffInvitationAction staff.id)
                        [("invitationEmail", "linked-invite-claim@example.com")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Only active trial staff without a linked login can be invited."
                exists <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#email, "linked-invite-claim@example.com" :: Text)
                    |> fetchExists
                exists `shouldBe` False

        it "renders shift preferences in a dedicated staff edit accordion section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Preferences Accordion Venue"
                manager <- createUserRecord "staff-preferences-accordion-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "data-bepis-surface=\"staff\""
                response `responseBodyShouldContain` "data-bepis-surface-config="
                response `responseBodyShouldContain` "data-bepis-surface-action=\"update-staff-profile\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"update-staff-shift-preferences\""
                response `responseBodyShouldContain` "data-bepis-surface-action=\"create-staff-leave-request\""
                response `responseBodyShouldContain` "id=\"staff-profile-details-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"staff-profile-preferences-collapse\" class=\"accordion-collapse collapse\""
                response `responseBodyShouldContain` "id=\"staff-shift-preferences-form\""
                response `responseBodyShouldContain` "<span class=\"fw-semibold\">Shift Preferences</span>"

        it "updates explicit roster-group applicability from the staff edit form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-group-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                frontOfHouse <- createVenueRosterGroupWithDefaults venue "Front of House" 1 True
                backOfHouse <- createVenueRosterGroupWithDefaults venue "Back of House" 2 True
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow frontOfHouse.id))
                        , ("rosterGroupIds", cs (tshow backOfHouse.id))
                        ]

                response `responseStatusShouldBe` status302
                assignments <- query @StaffRosterGroup
                    |> filterWhere (#staffId, unpackId staff.id)
                    |> filterWhere (#deletedAt, Nothing)
                    |> fetch
                sort (map (.rosterGroupId) assignments) `shouldBe` sort [unpackId frontOfHouse.id, unpackId backOfHouse.id]

        it "keeps existing shift preferences when saving staff profile details" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Preserve Preferences Venue"
                manager <- createUserRecord "staff-preserve-preferences-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <-
                    newRecord @StaffShiftPreference
                        |> set #venueId (unpackId venue.id)
                        |> set #staffId (unpackId staff.id)
                        |> set #weekdayIndex 1
                        |> set #preferredStartHour 9
                        |> set #preferredEndHour 17
                        |> createRecord

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> filterWhere (#deletedAt, Nothing) |> fetch
                map (.weekdayIndex) preferences `shouldBe` [1]
                map (.preferredStartHour) preferences `shouldBe` [9]
                map (.preferredEndHour) preferences `shouldBe` [17]

        it "saves staff shift preferences from the dedicated preferences form" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Dedicated Preferences Venue"
                manager <- createUserRecord "staff-dedicated-preferences-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                let preferenceKey = encodeShiftPreferenceKey 2

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "preferences")
                        , ("weekOffset", "0")
                        , ("shiftPreferenceKeys", cs preferenceKey)
                        , (cs (shiftPreferenceStartHourParamName preferenceKey), "8")
                        , (cs (shiftPreferenceEndHourParamName preferenceKey), "14")
                        ]

                response `responseStatusShouldBe` status302
                preferences <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> filterWhere (#deletedAt, Nothing) |> fetch
                map (.weekdayIndex) preferences `shouldBe` [2]
                map (.preferredStartHour) preferences `shouldBe` [8]
                map (.preferredEndHour) preferences `shouldBe` [14]

        it "rejects malformed roster group ids and shift preference keys without throwing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-malformed-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams
                            (UpdateStaffAction staff.id)
                            [ ("section", "profile")
                            , ("firstName", "Alpha")
                            , ("lastName", "Crew")
                            , ("preferredName", "")
                            , ("phone", "0400000000")
                            , ("emergencyContactName", "Jordan Crew")
                            , ("emergencyContactPhone", "0411111111")
                            , ("idealShiftsPerWeek", "4")
                            , ("isActive", "on")
                            , ("weekOffset", "0")
                            , ("rosterGroupIds", "not-a-uuid")
                            , ("shiftPreferenceKeys", "bad|key|not-a-uuid")
                            ]

                response `responseStatusShouldBe` status200
                preferenceExists <- query @StaffShiftPreference |> filterWhere (#staffId, unpackId staff.id) |> fetchExists
                preferenceExists `shouldBe` False

        it "allows venue admins to update staff employment basis and default pay level" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "staff-pay-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                payLevel <- createPayLevelRecord venue "Level 2"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                xeroVersionBefore <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                response <- withPasskeyVerifiedUserAndCurrentVenue admin (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("award:" <> tshow payLevel.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.employmentBasis `shouldBe` Permanent
                updatedStaff.defaultAwardLevelId `shouldBe` Just payLevel.id
                xeroVersionAfter <- LiveUpdate.currentLiveUpdateVersion (AdminLive.adminXeroLiveScope (unpackId venue.id))
                xeroVersionAfter `shouldBe` xeroVersionBefore

        it "shows synced award level hourly rates in the staff pay selector" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                admin <- createUserRecord "staff-pay-options-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                _ <- createPayLevelRecordWithRates venue "Level 3" 32.75 3.25 6.50 1 1.25 1.50
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin (get #id venue) do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldContain` "Award rates"
                response `responseBodyShouldContain` "Level 3 (perm $32.75/hr)"
                response `responseBodyShouldContain` "Not assigned"

        it "explains why venue roles are unavailable for unlinked staff" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Unlinked Staff Role Venue"
                admin <- createUserRecord "unlinked-staff-role-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                staff <- createStaffRecord venue Nothing "Trial" "Role"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff Role"
                response `responseBodyShouldContain` "can be assigned after this staff profile is linked to a user account"
                response `responseBodyShouldNotContain` "<select name=\"venueRole\""

        it "lets venue admins view and update a linked staff member venue role" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Role Venue"
                admin <- createUserRecord "staff-role-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                workerUser <- createUserRecord "staff-role-worker@example.com" "staff" True
                membership <- createVenueMembershipRecord venue workerUser "worker"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                staff <- createStaffRecord venue (Just workerUser) "Role" "Target"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff Role"
                response `responseBodyShouldContain` "<select name=\"venueRole\""
                response `responseBodyShouldContain` "<option value=\"worker\" selected"
                response `responseBodyShouldContain` "<option value=\"supervisor\""

                updateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Role")
                        , ("lastName", "Target")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "casual")
                        , ("payRateSelection", "")
                        , ("venueRole", "manager")
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                updateResponse `responseStatusShouldBe` status302
                updatedMembership <- fetch membership.id
                inputValue updatedMembership.venueRole `shouldBe` ("manager" :: Text)
                auditEvent <- query @AuditEvent |> filterWhere (#targetId, unpackId membership.id) |> fetchOne
                auditEvent.eventType `shouldBe` "venue_role_changed"

        it "shows active imported Xero pay items in the staff pay override dropdown" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Imported Pay Item Venue"
                admin <- createUserRecord "staff-imported-pay-items-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                _ <- createPayLevelRecordWithRates venue "Level Staff" 45.00 4.50 9.00 1 1.25 1.50
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Imported Staff Rate" "imported-staff-rate" 55.25

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldContain` (cs ("<option value=\"xero:" <> inputValue importedPayItem.id <> "\""))
                response `responseBodyShouldContain` "Xero imported rates"
                response `responseBodyShouldContain` "Imported Staff Rate"
                response `responseBodyShouldContain` "55.25/hr"
                responseBodyText <- responseBody response
                (cs responseBodyText :: String) `shouldContainInOrder` ["Award rates", "Level Staff", "Xero imported rates", "Imported Staff Rate"]

                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                updateResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("xero:" <> tshow importedPayItem.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]
                updateResponse `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.defaultAwardLevelId `shouldBe` Nothing
                updatedStaff.importedXeroPayItemId `shouldBe` Just importedPayItem.id

        it "hides archived imported Xero pay items from the staff pay override dropdown" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Archived Imported Pay Item Venue"
                admin <- createUserRecord "staff-archived-imported-pay-items-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"
                importedPayItem <- createImportedXeroPayItemRecord venue admin "Archived Staff Rate" "archived-staff-rate" 55.25
                now <- getCurrentTime
                _ <- importedPayItem
                    |> set #archivedAt (Just now)
                    |> set #archivedByUserId (Just (unpackId admin.id))
                    |> set #archiveReason (Just ("Test archive" :: Text))
                    |> updateRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Default Pay Rate"
                response `responseBodyShouldNotContain` "Archived Staff Rate"

        it "renders staff login access and temporarily hides RSA upload in the staff edit modal" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Staff Access Modal Venue"
                owner <- createUserRecord "staff-access-owner@example.com" "admin" True
                worker <- createUserRecord "staff-access-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueMembershipRecord venue worker "worker"
                staff <- createStaffRecord venue (Just worker) "Access" "Worker"

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams (EditStaffAction staff.id) [("weekOffset", "0")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-in access"
                response `responseBodyShouldContain` "staff-access-worker@example.com"
                response `responseBodyShouldContain` "Email passkey setup"
                response `responseBodyShouldContain` "Email recovery link"
                response `responseBodyShouldNotContain` "id=\"staff-profile-rsa\""
                response `responseBodyShouldNotContain` "Upload a Responsible Service of Alcohol statement of attainment."
                response `responseBodyShouldNotContain` "Upload and scan PDF"
                response `responseBodyShouldNotContain` "action=\"/ScanStaffDocument\""

        it "ignores staff pay fields submitted by non-admin managers" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Venue A"
                manager <- createUserRecord "staff-pay-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager "manager"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#isDefault, True) |> fetchOne
                payLevel <- createPayLevelRecord venue "Level 2"
                staff <- createStaffRecord venue Nothing "Alpha" "Crew"

                response <- withUserAndCurrentVenue manager (get #id venue) do
                    callActionWithParams
                        (UpdateStaffAction staff.id)
                        [ ("section", "profile")
                        , ("firstName", "Alpha")
                        , ("lastName", "Crew")
                        , ("preferredName", "")
                        , ("phone", "0400000000")
                        , ("emergencyContactName", "Jordan Crew")
                        , ("emergencyContactPhone", "0411111111")
                        , ("idealShiftsPerWeek", "4")
                        , ("isActive", "on")
                        , ("employmentBasis", "permanent")
                        , ("payRateSelection", cs ("award:" <> tshow payLevel.id))
                        , ("weekOffset", "0")
                        , ("rosterGroupIds", cs (tshow rosterGroup.id))
                        ]

                response `responseStatusShouldBe` status302
                updatedStaff <- fetch staff.id
                updatedStaff.employmentBasis `shouldBe` Casual
                updatedStaff.defaultAwardLevelId `shouldBe` Nothing

shouldContainInOrder :: String -> [String] -> Expectation
shouldContainInOrder haystack needles =
    go haystack needles
    where
        go _ [] = pure ()
        go remaining (needle : rest) =
            case findNeedle needle remaining of
                Nothing -> expectationFailure "Expected to find text in order"
                Just afterNeedle -> go afterNeedle rest

        findNeedle needle value =
            case List.dropWhile (not . List.isPrefixOf needle) (List.tails value) of
                []        -> Nothing
                match : _ -> Just (drop (length needle) match)
