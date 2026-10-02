module Test.EmailEnvelopeSpec where

import Application.EmailDelivery.Envelope
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import Test.Hspec

externalPayload :: ExternalEmailPayload
externalPayload = ExternalEmailPayload
    "daysheet_report_v1"
    (VenueReportRecipient UUID.nil (UUID.fromWords 0 0 0 1) (UUID.fromWords 0 0 0 2))
    "report@example.test"
    (UUID.fromWords 0 0 0 3)

tests :: Spec
tests = describe "Shared email envelope compatibility" do
    it "retains the legacy recipient field without reinterpreting invitation IDs" do
        let payload = Aeson.object
                [ "mailKind" Aeson..= ("venue_invitation_v1" :: Text)
                , "recipientAccountId" Aeson..= UUID.nil
                , "recipientAddress" Aeson..= ("invite@example.test" :: Text)
                , "domainReferenceId" Aeson..= UUID.nil
                ]
        Aeson.fromJSON payload `shouldBe` Aeson.Success (EmailDeliveryPayload "venue_invitation_v1" UUID.nil "invite@example.test" UUID.nil)
        emailEnvelopeVersionNumber LegacyEnvelopeV1 `shouldBe` 1
        emailEnvelopeVersionNumber ExternalEnvelopeV2 `shouldBe` 2
    it "round-trips explicit venue/report recipient identity in the new envelope" do
        Aeson.fromJSON (externalEmailPayloadJson externalPayload) `shouldBe` Aeson.Success externalPayload
    it "rejects account-identity ambiguity and header-bearing destinations" do
        let Aeson.Object fields = externalEmailPayloadJson externalPayload
        let ambiguous = Aeson.Object (KeyMap.insert "recipientAccountId" (Aeson.toJSON UUID.nil) fields)
        case Aeson.fromJSON ambiguous :: Aeson.Result ExternalEmailPayload of
            Aeson.Error _ -> pure ()
            Aeson.Success _ -> expectationFailure "accepted a mixed identity envelope"
        let invalid = externalEmailPayloadJson (externalPayload { externalRecipientAddress = "report@example.test\r\nBcc: other@example.test" })
        case Aeson.fromJSON invalid :: Aeson.Result ExternalEmailPayload of
            Aeson.Error _ -> pure ()
            Aeson.Success _ -> expectationFailure "accepted mail headers in an address"
    it "separates new dedupe identity from legacy jobs and every report/recipient" do
        let original = externalEmailDedupeKey "capture-1" externalPayload
        Text.isPrefixOf "email-delivery-v2:" original `shouldBe` True
        Text.isInfixOf "report@example.test" original `shouldBe` False
        externalEmailDedupeKey "capture-1" (externalPayload { externalRecipientAddress = " REPORT@example.test " }) `shouldBe` original
        let recipient = externalPayload.externalRecipient
        externalEmailDedupeKey "capture-1" (externalPayload { externalRecipient = recipient { externalReportId = UUID.nil } }) `shouldNotBe` original
        externalEmailDedupeKey "capture-2" externalPayload `shouldNotBe` original
        externalEmailDedupeKey "capture-1" (externalPayload { externalRecipient = recipient { externalRecipientId = UUID.fromWords 0 0 0 99 } }) `shouldNotBe` original
    it "redacts external destinations from diagnostic rendering" do
        Text.isInfixOf "report@example.test" (tshow externalPayload) `shouldBe` False
