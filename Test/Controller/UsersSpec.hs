module Test.Controller.UsersSpec where

import Application.Helper.Controller (unsafeEnumFromText,
                                      updateVenueMembershipRoleWithAudit)
import Config
import Data.Aeson (Value (Null))
import Data.Time.Clock (addUTCTime, getCurrentTime)
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
import Web.Controller.Users ()
import Web.FrontController ()
import Web.Routes
import Web.Types

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
                founder <- query @User
                    |> filterWhere (#email, bootstrapFounderEmail)
                    |> fetchOneOrNothing
                userCount `shouldBe` 1
                fmap (.email) founder `shouldBe` Just bootstrapFounderEmail

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

                acceptedUser <- query @User
                    |> filterWhere (#email, "accepted@example.com")
                    |> fetchOneOrNothing
                founder <- query @User
                    |> filterWhere (#email, bootstrapFounderEmail)
                    |> fetchOne
                founderMembershipCount <- query @VenueMembership
                    |> filterWhere (#userId, unpackId founder.id)
                    |> fetchCount
                acceptedUser `shouldBe` Nothing
                founderMembershipCount `shouldBe` 1

        it "creates a user and venue membership from a pending invitation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Bootstrap Venue"
                invitation <- createVenueInvitationRecord venue Nothing "owner@example.com" "venue_owner"

                response <- callActionWithParams CreateUserAction
                    [ ("invitationId", idToParam invitation.id)
                    , ("passwordHash", "test-password-123")
                    , ("passwordConfirmation", "test-password-123")
                    ]

                response `responseStatusShouldBe` status302

                user <- query @User
                    |> filterWhere (#email, "owner@example.com")
                    |> fetchOne
                membership <- query @VenueMembership
                    |> filterWhere (#userId, unpackId user.id)
                    |> fetchOne
                updatedInvitation <- fetch invitation.id

                membership.venueId `shouldBe` unpackId venue.id
                inputValue membership.venueRole `shouldBe` "venue_owner"
                inputValue user.userRole `shouldBe` "staff"
                inputValue updatedInvitation.status `shouldBe` "accepted"
                updatedInvitation.acceptedByUserId `shouldBe` Just (unpackId user.id)

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
