module Test.Controller.UsersSpec where

import Application.Helper.Controller (unsafeEnumFromText,
                                      updateVenueMembershipRoleWithAudit,
                                      validRosterWeekStartDays)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffPreferencesResource,
                                                                     staffProfileResource)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterSlotsContentResource,
                                                                    rosterWeekResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.SurfaceResource
import Application.Helper.VenueBootstrap (defaultVenueBootstrapTimezone)
import Config
import Data.Aeson (Value (Null))
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Set as Set
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.ModelSupport (inputValue)
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai
import Test.Hspec
import Test.Support
import Web.Controller.Users ()
import Web.FrontController ()
import Web.Routes
import Web.Types
import Web.Users.Mutations (acceptedVenueInvitationTouchedResources,
                            acceptedVenueInvitationTouchedResourcesForScopes)

signupStaffParams :: [(ByteString, ByteString)]
signupStaffParams =
    [ ("firstName", "Taylor")
    , ("lastName", "Smith")
    , ("preferredName", "")
    , ("phone", "0400000000")
    , ("emergencyContactName", "Casey Smith")
    , ("emergencyContactPhone", "0411111111")
    , ("idealShiftsPerWeek", "3")
    ]

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "UsersController" do
        it "renders the invitation-only access page without an invitation" $ withContext do
            response <- callAction NewUserAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Invitation Required"
            response `responseBodyShouldContain` "Sign In"
            response `responseBodyShouldNotContain` "Confirm Password"

        it "renders the invited signup form for a valid invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "invitee@example.com" "venue_admin"

                response <- callActionWithParams NewUserAction [("invitationId", idToParam invitation.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Accept Invitation"
                response `responseBodyShouldContain` "invitee@example.com"
                response `responseBodyShouldContain` "venue admin"
                response `responseBodyShouldNotContain` "data-disable-javascript-submission"
                response `responseBodyShouldContain` "Account Details"
                response `responseBodyShouldContain` "Confirm your staff details"
                response `responseBodyShouldContain` "id=\"email\""
                response `responseBodyShouldContain` "disabled=\"disabled\""
                response `responseBodyShouldNotContain` "id=\"invite-email\""
                response `responseBodyShouldNotContain` "id=\"staff-email\""

        it "prefills the signup form from an adoptable trial staff invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Trial Adoption Signup Venue"
                staff <- createStaffRecord venue Nothing "Blair" "Trial"
                    >>= updateRecord . set #preferredName (Just "Bee")
                invitation <- createVenueInvitationRecord venue Nothing "blair-trial@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- callActionWithParams NewUserAction [("invitationId", idToParam invitation.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Accept Invitation"
                response `responseBodyShouldContain` "claim an existing trial staff profile"
                response `responseBodyShouldContain` "value=\"Blair\""
                response `responseBodyShouldContain` "value=\"Trial\""
                response `responseBodyShouldContain` "value=\"Bee\""
                response `responseBodyShouldContain` "blair-trial@example.com"
                response `responseBodyShouldContain` "Confirm your staff details"

        it "does not render the signup form when the adoption target is already linked" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Linked Adoption Signup Venue"
                linkedUser <- createUserRecord "linked-adoption-target@example.com" "staff" True
                staff <- createStaffRecord venue (Just linkedUser) "Linked" "Trial"
                invitation <- createVenueInvitationRecord venue Nothing "linked-adoption@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- callActionWithParams NewUserAction [("invitationId", idToParam invitation.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"
                response `responseBodyShouldNotContain` "Accept Invitation"

        it "does not render the signup form for an expired invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Expired Invite Venue"
                now <- getCurrentTime
                invitation <- createVenueInvitationRecord venue Nothing "expired@example.com" "worker"
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-3600) now))

                response <- callActionWithParams NewUserAction [("invitationId", idToParam invitation.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"
                response `responseBodyShouldNotContain` "Accept Invitation"

        it "does not create accounts without an invitation" $ withContext do
            withCleanDb do
                response <- callActionWithParams CreateUserAction
                    [ ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"

                userCount <- query @User |> fetchCount
                userCount `shouldBe` 0

        it "renders the onboarding signup form for a valid venue owner invitation" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-onboarding@example.com"

                response <- callActionWithParams NewVenueOnboardingUserAction [("invitationId", idToParam invitation.id)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Create Your Venue"
                response `responseBodyShouldContain` "owner-onboarding@example.com"
                response `responseBodyShouldContain` "Roster week starts on"
                response `responseBodyShouldContain` "Account Details"
                response `responseBodyShouldContain` "Confirm your staff details"
                response `responseBodyShouldContain` "id=\"email\""
                response `responseBodyShouldContain` "disabled=\"disabled\""
                response `responseBodyShouldNotContain` "id=\"staff-email\""
                response `responseBodyShouldNotContain` "id=\"invite-email\""
                response `responseBodyShouldContain` "Show shift end times in roster"
                response `responseBodyShouldNotContain` "Auto-create pending timesheets"
                response `responseBodyShouldNotContain` "autoTimesheetCreationEnabled"
                response `responseBodyShouldNotContain` "venue-timezone"
                response `responseBodyShouldNotContain` "Already have an account?"

        it "creates a verified user, venue, and owner membership from a pending onboarding invitation" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-create-venue@example.com"

                response <- callActionWithParams CreateVenueOnboardingUserAction $
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    , ("name", "Owner Venue")
                    , ("timezone", "Pacific/Auckland")
                    , ("rosterWeekStartsOn", "2")
                    , ("autoTimesheetCreationEnabled", "true")
                    ] <> signupStaffParams

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

                user <- query @User |> filterWhere (#email, "owner-create-venue@example.com") |> fetchOne
                venue <- query @Venue |> filterWhere (#name, "Owner Venue") |> fetchOne
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                membership <- query @VenueMembership |> filterWhere (#userId, unpackId user.id) |> fetchOne
                staff <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#userId, Just (unpackId user.id)) |> fetchOneOrNothing
                updatedInvitation <- fetch invitation.id

                venueConfig.timezone `shouldBe` defaultVenueBootstrapTimezone
                venueConfig.rosterWeekStartsOn `shouldBe` 2
                venueConfig.rosterEndTimesEnabled `shouldBe` False
                venueConfig.autoTimesheetCreationEnabled `shouldBe` False
                venueConfig.rosterWeekStartsOn `shouldSatisfy` (`elem` validRosterWeekStartDays)
                inputValue membership.venueRole `shouldBe` "venue_owner"
                staff `shouldSatisfy` isJust
                inputValue updatedInvitation.status `shouldBe` "accepted"
                updatedInvitation.acceptedByUserId `shouldBe` Just (unpackId user.id)

        it "does not redeem an invitation that has already been accepted" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Accepted Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "accepted@example.com" "manager"
                    >>= updateRecord . set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")

                response <- callActionWithParams CreateUserAction
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"

                userCount <- query @User |> fetchCount
                membershipCount <- query @VenueMembership |> fetchCount
                userCount `shouldBe` 0
                membershipCount `shouldBe` 0

        it "does not redeem an invitation that has been revoked" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Revoked Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "revoked@example.com" "worker"
                    >>= updateRecord . set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")

                response <- callActionWithParams CreateUserAction
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"

                userCount <- query @User |> fetchCount
                membershipCount <- query @VenueMembership |> fetchCount
                userCount `shouldBe` 0
                membershipCount `shouldBe` 0

        it "does not create or accept invited accounts until staff details are complete" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Incomplete Staff Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "incomplete-staff@example.com" "worker"

                response <- callActionWithParams CreateUserAction
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Confirm your staff details"
                userExists <- query @User |> filterWhere (#email, "incomplete-staff@example.com") |> fetchExists
                updatedInvitation <- fetch invitation.id
                userExists `shouldBe` False
                inputValue updatedInvitation.status `shouldBe` "pending"
                updatedInvitation.acceptedAt `shouldBe` Nothing

        it "records touched resources for accepted venue invitations" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invitation Touch Venue"
                invitation <- createVenueInvitationRecord venue Nothing "touch@example.com" "manager"
                staff <- createStaffRecord venue Nothing "Touch" "Trial"
                adoptionInvitation <- createVenueInvitationRecord venue Nothing "touch-adoption@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                acceptedVenueInvitationTouchedResources invitation `shouldBe` [adminInvitesResource (unpackId venue.id)]
                acceptedVenueInvitationTouchedResources adoptionInvitation
                    `shouldBe`
                        [ adminInvitesResource (unpackId venue.id)
                        , staffProfileResource (unpackId staff.id)
                        , staffPreferencesResource (unpackId staff.id)
                        ]

                let rosterGroupId = Id (unpackId venue.id) :: Id RosterGroup
                let activeRosterScopes = [(unpackId venue.id, unpackId rosterGroupId, 3)]
                let activeTimesheetScopes = [(unpackId venue.id, 3)]
                Set.fromList (acceptedVenueInvitationTouchedResourcesForScopes adoptionInvitation activeRosterScopes activeTimesheetScopes [rosterGroupId])
                    `shouldBe`
                        Set.fromList
                            [ adminInvitesResource (unpackId venue.id)
                            , staffProfileResource (unpackId staff.id)
                            , staffPreferencesResource (unpackId staff.id)
                            , rosterWeekResource (unpackId rosterGroupId) 3
                            , rosterSlotsContentResource (unpackId rosterGroupId) 3
                            , timesheetWeekResource (unpackId venue.id) 3
                            ]

        it "creates a verified user and venue membership from a pending invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Bootstrap Venue"
                invitation <- createVenueInvitationRecord venue Nothing "owner@example.com" "venue_owner"

                response <- callActionWithParams CreateUserAction $
                    [ ("invitationId", idToParam invitation.id)
                    , ("email", "attacker@example.com")
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ] <> signupStaffParams

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

                user <- query @User
                    |> filterWhere (#email, "owner@example.com")
                    |> fetchOne
                membership <- query @VenueMembership
                    |> filterWhere (#userId, unpackId user.id)
                    |> fetchOne
                staff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId user.id))
                    |> fetchOneOrNothing
                updatedInvitation <- fetch invitation.id
                unexpectedUser <- query @User
                    |> filterWhere (#email, "attacker@example.com")
                    |> fetchOneOrNothing
                verificationTokenCount <- query @EmailVerificationToken |> fetchCount

                membership.venueId `shouldBe` unpackId venue.id
                staff `shouldSatisfy` isJust
                inputValue membership.venueRole `shouldBe` "venue_owner"
                inputValue user.userRole `shouldBe` "staff"
                isJust user.emailVerifiedAt `shouldBe` True
                inputValue updatedInvitation.status `shouldBe` "accepted"
                updatedInvitation.acceptedByUserId `shouldBe` Just (unpackId user.id)
                unexpectedUser `shouldBe` Nothing
                verificationTokenCount `shouldBe` 0

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId user.id
                auditEvent.eventType `shouldBe` "venue_role_assigned"
                auditEvent.targetTable `shouldBe` "venue_memberships"
                auditEvent.targetId `shouldBe` unpackId membership.id

                roleEvent <- query @VenueMembershipRoleEvent |> fetchOne
                inputValue roleEvent.eventType `shouldBe` "assigned"
                roleEvent.previousRole `shouldBe` Nothing
                inputValue roleEvent.newRole `shouldBe` "venue_owner"

        it "adopts an existing trial staff row when accepting a staff-linked invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Adopt Trial Venue"
                trialStaff <- createStaffRecord venue Nothing "Blair" "Trial"
                rosterWeek <- createRosterWeekRecord venue 0 False
                rosterDay <- createRosterDayRecord rosterWeek 0
                slotName <- createSlotNameRecord venue "Floor"
                rosterSlot <- createRosterSlotRecord rosterDay slotName (Just trialStaff) 0
                invitation <- createVenueInvitationRecord venue Nothing "adopt-trial@example.com" "worker"
                    >>= updateRecord . set #staffId (Just trialStaff.id)

                response <- callActionWithParams CreateUserAction $
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    , ("firstName", "Blair Updated")
                    , ("lastName", "Trial")
                    , ("preferredName", "Bee")
                    , ("phone", "0499999999")
                    , ("emergencyContactName", "Casey Trial")
                    , ("emergencyContactPhone", "0488888888")
                    , ("idealShiftsPerWeek", "4")
                    ]

                response `responseStatusShouldBe` status302
                user <- query @User |> filterWhere (#email, "adopt-trial@example.com") |> fetchOne
                updatedStaff <- fetch trialStaff.id
                updatedSlot <- fetch rosterSlot.id
                membership <- query @VenueMembership |> filterWhere (#userId, unpackId user.id) |> fetchOne
                linkedStaffCount <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId user.id))
                    |> fetchCount
                updatedInvitation <- fetch invitation.id

                updatedStaff.userId `shouldBe` Just (unpackId user.id)
                updatedStaff.firstName `shouldBe` "Blair Updated"
                updatedStaff.preferredName `shouldBe` Just "Bee"
                updatedStaff.phone `shouldBe` "0499999999"
                updatedSlot.staffId `shouldBe` Just (unpackId trialStaff.id)
                linkedStaffCount `shouldBe` 1
                inputValue membership.venueRole `shouldBe` "worker"
                inputValue updatedInvitation.status `shouldBe` "accepted"
                updatedInvitation.acceptedByUserId `shouldBe` Just (unpackId user.id)

        it "does not accept a staff-linked invitation whose target was already linked" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Stale Adoption Venue"
                linkedUser <- createUserRecord "stale-adoption-linked@example.com" "staff" True
                staff <- createStaffRecord venue (Just linkedUser) "Stale" "Trial"
                invitation <- createVenueInvitationRecord venue Nothing "stale-adoption@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)

                response <- callActionWithParams CreateUserAction $
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ] <> signupStaffParams

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Invitation Required"
                userExists <- query @User |> filterWhere (#email, "stale-adoption@example.com") |> fetchExists
                updatedInvitation <- fetch invitation.id
                userExists `shouldBe` False
                inputValue updatedInvitation.status `shouldBe` "pending"

        it "records durable history when a venue membership role changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Role Change Venue"
                owner <- createUserRecord "owner-role@example.com" "staff" True
                user <- createUserRecord "worker-role@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                membership <- createVenueMembershipRecord venue user "worker"

                updatedMembership <- updateVenueMembershipRoleWithAudit
                    (unpackId owner.id)
                    "web"
                    membership
                    (unsafeEnumFromText @VenueRoleEnum "manager")
                    Null

                inputValue updatedMembership.venueRole `shouldBe` "manager"

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "venue_role_changed"
                auditEvent.targetId `shouldBe` unpackId membership.id

                roleEvent <- query @VenueMembershipRoleEvent |> fetchOne
                inputValue roleEvent.eventType `shouldBe` "changed"
                fmap inputValue roleEvent.previousRole `shouldBe` Just "worker"
                inputValue roleEvent.newRole `shouldBe` "manager"
