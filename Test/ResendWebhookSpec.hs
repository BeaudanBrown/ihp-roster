module Test.ResendWebhookSpec where

import Application.EmailDelivery.Correlation
import Application.EmailDelivery.Resend (requestOperationalEmailResend)
import Application.EmailDelivery.ResendWebhook
import Application.OperationalIncident
import qualified "crypton" Crypto.Hash as Hash
import qualified "crypton" Crypto.MAC.HMAC as HMAC
import qualified Data.Aeson as Aeson
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import Data.Either (isRight)
import qualified Data.Text.Encoding as TextEncoding
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Resend webhook delivery visibility" do
        it "verifies raw-body signatures and rejects replay-window violations" $ \_ -> do
            now <- getCurrentTime
            let body = "{\"type\":\"email.sent\"}"
            let (secret, headers) = signedFixture now body "msg_signature"
            verifyResendWebhookAt now 300 secret headers body `shouldBe` Right ()
            verifyResendWebhookAt (addUTCTime 301 now) 300 secret headers body
                `shouldBe` Left "Svix timestamp is outside the replay window"
            verifyResendWebhookAt now 300 secret (headers { svixSignature = "v1,invalid" }) body
                `shouldBe` Left "Svix signature mismatch"

        it "correlates by deterministic Message-ID, deduplicates Svix IDs and ignores older status" $ withContext do
            withCleanDb do
                appJob <- newRecord @AppJob |> set #jobKind "email_delivery" |> createRecord
                state <- prepareProviderCorrelation appJob
                now <- getCurrentTime
                let deliveredBody = webhookBody "email.delivered" now "email_123" (Just state.messageId)
                let (secret, deliveredHeaders) = signedFixture now deliveredBody "msg_delivered"
                first <- handleResendWebhook now secret deliveredHeaders deliveredBody
                first `shouldSatisfy` isRight

                duplicate <- handleResendWebhook now secret deliveredHeaders deliveredBody
                case duplicate of
                    Right (ResendWebhookDuplicate _) -> pure ()
                    _ -> expectationFailure "expected duplicate webhook result"

                let older = addUTCTime (-60) now
                let failedBody = webhookBody "email.failed" older "email_123" (Just state.messageId)
                let (_, failedHeaders) = signedFixture now failedBody "msg_older"
                _ <- handleResendWebhook now secret failedHeaders failedBody
                refreshed <- query @EmailDeliveryProviderState |> fetchOne
                refreshed.providerStatus `shouldBe` "delivered"
                events <- query @EmailDeliveryWebhookEvent |> orderByAsc #receivedAt |> fetch
                map (.processingOutcome) events `shouldMatchList` ["correlated", "ignored_older_status"]

        it "retains unknown provider IDs without recipient/time correlation" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                let body = webhookBody "email.bounced" now "unknown_email" Nothing
                let (secret, headers) = signedFixture now body "msg_unknown"
                result <- handleResendWebhook now secret headers body
                case result of
                    Right (ResendWebhookUnknownMessage event) -> event.processingOutcome `shouldBe` "unknown_message"
                    _ -> expectationFailure "expected unknown-message result"
                query @EmailDeliveryProviderState |> fetchCount >>= (`shouldBe` 0)

        it "permits only audited operational resends by an active super admin" $ withContext do
            withCleanDb do
                actor <- createUserRecordWithPlatformRole "resend-actor@example.com" "staff" (Just SuperAdmin) True
                ordinary <- createUserRecord "resend-ordinary@example.com" "staff" True
                now <- getCurrentTime
                _ <- reconcileOperationalIncident (incidentObservation now)
                original <- query @AppJob |> filterWhere (#jobKind, "email_delivery" :: Text) |> fetchOne
                disabled <-
                    original
                        |> set #status JobStatusSucceeded
                        |> set #result (Aeson.object ["deliveryStatus" Aeson..= ("delivery_disabled" :: Text)])
                        |> updateRecord

                requestOperationalEmailResend ordinary disabled "operator reviewed" `shouldReturn` Nothing
                replacement <- requestOperationalEmailResend actor disabled "operator reviewed"
                replacement `shouldSatisfy` isJust
                [audit] <- query @EmailDeliveryResendRequest |> fetch
                audit.originalEmailDeliveryJobId `shouldBe` unpackId original.id
                audit.requestedByUserId `shouldBe` unpackId actor.id
                audit.replacementEmailDeliveryJobId `shouldBe` (unpackId . (.id) <$> replacement)

        it "records an adverse provider incident and recovery from authoritative events" $ withContext do
            withCleanDb do
                _ <- createUserRecordWithPlatformRole "provider-admin@example.com" "staff" (Just SuperAdmin) True
                appJob <- newRecord @AppJob |> set #jobKind "email_delivery" |> createRecord
                state <- prepareProviderCorrelation appJob
                now <- getCurrentTime
                let failedBody = webhookBody "email.failed" now "email_recovery" (Just state.messageId)
                let (secret, failedHeaders) = signedFixture now failedBody "msg_failed"
                _ <- handleResendWebhook now secret failedHeaders failedBody
                incident <- query @OperationalIncident |> filterWhere (#category, "email_delivery" :: Text) |> fetchOne
                incident.state `shouldBe` "open"

                let deliveredAt = addUTCTime 60 now
                let deliveredBody = webhookBody "email.delivered" deliveredAt "email_recovery" (Just state.messageId)
                let (_, deliveredHeaders) = signedFixture deliveredAt deliveredBody "msg_recovered"
                _ <- handleResendWebhook deliveredAt secret deliveredHeaders deliveredBody
                recovered <- fetch incident.id
                recovered.state `shouldBe` "resolved"

incidentObservation :: UTCTime -> IncidentObservation
incidentObservation now =
    IncidentObservation
        { category = "test_delivery"
        , scopeKey = "global"
        , stableIdentity = "resend-fixture"
        , affectedSource = "fixture"
        , venueId = Nothing
        , observedAt = now
        , isActive = True
        , severity = IncidentWarning
        , impactKey = "failed"
        , impactRank = 10
        , symptomCodes = ["failed"]
        , safeMetadata = Aeson.object []
        }

webhookBody :: Text -> UTCTime -> Text -> Maybe Text -> LBS.ByteString
webhookBody eventType createdAt emailId messageId =
    Aeson.encode $
        Aeson.object
            [ "type" Aeson..= eventType
            , "created_at" Aeson..= createdAt
            , "data" Aeson..= Aeson.object ["email_id" Aeson..= emailId, "message_id" Aeson..= messageId]
            ]

signedFixture :: UTCTime -> LBS.ByteString -> Text -> (Text, ResendWebhookHeaders)
signedFixture now body messageId =
    let key = "test-resend-webhook-key"
        encodedSecret = TextEncoding.decodeUtf8 (Base64.encode key)
        secret = "whsec_" <> encodedSecret
        timestamp = tshow (floor (utcTimeToPOSIXSeconds now) :: Integer)
        signed = TextEncoding.encodeUtf8 messageId <> "." <> TextEncoding.encodeUtf8 timestamp <> "." <> LBS.toStrict body
        signature = TextEncoding.decodeUtf8 (Base64.encode (ByteArray.convert (HMAC.hmac key signed :: HMAC.HMAC Hash.SHA256)))
     in (secret, ResendWebhookHeaders { svixId = messageId, svixTimestamp = timestamp, svixSignature = "v1," <> signature })
