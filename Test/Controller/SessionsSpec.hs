{-# LANGUAGE TypeApplications #-}

module Test.Controller.SessionsSpec where

import Application.Helper.Controller (currentVenueSessionKey,
                                      passkeyVerifiedAtSessionKey,
                                      passkeyVerifiedUserSessionKey)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeyDom (..),
                                                            canonicalPasskeyDom)
import Application.Helper.SessionVersion (sessionVersionSessionKey)
import Config
import qualified Data.Serialize as Serialize
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import qualified IHP.AuthSupport.Controller.Sessions as Sessions
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.Sessions ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "SessionsController" do
        it "renders the login form" $ withContext do
            response <- callAction NewSessionAction
            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Sign In"
            response `responseBodyShouldNotContain` "data-disable-javascript-submission"
            response `responseBodyShouldNotContain` "Need venue access?"
            response `responseBodyShouldNotContain` "Request an invitation"
            response `responseBodyShouldNotContain` "/helpers.js"

        it "redirects successful logins to the roster week flow" $ withContext do
            Sessions.afterLoginRedirectPath @User `shouldBe` pathTo RosterWeeksAction

        it "rejects sessions issued before the user's session version changed" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Revoked Session Venue"
                user <- createUserRecord "revoked-session@example.com" "staff" True
                    >>= updateRecord . set #sessionVersion 1
                _ <- createVenueMembershipRecord venue user Worker

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    , (passkeyVerifiedAtSessionKey, Serialize.encode ("9999999999" :: Text))
                    ]
                    do
                        response <- callAction EditProfileAction
                        getSession @Text passkeyVerifiedUserSessionKey `shouldReturn` Nothing
                        getSession @Text passkeyVerifiedAtSessionKey `shouldReturn` Nothing
                        pure response

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

        it "accepts a session carrying the user's current session version" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Current Session Version Venue"
                user <- createUserRecord "current-session-version@example.com" "staff" True
                    >>= updateRecord . set #sessionVersion 1
                _ <- createVenueMembershipRecord venue user Worker

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (sessionVersionSessionKey, Serialize.encode (1 :: Int))
                    ]
                    do
                        callAction EditProfileAction

                response `responseStatusShouldBe` status200

        it "verifies a user, signs them in, and redirects to profile editing" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Verify Venue"
                user <- createUserRecord "verify-me@example.com" "staff" False
                    >>= updateRecord . set #emailVerifiedAt Nothing
                _ <- createVenueMembershipRecord venue user Worker
                now <- getCurrentTime
                tokenRecord <- newRecord @EmailVerificationToken
                    |> set #userId (unpackId (get #id user))
                    |> set #token "valid-token"
                    |> set #sentToEmail user.email
                    |> set #expiresAt (addUTCTime 3600 now)
                    |> createRecord

                withSessionValues [] do
                    response <- callActionWithParams VerifyEmailAction [("token", cs tokenRecord.token)]

                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile"

                    verifiedUser <- fetch (get #id user)
                    consumedToken <- fetch (get #id tokenRecord)
                    verifiedUser.emailVerifiedAt `shouldSatisfy` isJust
                    consumedToken.consumedAt `shouldSatisfy` isJust

                    editProfileResponse <- callAction EditProfileAction
                    editProfileResponse `responseStatusShouldBe` status200
                    editProfileResponse `responseBodyShouldContain` "Profile"
                    editProfileResponse `responseBodyShouldContain` user.email

        it "rejects invalid verification tokens" $ withContext do
            withCleanDb do
                response <- callActionWithParams VerifyEmailAction [("token", "missing-token")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

        it "rejects expired verification tokens" $ withContext do
            withCleanDb do
                user <- createUserRecord "expired-verify@example.com" "staff" True
                    >>= updateRecord . set #emailVerifiedAt Nothing
                now <- getCurrentTime
                token <- newRecord @EmailVerificationToken
                    |> set #userId (unpackId (get #id user))
                    |> set #token "expired-token"
                    |> set #sentToEmail user.email
                    |> set #expiresAt (addUTCTime (-3600) now)
                    |> createRecord

                response <- callActionWithParams VerifyEmailAction [("token", cs token.token)]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                unchangedUser <- fetch (get #id user)
                unchangedToken <- fetch (get #id token)
                unchangedUser.emailVerifiedAt `shouldBe` Nothing
                unchangedToken.consumedAt `shouldBe` Nothing

        it "does not allow a consumed token to be reused" $ withContext do
            withCleanDb do
                user <- createUserRecord "reuse-token@example.com" "staff" True
                    >>= updateRecord . set #emailVerifiedAt Nothing
                now <- getCurrentTime
                token <- newRecord @EmailVerificationToken
                    |> set #userId (unpackId (get #id user))
                    |> set #token "one-shot-token"
                    |> set #sentToEmail user.email
                    |> set #expiresAt (addUTCTime 3600 now)
                    |> createRecord

                _ <- callActionWithParams VerifyEmailAction [("token", cs token.token)]
                response <- callActionWithParams VerifyEmailAction [("token", cs token.token)]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

        it "blocks password login until the email is verified and shows the resend banner" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Pending Verification Venue"
                user <- createUserRecord "pending-login@example.com" "staff" True
                    >>= updateRecord . set #emailVerifiedAt Nothing
                _ <- createVenueMembershipRecord venue user Worker

                withSessionValues [] do
                    response <- callActionWithParams CreateSessionAction
                        [ ("email", cs user.email)
                        , ("password", cs testPassword)
                        ]

                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                    rendered <- callAction NewSessionAction
                    rendered `responseStatusShouldBe` status200
                    rendered `responseBodyShouldContain` "Verify your email before signing in."
                    rendered `responseBodyShouldContain` user.email

        it "allows password login after verification" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Verified Login Venue"
                user <- createUserRecord "verified-login@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- callActionWithParams CreateSessionAction
                    [ ("email", cs user.email)
                    , ("password", cs testPassword)
                    ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/RosterWeeks"
                getSession @Int sessionVersionSessionKey `shouldReturn` Just 0

                auditEvent <- query @AuditEvent
                    |> filterWhere (#eventType, "login_succeeded")
                    |> fetchOne
                auditEvent.venueId `shouldBe` unpackId (get #id venue)
                auditEvent.actorUserId `shouldBe` unpackId (get #id user)
                auditEvent.targetTable `shouldBe` "users"
                auditEvent.targetId `shouldBe` unpackId (get #id user)

        it "redirects a bootstrap super-admin without venues to support" $ withContext do
            withCleanDb do
                user <- createUserRecordWithPlatformRole "bootstrap-super-admin@example.com" "staff" (Just SuperAdmin) True

                response <- callActionWithParams CreateSessionAction
                    [ ("email", cs user.email)
                    , ("password", cs testPassword)
                    ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/Support"

        it "prompts users without passkeys to set up faster sign-in after password login" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "First Passkey Prompt Venue"
                user <- createUserRecord "first-passkey-prompt@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                withSessionValues [] do
                    loginResponse <- callActionWithParams CreateSessionAction
                        [ ("email", cs user.email)
                        , ("password", cs testPassword)
                        ]
                    loginResponse `responseStatusShouldBe` status302

                    rosterResponse <- callAction (ShowRosterWeekAction 0)
                    rosterResponse `responseStatusShouldBe` status200
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeySetupPromptAttribute
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyFlowConfigAttribute
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyDismissalAttribute
                    rosterResponse `responseBodyShouldContain` cs ("&quot;promptUserKey&quot;:&quot;" <> tshow user.id <> "&quot;")
                    rosterResponse `responseBodyShouldContain` "&quot;setupPromptMode&quot;:&quot;first-passkey&quot;"
                    rosterResponse `responseBodyShouldContain` "Set up faster sign-in"
                    rosterResponse `responseBodyShouldNotContain` "js-passkey-setup-prompt"
                    rosterResponse `responseBodyShouldNotContain` "data-user-id"
                    rosterResponse `responseBodyShouldNotContain` "data-mode"

        it "presents passkeys as optional faster sign-in when privileged strong authentication is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Optional Admin Passkey Prompt Venue"
                user <- createUserRecord "optional-admin-passkey-prompt@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user VenueOwner

                withPrivilegedStrongAuthentication False do
                    withSessionValues [] do
                        loginResponse <- callActionWithParams CreateSessionAction
                            [ ("email", cs user.email)
                            , ("password", cs testPassword)
                            ]
                        loginResponse `responseStatusShouldBe` status302

                        rosterResponse <- callAction (ShowRosterWeekAction 0)
                        rosterResponse `responseStatusShouldBe` status200
                        rosterResponse `responseBodyShouldContain` "Set up faster sign-in"
                        rosterResponse `responseBodyShouldContain` "You can skip this for now."
                        rosterResponse `responseBodyShouldNotContain` "Create a passkey for admin access"
                        rosterResponse `responseBodyShouldNotContain` "restricted venue administration requires a passkey"

        it "prompts password users with existing passkeys to add this device" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Additional Device Prompt Venue"
                user <- createUserRecord "additional-device-prompt@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                _ <- createTestPasskeyRecord user "Phone"

                withSessionValues [] do
                    loginResponse <- callActionWithParams CreateSessionAction
                        [ ("email", cs user.email)
                        , ("password", cs testPassword)
                        ]
                    loginResponse `responseStatusShouldBe` status302

                    rosterResponse <- callAction (ShowRosterWeekAction 0)
                    rosterResponse `responseStatusShouldBe` status200
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeySetupPromptAttribute
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyFlowConfigAttribute
                    rosterResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyDismissalAttribute
                    rosterResponse `responseBodyShouldContain` cs ("&quot;promptUserKey&quot;:&quot;" <> tshow user.id <> "&quot;")
                    rosterResponse `responseBodyShouldContain` "&quot;setupPromptMode&quot;:&quot;additional-device&quot;"
                    rosterResponse `responseBodyShouldContain` "Add this device as a passkey"
                    rosterResponse `responseBodyShouldNotContain` "js-passkey-setup-prompt"
                    rosterResponse `responseBodyShouldNotContain` "data-user-id"
                    rosterResponse `responseBodyShouldNotContain` "data-mode"

        it "audits failed password logins for known invited accounts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Failed Login Venue"
                user <- createUserRecord "failed-login@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- callActionWithParams CreateSessionAction
                    [ ("email", cs user.email)
                    , ("password", "wrong-password")
                    ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                auditEvent <- query @AuditEvent
                    |> filterWhere (#eventType, "login_failed")
                    |> fetchOne
                auditEvent.venueId `shouldBe` unpackId (get #id venue)
                auditEvent.actorUserId `shouldBe` unpackId (get #id user)
                auditEvent.targetTable `shouldBe` "users"
                auditEvent.targetId `shouldBe` unpackId (get #id user)

        it "resends verification for unverified accounts and surfaces the banner" $ withContext do
            withCleanDb do
                user <- createUserRecord "resend-me@example.com" "staff" True
                    >>= updateRecord . set #emailVerifiedAt Nothing

                withSessionValues [] do
                    response <- callActionWithParams ResendVerificationAction [("email", cs user.email)]

                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                    tokens <- query @EmailVerificationToken |> filterWhere (#userId, unpackId (get #id user)) |> fetch
                    length tokens `shouldBe` 1

                    rendered <- callAction NewSessionAction
                    rendered `responseStatusShouldBe` status200
                    rendered `responseBodyShouldContain` "Verify your email before signing in."
                    rendered `responseBodyShouldContain` user.email

        it "does not create resend tokens for verified accounts" $ withContext do
            withCleanDb do
                user <- createUserRecord "already-verified@example.com" "staff" True

                response <- callActionWithParams ResendVerificationAction [("email", cs user.email)]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                tokenCount <- query @EmailVerificationToken |> filterWhere (#userId, unpackId (get #id user)) |> fetchCount
                tokenCount `shouldBe` 0

        it "does not create resend tokens for unknown emails" $ withContext do
            withCleanDb do
                response <- callActionWithParams ResendVerificationAction [("email", "unknown@example.com")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/NewSession"

                tokenCount <- query @EmailVerificationToken |> fetchCount
                tokenCount `shouldBe` 0

        it "stores the current venue during beforeLogin for verified users" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Current Venue"
                user <- createUserRecord "before-login@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                selectedVenueId <- withControllerTestContext do
                    Sessions.beforeLogin @User user
                    getSession @(Id Venue) currentVenueSessionKey

                selectedVenueId `shouldBe` Just (get #id venue)
