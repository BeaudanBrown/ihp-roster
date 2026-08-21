module Test.AccountSecurityEmailSpec where

import Application.AccountSecurityEmail.Email
import Application.AccountSecurityEmail.Enqueue
import Application.AccountSecurityEmail.TokenCipher
import Application.AccountSecurityEmail.Types
import Application.Async.Queue (appJobMaxAttempts)
import Application.EmailDelivery
import Application.Helper.EmailVerification (issueEmailVerification)
import Application.Helper.Mail (loadAppMailSettings)
import Application.Helper.PasskeySetupTokens
import Application.Helper.PasswordResetTokens
import Config (config)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.Mail.Users.PasswordReset (PasswordResetMail (..))

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Account security email delivery" do
        it "keeps the ciphertext migration additive and leaves existing active tokens valid" $ withContext do
            migrationSql <- TextIO.readFile "Application/Migration/1788003000.sql"
            migrationSql `shouldSatisfy` Text.isInfixOf "ADD COLUMN delivery_token_ciphertext TEXT DEFAULT NULL"
            migrationSql `shouldSatisfy` Text.isInfixOf "passkey_setup_tokens"
            migrationSql `shouldSatisfy` Text.isInfixOf "password_reset_tokens"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "NOT NULL"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "DELETE"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "UPDATE"

        it "atomically persists verification tokens and shared envelopes without copying the token or URL" $ withContext do
            withCleanDb do
                user <- createUserRecord "verification-envelope@example.com" "staff" False

                token <- issueEmailVerification user

                appJob <- query @AppJob
                    |> filterWhere (#relatedTable, Just "email_verification_tokens")
                    |> filterWhere (#relatedId, Just (unpackId token.id))
                    |> fetchOne
                appJob.jobKind `shouldBe` emailDeliveryJobKind
                jobJsonText appJob.payload "mailKind" `shouldBe` Just emailVerificationMailKind
                jobJsonText appJob.payload "recipientAddress" `shouldBe` Just user.email
                tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf token.token
                tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf "VerifyEmail"

        it "rolls back token persistence and enqueue together" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Credential Atomic Venue"
                admin <- createUserRecord "credential-atomic-admin@example.com" "admin" True
                target <- createUserRecord "credential-atomic-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue target Worker

                result <- try
                    ( withTransaction do
                        _ <- issuePasswordResetToken target admin.id venue.id
                        ioError (userError "rollback after enqueue")
                    ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft
                query @PasswordResetToken |> fetchCount `shouldReturn` 0
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount `shouldReturn` 0

        it "stores password and passkey delivery secrets authenticated-encrypted outside the envelope" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Credential Encryption Venue"
                admin <- createUserRecord "credential-encryption-admin@example.com" "admin" True
                target <- createUserRecord "credential-encryption-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue target Worker

                (passwordToken, passwordRawToken) <- issuePasswordResetToken target admin.id venue.id
                (passkeyToken, passkeyRawToken) <- issuePasskeySetupToken StaffNewDevicePasskeySetup target (Just admin.id) (Just venue.id)

                forM_
                    [ (passwordToken.deliveryTokenCiphertext, passwordRawToken)
                    , (passkeyToken.deliveryTokenCiphertext, passkeyRawToken)
                    ]
                    \(maybeCiphertext, rawToken) -> case maybeCiphertext of
                        Nothing -> expectationFailure "new token must retain an encrypted delivery projection"
                        Just ciphertext -> do
                            ciphertext `shouldSatisfy` not . Text.isInfixOf rawToken
                            decryptAccountSecurityDeliveryToken ciphertext `shouldReturn` Right rawToken
                            let tampered = Text.dropEnd 1 ciphertext <> if Text.isSuffixOf "A" ciphertext then "B" else "A"
                            decryptAccountSecurityDeliveryToken tampered >>= (`shouldSatisfy` isLeft)

                jobs <- query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetch
                length jobs `shouldBe` 2
                forM_ jobs \appJob -> do
                    tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf passwordRawToken
                    tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf passkeyRawToken
                    tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf "token="

        it "generates current one-time URLs only from eligible token records at delivery" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Credential Projection Venue"
                admin <- createUserRecord "credential-projection-admin@example.com" "admin" True
                target <- createUserRecord "credential-projection-target@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue target Worker
                (token, _) <- issuePasswordResetToken target admin.id venue.id
                settings <- loadAppMailSettings

                projection <- loadAccountSecurityMail passwordResetMailKind (unpackId target.id) target.email (unpackId token.id) (Just (unpackId venue.id)) settings "https://app.example"

                case projection of
                    AccountSecurityMailReady (PasswordResetDelivery mail) -> do
                        mail.resetUrl `shouldSatisfy` Text.isPrefixOf "https://app.example/NewPasswordReset?token="
                        mail.resetUrl `shouldSatisfy` (/= "https://app.example/NewPasswordReset?token=")
                    _ -> expectationFailure "eligible password reset must project a mail"

        it "sends through the shared runtime once, clears delivery secret, and permanently deduplicates" $ withContext do
            withCleanDb do
                user <- createUserRecord "passkey-shared-runtime@example.com" "staff" True
                (token, _) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId token.id)) |> fetchOne

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailRuntime appJob

                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "sent"
                completedToken <- fetch token.id
                completedToken.deliveryTokenCiphertext `shouldBe` Nothing
                repeated <- enqueuePasskeySetupDelivery completedToken
                case repeated of
                    ExistingEmailDelivery existing -> existing.id `shouldBe` appJob.id
                    EnqueuedEmailDelivery _ -> expectationFailure "completed token event must remain permanently deduplicated"
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount `shouldReturn` 1

        it "projects explicit skip reasons for consumed, expired, deactivated, and changed-address tokens" $ withContext do
            withCleanDb do
                settings <- loadAppMailSettings
                now <- getCurrentTime

                consumedUser <- createUserRecord "credential-consumed@example.com" "staff" False
                consumedToken <- issueEmailVerification consumedUser
                _ <- consumedToken |> set #consumedAt (Just now) |> updateRecord
                consumedProjection <- loadAccountSecurityMail emailVerificationMailKind (unpackId consumedUser.id) consumedUser.email (unpackId consumedToken.id) Nothing settings "https://app.example"
                accountSecurityProjectionReason consumedProjection `shouldBe` Just "token_consumed"

                expiredUser <- createUserRecord "credential-expired@example.com" "staff" True
                (expiredToken, _) <- issuePasskeySetupToken SelfNewDevicePasskeySetup expiredUser (Just expiredUser.id) Nothing
                _ <- expiredToken |> set #expiresAt (addUTCTime (-60) now) |> updateRecord
                expiredProjection <- loadAccountSecurityMail passkeySetupMailKind (unpackId expiredUser.id) expiredUser.email (unpackId expiredToken.id) Nothing settings "https://app.example"
                accountSecurityProjectionReason expiredProjection `shouldBe` Just "token_expired"

                deactivatedUser <- createUserRecord "credential-deactivated@example.com" "staff" False
                deactivatedToken <- issueEmailVerification deactivatedUser
                _ <- deactivatedUser |> set #deactivatedAt (Just now) |> updateRecord
                deactivatedProjection <- loadAccountSecurityMail emailVerificationMailKind (unpackId deactivatedUser.id) deactivatedUser.email (unpackId deactivatedToken.id) Nothing settings "https://app.example"
                accountSecurityProjectionReason deactivatedProjection `shouldBe` Just "recipient_account_deactivated"

                changedUser <- createUserRecord "credential-before-change@example.com" "staff" False
                changedToken <- issueEmailVerification changedUser
                _ <- changedUser |> set #email "credential-after-change@example.com" |> updateRecord
                changedProjection <- loadAccountSecurityMail emailVerificationMailKind (unpackId changedUser.id) changedToken.sentToEmail (unpackId changedToken.id) Nothing settings "https://app.example"
                accountSecurityProjectionReason changedProjection `shouldBe` Just "recipient_email_changed"

        it "truthfully skips obsolete administrator authority" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Credential Eligibility Venue"
                admin <- createUserRecord "credential-eligibility-admin@example.com" "admin" True
                target <- createUserRecord "credential-eligibility-target@example.com" "staff" True
                adminMembership <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord venue target Worker
                (token, _) <- issuePasswordResetToken target admin.id venue.id
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId token.id)) |> fetchOne
                now <- getCurrentTime
                _ <- adminMembership |> set #isActive False |> set #archivedAt (Just now) |> updateRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailRuntime appJob

                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "delivery_skipped"
                jobJsonText completedJob.result "reason" `shouldBe` Just "recipient_authority_obsolete"
                completedToken <- fetch token.id
                completedToken.deliveryTokenCiphertext `shouldBe` Nothing

        it "completes disabled eligible delivery without transport or later replay" $ withContext do
            withCleanDb do
                user <- createUserRecord "verification-disabled@example.com" "staff" False
                token <- issueEmailVerification user
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId token.id)) |> fetchOne

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith disabledEmailRuntime appJob

                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "delivery_disabled"
                repeated <- enqueueEmailVerificationDelivery token user
                case repeated of
                    ExistingEmailDelivery existing -> existing.id `shouldBe` appJob.id
                    EnqueuedEmailDelivery _ -> expectationFailure "disabled token event must not replay later"

        it "clears encrypted delivery material after final shared failure without storing provider detail" $ withContext do
            withCleanDb do
                user <- createUserRecord "passkey-final-failure@example.com" "staff" True
                (token, _) <- issuePasskeySetupToken SelfNewDevicePasskeySetup user (Just user.id) Nothing
                queuedJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId token.id)) |> fetchOne
                finalJob <- queuedJob |> set #attemptsCount appJobMaxAttempts |> updateRecord

                failure <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    try (performEmailDeliveryJobWith failingEmailRuntime finalJob) :: IO (Either SomeException ())
                failure `shouldSatisfy` isLeft
                handleEmailDeliveryFailureAfterFinalAttempt finalJob

                failedToken <- fetch token.id
                failedToken.deliveryTokenCiphertext `shouldBe` Nothing
                tshow failedToken `shouldSatisfy` not . Text.isInfixOf "provider-secret@example.com"

enabledEmailRuntime :: EmailDeliveryRuntime
enabledEmailRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail = \_ -> pure ()
        }

disabledEmailRuntime :: EmailDeliveryRuntime
disabledEmailRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure True
        , deliverMail = \_ -> expectationFailure "disabled delivery must not invoke transport"
        }

accountSecurityProjectionReason :: AccountSecurityMailProjection -> Maybe Text
accountSecurityProjectionReason = \case
    AccountSecurityMailSkipped reason -> Just reason
    AccountSecurityMailReady _        -> Nothing

jobJsonText :: Aeson.Value -> Text -> Maybe Text
jobJsonText value key =
    AesonTypes.parseMaybe (Aeson.withObject "account security email JSON" (Aeson..: AesonKey.fromText key)) value

failingEmailRuntime :: EmailDeliveryRuntime
failingEmailRuntime =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail = \_ -> ioError (userError "provider-secret@example.com")
        }
