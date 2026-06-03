module Test.Controller.UsersSpec where

import Application.Helper.Controller (unsafeEnumFromText,
                                      updateVenueMembershipRoleWithAudit,
                                      validRosterWeekStartDays)
import Application.Helper.LiveResource
import Config
import Data.Aeson (Value (Null))
import qualified Data.ByteString.Char8 as ByteString
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
import Web.Users.Mutations (acceptedVenueInvitationTouchedResources)
import Web.Routes
import Web.Types

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
tests = beforeAll testContext do
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
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "readonly=\"readonly\""

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

        it "creates a verified user, venue, and owner membership from a pending onboarding invitation" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-create-venue@example.com"

                response <- callActionWithParams CreateVenueOnboardingUserAction $
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    , ("name", "Owner Venue")
                    , ("timezone", "Australia/Melbourne")
                    , ("rosterWeekStartsOn", "2")
                    ] <> signupStaffParams

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"

                user <- query @User |> filterWhere (#email, "owner-create-venue@example.com") |> fetchOne
                venue <- query @Venue |> filterWhere (#name, "Owner Venue") |> fetchOne
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                membership <- query @VenueMembership |> filterWhere (#userId, unpackId user.id) |> fetchOne
                staff <- query @Staff |> filterWhere (#venueId, unpackId venue.id) |> filterWhere (#userId, Just (unpackId user.id)) |> fetchOneOrNothing
                updatedInvitation <- fetch invitation.id

                venueConfig.timezone `shouldBe` "Australia/Melbourne"
                venueConfig.rosterWeekStartsOn `shouldBe` 2
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

                acceptedVenueInvitationTouchedResources invitation `shouldBe` [AdminInvitesResource (unpackId venue.id)]

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
