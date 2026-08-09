module Test.Controller.PasskeysSpec where

import Application.Helper.Controller (currentVenueSessionKey,
                                      formatPasskeyVerifiedAt,
                                      passkeyRecoveryVerifiedAtSessionKey,
                                      passkeyRecoveryVerifiedUserSessionKey,
                                      passkeyStepUpRedirectSessionKey,
                                      passkeyVerifiedAtSessionKey,
                                      passkeyVerifiedUserSessionKey)
import Application.Helper.FrontendContract.Overlay.Runtime (OverlayDom (..),
                                                            canonicalOverlayDom)
import Application.Helper.FrontendContract.Passkey.Runtime (PasskeyDom (..),
                                                            canonicalPasskeyDom)
import Application.Helper.PasskeyRecoveryCodes (hashRecoveryCode)
import Application.Helper.Passkeys (allowedOrigins, rpIdTextFromRequest)
import Application.Helper.PasskeySetupTokens (PasskeySetupTokenPurpose (SelfNewDevicePasskeySetup),
                                              issuePasskeySetupToken)
import Config
import Crypto.WebAuthn.Model.Types (Origin (..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as ByteString
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Serialize as Serialize
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, getCurrentTime,
                        secondsToDiffTime)
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
import Web.View.Passkeys.Management (formatRelativeLastUsed)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "PasskeysController" do
        it "formats relative passkey last-used times with one unit" $ withContext do
            let now = UTCTime (fromGregorian 2026 5 28) (secondsToDiffTime (12 * 60 * 60))
            formatRelativeLastUsed now Nothing `shouldBe` "Never"
            formatRelativeLastUsed now (Just (addUTCTime (negate (90 * 60)) now)) `shouldBe` "less than 2 hours ago"
            formatRelativeLastUsed now (Just (addUTCTime (negate (3 * 24 * 60 * 60)) now)) `shouldBe` "less than 3 days ago"
            formatRelativeLastUsed now (Just (addUTCTime (negate (13 * 24 * 60 * 60)) now)) `shouldBe` "less than 2 weeks ago"
            formatRelativeLastUsed now (Just (addUTCTime (negate (35 * 24 * 60 * 60)) now)) `shouldBe` "less than 2 months ago"

        it "uses forwarded HTTPS origin when running behind a reverse proxy" $ withContext do
            withRequestHeaders [("X-Forwarded-Proto", "https")] do
                let ?request = ?request { Wai.requestHeaderHost = Just "bepis.lol" }

                allowedOrigins `shouldBe` (Origin "https://bepis.lol" :| [])
                rpIdTextFromRequest `shouldBe` "bepis.lol"

        it "renders the generated passkey login control with a local accessible status" $ withContext do
            response <- callAction NewSessionAction

            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Sign in with a passkey"
            response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyLoginAttribute
            response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyFlowConfigAttribute
            response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyActionButtonAttribute
            response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyStatusAttribute
            response `responseBodyShouldContain` "&quot;beginUrl&quot;:&quot;/BeginPasskeyAuthentication&quot;"
            response `responseBodyShouldContain` "&quot;finishUrl&quot;:&quot;/FinishPasskeyAuthentication&quot;"
            response `responseBodyShouldContain` "role=\"status\""
            response `responseBodyShouldContain` "aria-live=\"polite\""
            response `responseBodyShouldNotContain` "js-passkey-"
            response `responseBodyShouldNotContain` "data-begin-url"
            response `responseBodyShouldNotContain` "data-finish-url"
            response `responseBodyShouldNotContain` "data-status-id"
            response `responseBodyShouldNotContain` "data-success-redirect"

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
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-In Methods"
                response `responseBodyShouldContain` "Add a passkey"
                response `responseBodyShouldContain` "Create passkey"
                response `responseBodyShouldContain` "No passkeys registered yet."
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                response `responseBodyShouldContain` "successRedirect=%2FEditProfile%3Fsection%3Dsecurity"
                response `responseBodyShouldNotContain` "data-begin-url=\"/BeginPasskeyRegistration\""
                response `responseBodyShouldNotContain` "data-finish-url=\"/FinishPasskeyRegistration\""
                response `responseBodyShouldNotContain` "modal fade show d-block"

        it "renders normal profile passkey management for venue admins without passkeys" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Profile Passkey Venue"
                user <- createUserRecord "admin-profile-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-In Methods"
                response `responseBodyShouldContain` "Add a passkey"
                response `responseBodyShouldContain` "Create passkey"
                response `responseBodyShouldContain` "No passkeys registered yet."
                response `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                response `responseBodyShouldContain` "successRedirect=%2FEditProfile%3Fsection%3Dsecurity"
                response `responseBodyShouldNotContain` "data-begin-url=\"/BeginPasskeyRegistration\""
                response `responseBodyShouldNotContain` "data-finish-url=\"/FinishPasskeyRegistration\""
                response `responseBodyShouldNotContain` "Create a passkey for admin access"
                response `responseBodyShouldNotContain` "restricted venue administration requires a passkey"
                response `responseBodyShouldNotContain` "modal fade show d-block"

        it "renders optional passkey setup through generated registration and overlay contracts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Dialog Venue"
                user <- createUserRecord "passkey-dialog@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams ShowPasskeySetupDialogAction [("successRedirect", "/EditProfile?section=security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` (cs canonicalOverlayDom.overlayDialogMountAttribute)
                response `responseBodyShouldContain` "Set up faster sign-in"
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyRegistrationAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyFlowConfigAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyActionButtonAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyDeviceNameAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyStatusAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyRecoveryAttribute
                response `responseBodyShouldContain` "&quot;beginUrl&quot;:&quot;/BeginPasskeyRegistration&quot;"
                response `responseBodyShouldContain` "&quot;finishUrl&quot;:&quot;/FinishPasskeyRegistration&quot;"
                response `responseBodyShouldContain` "&quot;successRedirect&quot;:&quot;/EditProfile?section=security&quot;"
                response `responseBodyShouldContain` "Save this recovery code now."
                response `responseBodyShouldContain` "This code is shown once and can be used if you lose access to your passkey."
                response `responseBodyShouldContain` "I have saved it"
                response `responseBodyShouldNotContain` "Create a passkey for admin access"
                response `responseBodyShouldNotContain` "js-passkey-"
                response `responseBodyShouldNotContain` "data-begin-url"
                response `responseBodyShouldNotContain` "data-finish-url"
                response `responseBodyShouldNotContain` "data-status-id"
                response `responseBodyShouldNotContain` "data-success-redirect"

        it "keeps roster access available across the no-passkey venue-role matrix" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Optional Roster Passkey Venue"
                admin <- createUserRecord "optional-roster-admin@example.com" "admin" True
                owner <- createUserRecord "optional-roster-owner@example.com" "admin" True
                worker <- createUserRecord "optional-roster-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue worker Worker

                responses <-
                    forM [("admin", admin), ("owner", owner), ("worker", worker)] \(role, user) -> do
                        response <- withUserAndCurrentVenue user venue.id do
                            callAction RosterWeeksAction
                        pure (role, response)

                map (\(role, response) -> (role, Wai.responseStatus response)) responses
                    `shouldBe` [("admin", status302), ("owner", status302), ("worker", status302)]
                map
                    (\(role, response) ->
                        ( role
                        , lookup HTTP.hLocation (responseHeaders response)
                            |> maybe False ("http://localhost/ShowRosterWeek?weekOffset=" `ByteString.isPrefixOf`)
                        )
                    )
                    responses
                    `shouldBe` [("admin", True), ("owner", True), ("worker", True)]

        it "requires passkey verification before venue admin pages when a passkey exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Step Up Venue"
                user <- createUserRecord "admin-step-up@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Admin security key"

                withUserAndCurrentVenue user venue.id do
                    response <- callAction AdminAction
                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

                    stepUpResponse <- callAction PasskeyStepUpAction
                    stepUpResponse `responseStatusShouldBe` status200
                    stepUpResponse `responseBodyShouldContain` "Verify with a passkey"
                    stepUpResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyLoginAttribute
                    stepUpResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyFlowConfigAttribute
                    stepUpResponse `responseBodyShouldContain` "&quot;beginUrl&quot;:&quot;/BeginPasskeyStepUpAuthentication&quot;"
                    stepUpResponse `responseBodyShouldContain` "&quot;finishUrl&quot;:&quot;/FinishPasskeyStepUpAuthentication&quot;"
                    stepUpResponse `responseBodyShouldContain` "&quot;successRedirect&quot;:&quot;/RosterWeeks&quot;"
                    stepUpResponse `responseBodyShouldContain` "Can't access your passkey?"
                    stepUpResponse `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                    stepUpResponse `responseBodyShouldNotContain` "Recovery code"

                    dialogResponse <- callAction ShowPasskeyRecoveryCodeDialogAction
                    dialogResponse `responseStatusShouldBe` status200
                    dialogResponse `responseBodyShouldContain` "Recover Passkey Access"
                    dialogResponse `responseBodyShouldContain` "Use recovery code"
                    dialogResponse `responseBodyShouldContain` "action=\"/UsePasskeyRecoveryCode\""

        it "audits failed passkey step-up attempts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Step Up Audit Venue"
                user <- createUserRecord "admin-step-up-audit@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin

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
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction FinishPasskeyStepUpAuthenticationAction

                response `responseStatusShouldBe` status422
                response `responseBodyShouldContain` "This passkey request has expired. Please try again."

        it "rejects passkey step-up finishes that do not send JSON" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Step Up JSON Venue"
                user <- createUserRecord "admin-step-up-json@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
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

        it "enforces the privileged passkey freshness boundary through admin middleware" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Passkey Freshness Venue"
                user <- createUserRecord "admin-passkey-freshness@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Admin passkey"
                now <- getCurrentTime
                let sessionFor verifiedAt =
                        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                        , (currentVenueSessionKey, Serialize.encode venue.id)
                        , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                        , (passkeyVerifiedAtSessionKey, Serialize.encode verifiedAt)
                        ]

                currentResponse <- withSessionValues (sessionFor (formatPasskeyVerifiedAt now)) do
                    callAction AdminAction
                twentyMinuteResponse <- withSessionValues (sessionFor (formatPasskeyVerifiedAt (addUTCTime (negate (20 * 60)) now))) do
                    callAction AdminAction
                expiredResponse <- withSessionValues (sessionFor "0") do
                    callAction AdminAction

                Wai.responseStatus currentResponse `shouldBe` status200
                Wai.responseStatus twentyMinuteResponse `shouldBe` status200
                Wai.responseStatus expiredResponse `shouldBe` status302
                lookup HTTP.hLocation (responseHeaders expiredResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "requires passkey setup after promotion when opening admin pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Promoted Admin Passkey Venue"
                user <- createUserRecord "promoted-admin@example.com" "staff" True
                membership <- createVenueMembershipRecord venue user Worker
                _ <- membership
                    |> set #venueRole (VenueAdmin)
                    |> updateRecord

                response <- withUserAndCurrentVenue user venue.id do
                    callAction AdminAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeySetup"

        it "requires fresh passkey verification before adding another admin passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Additional Admin Passkey Venue"
                user <- createUserRecord "additional-admin-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Existing admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction BeginPasskeyRegistrationAction

                response `responseStatusShouldBe` status403
                response `responseBodyShouldContain` "Verify with your passkey before adding another passkey."
                response `responseBodyShouldContain` "\"tag\":\"redirect\""
                response `responseBodyShouldContain` "\"redirectTo\":\"/PasskeyStepUp\""

        it "accepts and consumes a one-time passkey recovery code" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Recovery Code Venue"
                user <- createUserRecord "recovery-code@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Existing admin passkey"
                recoveryCode <- newRecord @PasskeyRecoveryCode
                    |> set #userId (unpackId user.id)
                    |> set #codeHash (hashRecoveryCode "abcd-efgh-ijkl-mnop")
                    |> createRecord

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "ABCD EFGH IJKL MNOP")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeySetup"
                consumedCode <- fetch recoveryCode.id
                consumedCode.usedAt `shouldSatisfy` isJust

                reuseResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "ABCD-EFGH-IJKL-MNOP")]

                reuseResponse `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders reuseResponse) `shouldBe` Just "http://localhost/PasskeyStepUp"

        it "routes super-admin recovery code users back to support passkey setup" $ withContext do
            withCleanDb do
                founder <- createUserRecordWithPlatformRole "support-recovery-code@example.com" "staff" (Just SuperAdmin) True
                _ <- createTestPasskeyRecord founder "Existing support passkey"
                _ <- newRecord @PasskeyRecoveryCode
                    |> set #userId (unpackId founder.id)
                    |> set #codeHash (hashRecoveryCode "support-recovery-code")
                    |> createRecord

                response <- withUser founder do
                    callActionWithParams UsePasskeyRecoveryCodeAction [("recoveryCode", "support recovery code")]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeySetup"
                now <- getCurrentTime
                supportResponse <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode founder.id)
                    , (passkeyRecoveryVerifiedUserSessionKey, Serialize.encode (inputValue founder.id :: Text))
                    , (passkeyRecoveryVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
                    ]
                    do
                        callAction SupportAction

                supportResponse `responseStatusShouldBe` status200
                supportResponse `responseBodyShouldContain` "Create passkey"
                supportResponse `responseBodyShouldContain` "hx-target=\"#dialog-overlay-mount\""
                supportResponse `responseBodyShouldContain` "successRedirect=%2FSupport"

                dialogResponse <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode founder.id)
                    , (passkeyRecoveryVerifiedUserSessionKey, Serialize.encode (inputValue founder.id :: Text))
                    , (passkeyRecoveryVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
                    ]
                    do
                        callActionWithParams ShowPasskeySetupDialogAction [("successRedirect", "/Support")]

                dialogResponse `responseStatusShouldBe` status200
                dialogResponse `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyRegistrationAttribute
                dialogResponse `responseBodyShouldContain` "&quot;successRedirect&quot;:&quot;/Support&quot;"
                dialogResponse `responseBodyShouldNotContain` "data-success-redirect"

        it "allows recovery-code verified admins to begin replacement passkey registration" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Recovery Registration Venue"
                user <- createUserRecord "recovery-registration@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
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
                _ <- createVenueMembershipRecord venue user VenueAdmin
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
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Existing admin passkey"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
                    callAction SendNewDevicePasskeySetupEmailAction

                response `responseStatusShouldBe` status302
                setupToken <- query @PasskeySetupToken |> fetchOne
                setupToken.userId `shouldBe` unpackId user.id
                setupToken.requestedByUserId `shouldBe` Just (unpackId user.id)
                setupToken.venueId `shouldBe` Just (unpackId venue.id)
                setupToken.purpose `shouldBe` "self_new_device"

        it "returns a verified super admin to Support after sending a new-device setup link" $ withContext do
            withCleanDb do
                setEnv "DISABLE_EMAIL_DELIVERY" "1"
                venue <- createVenueWithConfig "Support New Device Setup Venue"
                founder <- createUserRecordWithPlatformRole "support-new-device@example.com" "staff" (Just SuperAdmin) True
                _ <- createTestPasskeyRecord founder "Existing support passkey"

                response <- withPasskeyVerifiedUserAndCurrentVenue founder venue.id do
                    callAction SendNewDevicePasskeySetupEmailAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/Support"
                setupToken <- query @PasskeySetupToken |> fetchOne
                setupToken.userId `shouldBe` unpackId founder.id
                setupToken.venueId `shouldBe` Just (unpackId venue.id)

        it "returns an unverified super admin to Support after passkey step-up" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support New Device Step Up Venue"
                founder <- createUserRecordWithPlatformRole "support-new-device-step-up@example.com" "staff" (Just SuperAdmin) True
                _ <- createTestPasskeyRecord founder "Existing support passkey"

                response <- withUserAndCurrentVenue founder venue.id do
                    response <- callAction SendNewDevicePasskeySetupEmailAction
                    getSession @Text passkeyStepUpRedirectSessionKey `shouldReturn` Just "/Support"
                    pure response

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                query @PasskeySetupToken |> fetchCount `shouldReturn` 0

        it "returns super-admin passkey deletion step-up to Support" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Passkey Delete Step Up Venue"
                founder <- createUserRecordWithPlatformRole "support-passkey-delete-step-up@example.com" "staff" (Just SuperAdmin) True
                passkey <- createTestPasskeyRecord founder "Support passkey"
                _ <- createTestPasskeyRecord founder "Support backup passkey"

                response <- withUserAndCurrentVenue founder venue.id do
                    response <- callAction (DeletePasskeyAction passkey.id)
                    getSession @Text passkeyStepUpRedirectSessionKey `shouldReturn` Just "/Support"
                    pure response

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                query @Passkey |> filterWhere (#id, passkey.id) |> fetchExists `shouldReturn` True

        it "renders an active passkey setup link" $ withContext do
            withCleanDb do
                user <- createUserRecord "setup-link@example.com" "staff" True
                (_setupToken, rawToken) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing

                response <- callActionWithParams NewPasskeySetupAction [("token", cs rawToken)]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Set Up New Passkey"
                response `responseBodyShouldContain` "setup-link@example.com"
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyRegistrationAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyDeviceNameAttribute
                response `responseBodyShouldContain` cs canonicalPasskeyDom.passkeyRecoveryAttribute
                response `responseBodyShouldContain` "&quot;beginUrl&quot;:&quot;/BeginPasskeySetupRegistration?token="
                response `responseBodyShouldContain` "&quot;finishUrl&quot;:&quot;/FinishPasskeySetupRegistration&quot;"
                response `responseBodyShouldNotContain` "data-begin-url"
                response `responseBodyShouldNotContain` "data-finish-url"

        it "keeps exact passkey begin requests bodyless so setup-link tokens stay in the query string" $ withContext do
            sourceBytes <- ByteString.readFile "frontend/ts/app-passkeys.ts"
            let source = cs sourceBytes :: String
            source `shouldContain` "parsePasskeyRegistrationOptions"
            source `shouldContain` "body: hasPayload ? JSON.stringify(payload) : undefined"
            source `shouldNotContain` "JsonObject"
            source `shouldNotContain` "type PasskeyFinishResponse ="

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
                _ <- createVenueMembershipRecord venue owner VenueOwner
                _ <- createVenueMembershipRecord venue target Worker
                targetStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId target.id))
                    |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue owner venue.id do
                    callActionWithParams (SendStaffPasskeyRecoveryEmailAction targetStaff.id)
                        [ ("returnTo", "staff")
                        , ("weekOffset", "3")
                        ]

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/ShowRosterWeek?weekOffset=3"
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
                _ <- createVenueMembershipRecord venue pendingUser Worker
                _ <- createVenueMembershipRecord venue activeUser Worker

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
                _ <- createVenueMembershipRecord venue user Worker
                now <- getCurrentTime
                _ <- createTestPasskeyRecord user "Phone passkey"
                    >>= updateRecord . set #lastUsedAt (Just (addUTCTime (negate (35 * 24 * 60 * 60)) now))

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Phone passkey"
                response `responseBodyShouldContain` "less than 2 months ago"
                response `responseBodyShouldContain` "Delete"
                response `responseBodyShouldContain` "Email setup link for another device"
                response `responseBodyShouldContain` "Delete this passkey? You may need to verify with a passkey before it is removed."
                response `responseBodyShouldNotContain` "Created"
                response `responseBodyShouldNotContain` "Rename"
                response `responseBodyShouldNotContain` "id=\"passkey-management-name\""
                response `responseBodyShouldNotContain` "data-begin-url=\"/BeginPasskeyRegistration\""

        it "requires fresh passkey verification before an ordinary user deletes a passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Delete Step Up Worker Venue"
                user <- createUserRecord "passkey-delete-worker-step-up@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                passkey <- createTestPasskeyRecord user "Delete me later"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction passkey.id)

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"
                stillExists <- query @Passkey
                    |> filterWhere (#id, passkey.id)
                    |> fetchExists
                stillExists `shouldBe` True

        it "deletes an ordinary user's own passkey after fresh verification" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Delete Venue"
                user <- createUserRecord "passkey-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user Worker
                passkey <- createTestPasskeyRecord user "Delete me"

                response <- withPasskeyVerifiedUserAndCurrentVenue user venue.id do
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
                _ <- createVenueMembershipRecord venue user VenueAdmin
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
                _ <- createVenueMembershipRecord venue user VenueAdmin
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
