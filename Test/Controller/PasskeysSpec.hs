module Test.Controller.PasskeysSpec where

import Application.Helper.Controller (PlatformRole (SuperAdminRole),
                                      currentVenueSessionKey,
                                      formatPasskeyVerifiedAt,
                                      passkeyRecoveryVerifiedAtSessionKey,
                                      passkeyRecoveryVerifiedUserSessionKey,
                                      passkeyVerifiedAtSessionKey,
                                      passkeyVerifiedUserSessionKey,
                                      unsafeEnumFromText)
import Application.Helper.PasskeyRecoveryCodes (hashRecoveryCode)
import Application.Helper.PasskeySetupTokens (PasskeySetupTokenPurpose (SelfNewDevicePasskeySetup), issuePasskeySetupToken)
import Application.Helper.Passkeys (allowedOrigins, rpIdTextFromRequest)
import Config
import Crypto.WebAuthn.Model.Types (Origin (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as ByteString
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Serialize as Serialize
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.Prelude
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import qualified Network.Wai as Wai
import System.Environment (setEnv)
import Test.Hspec
import Test.Support
import Web.Controller.Auth (authenticationChallengeSessionKey,
                            registrationChallengeSessionKey,
                            registrationUserIdSessionKey,
                            stepUpAuthenticationChallengeSessionKey)
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "PasskeysController" do
        it "uses forwarded HTTPS origin when running behind a reverse proxy" $ withContext do
            withRequestHeaders [("X-Forwarded-Proto", "https")] do
                let ?request = ?request { Wai.requestHeaderHost = Just "bepis.lol" }

                allowedOrigins `shouldBe` (Origin "https://bepis.lol" :| [])
                rpIdTextFromRequest `shouldBe` "bepis.lol"

        it "renders passkey login entry points on the login form" $ withContext do
            response <- callAction NewSessionAction

            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Sign in with a passkey"
            response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyAuthentication\""
            response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyAuthentication\""

        it "requires an authenticated user to begin passkey registration" $ withContext do
            response <- callAction BeginPasskeyRegistrationAction

            response `responseStatusShouldBe` status302

        it "begins passkey authentication without an authenticated session" $ withContext do
            response <- callAction BeginPasskeyAuthenticationAction

            response `responseStatusShouldBe` status200
            lookup HTTP.hContentType (responseHeaders response) `shouldBe` Just "application/json"
            body <- responseBody response
            (Aeson.decode body :: Maybe Aeson.Value) `shouldSatisfy` isJust
            response `responseBodyShouldContain` "\"challenge\""

        it "rejects passkey authentication finishes after the challenge has expired" $ withContext do
            response <- withSessionValues [] do
                callAction FinishPasskeyAuthenticationAction

            response `responseStatusShouldBe` status422
            response `responseBodyShouldContain` "This passkey request has expired. Please try again."

        it "rejects passkey authentication finishes that do not send JSON" $ withContext do
            response <- withSessionValues
                [ (authenticationChallengeSessionKey, Serialize.encode ("test-auth-challenge" :: ByteString.ByteString))
                ]
                do
                    callActionWithParams FinishPasskeyAuthenticationAction [("credential", "not-json")]

            response `responseStatusShouldBe` status400
            response `responseBodyShouldContain` "Expected JSON body, but the request has a form content type."

        it "renders passkey management on the security profile section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Profile Venue"
                user <- createUserRecord "passkey-profile@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-In Methods"
                response `responseBodyShouldContain` "Add passkey"
                response `responseBodyShouldContain` "No passkeys registered yet."
                response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyRegistration\""
                response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyRegistration\""

        it "prompts mandatory-passkey users to add a backup passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Backup Passkey Prompt Venue"
                user <- createUserRecord "backup-passkey-prompt@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Only admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Add a backup passkey."
                response `responseBodyShouldContain` "should keep at least two passkeys"

        it "requires venue admins without passkeys to finish security setup before operational pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mandatory Admin Passkey Venue"
                user <- createUserRecord "mandatory-admin-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"

        it "requires venue owners without passkeys to finish security setup before operational pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mandatory Owner Passkey Venue"
                user <- createUserRecord "mandatory-owner-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_owner"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"

        it "does not require workers without passkeys to finish passkey setup before roster access" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Worker Optional Passkey Venue"
                user <- createUserRecord "worker-passkey-optional@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response)
                    `shouldSatisfy` maybe False ("http://localhost/ShowRosterWeek?weekOffset=" `ByteString.isPrefixOf`)

        it "requires passkey verification before venue admin pages when a passkey exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Step Up Venue"
                user <- createUserRecord "admin-step-up@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin security key"

                withUserAndCurrentVenue user venue.id do
                    response <- callAction AdminAction
                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

                    stepUpResponse <- callAction PasskeyStepUpAction
                    stepUpResponse `responseStatusShouldBe` status200
                    stepUpResponse `responseBodyShouldContain` "Verify with a passkey"
                    stepUpResponse `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyStepUpAuthentication\""
                    stepUpResponse `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyStepUpAuthentication\""
                    stepUpResponse `responseBodyShouldContain` "data-success-redirect=\"/RosterWeeks\""
                    stepUpResponse `responseBodyShouldContain` "Can't access your passkey?"
                    stepUpResponse `responseBodyShouldContain` "Use recovery code"

        it "audits failed passkey step-up attempts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Step Up Audit Venue"
                user <- createUserRecord "admin-step-up-audit@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction BeginPasskeyStepUpAuthenticationAction

                response `responseStatusShouldBe` status422
                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.venueId `shouldBe` unpackId venue.id
                auditEvent.actorUserId `shouldBe` unpackId user.id
                auditEvent.eventType `shouldBe` "passkey_step_up_failed"
                auditEvent.targetTable `shouldBe` "users"
                auditEvent.targetId `shouldBe` unpackId user.id

        it "rejects passkey step-up finishes after the challenge has expired" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Step Up Expired Venue"
                user <- createUserRecord "admin-step-up-expired@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction FinishPasskeyStepUpAuthenticationAction

                response `responseStatusShouldBe` status422
                response `responseBodyShouldContain` "This passkey request has expired. Please try again."

        it "rejects passkey step-up finishes that do not send JSON" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Step Up JSON Venue"
                user <- createUserRecord "admin-step-up-json@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (stepUpAuthenticationChallengeSessionKey, Serialize.encode ("test-step-up-challenge" :: ByteString.ByteString))
                    ]
                    do
                        callActionWithParams FinishPasskeyStepUpAuthenticationAction [("credential", "not-json")]

                response `responseStatusShouldBe` status400
                response `responseBodyShouldContain` "Expected JSON body, but the request has a form content type."

        it "allows venue admin pages after the session has passkey verification" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Verified Admin Venue"
                user <- createUserRecord "verified-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"
                now <- getCurrentTime

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    , (passkeyVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
                    ]
                    do
                        callAction AdminAction

                response `responseStatusShouldBe` status200

        it "keeps passkey verification fresh for privileged access within 30 minutes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Twenty Minute Admin Passkey Venue"
                user <- createUserRecord "twenty-minute-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"
                now <- getCurrentTime
                let verifiedAt = addUTCTime (negate (20 * 60)) now

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    , (passkeyVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt verifiedAt))
                    ]
                    do
                        callAction AdminAction

                response `responseStatusShouldBe` status200

        it "requires a fresh passkey verification for venue admin pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Expired Admin Passkey Venue"
                user <- createUserRecord "expired-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    , (passkeyVerifiedAtSessionKey, Serialize.encode ("0" :: Text))
                    ]
                    do
                        callAction AdminAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "forces passkey setup immediately after promotion to venue admin" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Promoted Admin Passkey Venue"
                user <- createUserRecord "promoted-admin@example.com" "staff" True
                membership <- createVenueMembershipRecord venue user "worker"
                _ <- membership
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum "venue_admin")
                    |> updateRecord

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"

        it "requires fresh passkey verification before adding another admin passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Additional Admin Passkey Venue"
                user <- createUserRecord "additional-admin-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Existing admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction BeginPasskeyRegistrationAction

                response `responseStatusShouldBe` status403
                response `responseBodyShouldContain` "Verify with your passkey before adding another passkey."
                response `responseBodyShouldContain` "\"redirectTo\":\"/PasskeyStepUp\""

        it "accepts and consumes a one-time passkey recovery code" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Recovery Code Venue"
                user <- createUserRecord "recovery-code@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Existing admin passkey"
                recoveryCode <- newRecord @PasskeyRecoveryCode
                    |> set #userId (unpackId user.id)
                    |> set #codeHash (hashRecoveryCode "abcd-efgh-ijkl-mnop")
                    |> createRecord

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "ABCD EFGH IJKL MNOP")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"
                consumedCode <- fetch recoveryCode.id
                consumedCode.usedAt `shouldSatisfy` isJust

                reuseResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "ABCD-EFGH-IJKL-MNOP")]

                reuseResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders reuseResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "routes super-admin recovery code users back to support passkey setup" $ withContext do
            withCleanDb do
                founder <- createUserRecordWithPlatformRole "support-recovery-code@example.com" "staff" (Just SuperAdminRole) True
                _ <- createTestPasskeyRecord founder "Existing support passkey"
                _ <- newRecord @PasskeyRecoveryCode
                    |> set #userId (unpackId founder.id)
                    |> set #codeHash (hashRecoveryCode "support-recovery-code")
                    |> createRecord

                response <- withUser founder do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "support recovery code")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/Support"
                now <- getCurrentTime
                supportResponse <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode founder.id)
                    , (passkeyRecoveryVerifiedUserSessionKey, Serialize.encode (inputValue founder.id :: Text))
                    , (passkeyRecoveryVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
                    ]
                    do
                        callAction SupportAction

                supportResponse `responseStatusShouldBe` status200
                supportResponse `responseBodyShouldContain` "Add passkey"
                supportResponse `responseBodyShouldContain` "data-success-redirect=\"/Support\""

        it "allows recovery-code verified admins to begin replacement passkey registration" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Recovery Registration Venue"
                user <- createUserRecord "recovery-registration@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Existing admin passkey"
                now <- getCurrentTime

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyRecoveryVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    , (passkeyRecoveryVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
                    ]
                    do
                        callAction BeginPasskeyRegistrationAction

                response `responseStatusShouldBe` status200
                lookup HTTP.hContentType (responseHeaders response) `shouldBe` Just "application/json"
                response `responseBodyShouldContain` "\"challenge\""

        it "requires fresh passkey verification before sending a new-device setup link" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Unverified New Device Setup Venue"
                user <- createUserRecord "unverified-new-device-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Existing admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction SendNewDevicePasskeySetupEmailAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                setupTokenExists <- query @PasskeySetupToken |> fetchExists
                setupTokenExists `shouldBe` False

        it "sends a new-device passkey setup link after fresh passkey verification" $ withContext do
            withCleanDb do
                setEnv "DISABLE_EMAIL_DELIVERY" "1"
                venue <- createVenueWithConfig "New Device Setup Venue"
                user <- createUserRecord "new-device-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Existing admin passkey"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    callAction SendNewDevicePasskeySetupEmailAction

                response `responseStatusShouldBe` status302
                setupToken <- query @PasskeySetupToken |> fetchOne
                setupToken.userId `shouldBe` unpackId user.id
                setupToken.requestedByUserId `shouldBe` Just (unpackId user.id)
                setupToken.venueId `shouldBe` Just (unpackId venue.id)
                setupToken.purpose `shouldBe` "self_new_device"

        it "renders an active passkey setup link" $ withContext do
            withCleanDb do
                user <- createUserRecord "setup-link@example.com" "staff" True
                (_setupToken, rawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing

                response <- callActionWithParams NewPasskeySetupAction [("token", cs rawToken)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Set Up New Passkey"
                response `responseBodyShouldContain` "setup-link@example.com"
                response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeySetupRegistration?token="
                response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeySetupRegistration\""

        it "rejects consumed and expired passkey setup links" $ withContext do
            withCleanDb do
                user <- createUserRecord "inactive-setup-link@example.com" "staff" True
                (consumedSetupToken, consumedRawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing
                now <- getCurrentTime
                consumedSetupToken
                    |> set #consumedAt (Just now)
                    |> updateRecordDiscardResult

                consumedResponse <- callActionWithParams NewPasskeySetupAction [("token", cs consumedRawToken)]

                consumedResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders consumedResponse) `shouldBe` Just "http://localhost/NewSession"

                (expiredSetupToken, expiredRawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing
                expiredSetupToken
                    |> set #expiresAt (addUTCTime (-60) now)
                    |> updateRecordDiscardResult

                expiredResponse <- callActionWithParams NewPasskeySetupAction [("token", cs expiredRawToken)]

                expiredResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders expiredResponse) `shouldBe` Just "http://localhost/NewSession"

        it "lets venue owners send staff passkey recovery links" $ withContext do
            withCleanDb do
                setEnv "DISABLE_EMAIL_DELIVERY" "1"
                venue <- createVenueWithConfig "Staff Recovery Venue"
                owner <- createUserRecord "staff-recovery-owner@example.com" "admin" True
                target <- createUserRecord "staff-recovery-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "venue_owner"
                _ <- createVenueMembershipRecord venue target "worker"
                targetStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId target.id))
                    |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callAction (SendStaffPasskeyRecoveryEmailAction targetStaff.id)

                response `responseStatusShouldBe` status302
                setupToken <- query @PasskeySetupToken |> fetchOne
                setupToken.userId `shouldBe` unpackId target.id
                setupToken.requestedByUserId `shouldBe` Just (unpackId owner.id)
                setupToken.venueId `shouldBe` Just (unpackId venue.id)
                setupToken.purpose `shouldBe` "staff_recovery"

        it "rejects passkey registration finishes if the pending user changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Pending Registration User Venue"
                pendingUser <- createUserRecord "pending-registration-user@example.com" "staff" True
                activeUser <- createUserRecord "active-registration-user@example.com" "staff" True
                _ <- createVenueMembershipRecord venue pendingUser "worker"
                _ <- createVenueMembershipRecord venue activeUser "worker"

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode activeUser.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (registrationChallengeSessionKey, Serialize.encode ("test-registration-challenge" :: ByteString.ByteString))
                    , (registrationUserIdSessionKey, Serialize.encode (inputValue pendingUser.id :: Text))
                    ]
                    do
                        callAction FinishPasskeyRegistrationAction

                response `responseStatusShouldBe` status422
                response `responseBodyShouldContain` "The pending passkey registration is invalid."

        it "lists existing passkeys on the security profile section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey List Venue"
                user <- createUserRecord "passkey-list@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createTestPasskeyRecord user "Phone passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Phone passkey"
                response `responseBodyShouldContain` "Delete"

        it "renames a user's passkey and normalizes blank names" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Rename Venue"
                user <- createUserRecord "passkey-rename@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                passkey <- createTestPasskeyRecord user "Original"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "  Laptop  ")]

                response `responseStatusShouldBe` status200
                renamedPasskey <- fetch passkey.id
                renamedPasskey.name `shouldBe` "Laptop"

                blankResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "   ")]

                blankResponse `responseStatusShouldBe` status200
                defaultedPasskey <- fetch passkey.id
                defaultedPasskey.name `shouldBe` "Passkey"

        it "does not let a user rename another user's passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Access Venue"
                owner <- createUserRecord "passkey-owner@example.com" "staff" True
                other <- createUserRecord "passkey-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "worker"
                _ <- createVenueMembershipRecord venue other "worker"
                passkey <- createTestPasskeyRecord owner "Owner passkey"

                response <- withUserAndCurrentVenue other venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "Compromised")]

                response `responseStatusShouldBe` status403
                unchangedPasskey <- fetch passkey.id
                unchangedPasskey.name `shouldBe` "Owner passkey"

        it "deletes a user's own passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Delete Venue"
                user <- createUserRecord "passkey-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                passkey <- createTestPasskeyRecord user "Delete me"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction passkey.id)

                response `responseStatusShouldBe` status302
                stillExists <- query @Passkey
                    |> filterWhere (#id, passkey.id)
                    |> fetchExists
                stillExists `shouldBe` False

        it "does not let a venue admin delete their last passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Last Admin Venue"
                user <- createUserRecord "passkey-last-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                passkey <- createTestPasskeyRecord user "Last admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction passkey.id)

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"
                stillExists <- query @Passkey
                    |> filterWhere (#id, passkey.id)
                    |> fetchExists
                stillExists `shouldBe` True

        it "requires fresh passkey verification before deleting an admin passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Delete Step Up Venue"
                user <- createUserRecord "passkey-delete-step-up@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                firstPasskey <- createTestPasskeyRecord user "First admin passkey"
                secondPasskey <- createTestPasskeyRecord user "Second admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction firstPasskey.id)

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                firstStillExists <- query @Passkey
                    |> filterWhere (#id, firstPasskey.id)
                    |> fetchExists
                secondStillExists <- query @Passkey
                    |> filterWhere (#id, secondPasskey.id)
                    |> fetchExists
                firstStillExists `shouldBe` True
                secondStillExists `shouldBe` True
