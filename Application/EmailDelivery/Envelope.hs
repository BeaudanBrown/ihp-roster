-- | Durable envelope compatibility. V1 identities deliberately retain their
-- historical interpretation (including invitation IDs); never rewrite their
-- identity or dedupe namespace into the explicit external-recipient format.
module Application.EmailDelivery.Envelope
    ( EmailEnvelopeVersion (..)
    , emailEnvelopeVersionNumber
    , EmailDeliveryPayload (..)
    , ExternalRecipient (..)
    , ExternalEmailPayload (..)
    , externalEmailPayloadJson
    , externalEmailDedupeKey
    , emailRecipientAddressDigest
    ) where

import Application.Error.Parser (parserFailure)
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as Aeson
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Prelude (Show (..))

data EmailEnvelopeVersion = LegacyEnvelopeV1 | ExternalEnvelopeV2 deriving (Eq, Show)

emailEnvelopeVersionNumber :: EmailEnvelopeVersion -> Int
emailEnvelopeVersionNumber LegacyEnvelopeV1 = 1
emailEnvelopeVersionNumber ExternalEnvelopeV2 = 2

data EmailDeliveryPayload = EmailDeliveryPayload
    { payloadMailKind :: !Text
    , payloadRecipientAccountId :: !UUID
    , payloadRecipientAddress :: !Text
    , payloadDomainReferenceId :: !UUID
    } deriving (Eq, Show)

-- Preserve legacy parsing exactly; the field is not proof of account identity.
instance Aeson.FromJSON EmailDeliveryPayload where
    parseJSON = Aeson.withObject "EmailDeliveryPayload" \object ->
        EmailDeliveryPayload
            <$> object Aeson..: "mailKind"
            <*> object Aeson..: "recipientAccountId"
            <*> object Aeson..: "recipientAddress"
            <*> object Aeson..: "domainReferenceId"

data ExternalRecipient = VenueReportRecipient
    { externalRecipientId :: !UUID
    , externalVenueId :: !UUID
    , externalReportId :: !UUID
    } deriving (Eq, Show)

data ExternalEmailPayload = ExternalEmailPayload
    { externalMailKind :: !Text
    , externalRecipient :: !ExternalRecipient
    , externalRecipientAddress :: !Text
    , externalDomainReferenceId :: !UUID
    } deriving (Eq)

-- Debugging/exception output must not expose snapshotted external addresses.
instance Show ExternalEmailPayload where show _ = "ExternalEmailPayload <redacted>"

instance Aeson.FromJSON ExternalRecipient where
    parseJSON = Aeson.withObject "ExternalRecipient" \object -> do
        exactKeys ["kind", "recipientId", "venueId", "reportId"] object
        kind <- object Aeson..: "kind"
        unless (kind == ("venue-report-recipient" :: Text)) (parserFailure "unsupported recipient identity")
        VenueReportRecipient
            <$> object Aeson..: "recipientId"
            <*> object Aeson..: "venueId"
            <*> object Aeson..: "reportId"

instance Aeson.FromJSON ExternalEmailPayload where
    parseJSON = Aeson.withObject "ExternalEmailPayload" \object -> do
        exactKeys ["mailKind", "recipient", "recipientAddress", "domainReferenceId"] object
        kind <- object Aeson..: "mailKind"
        recipient <- object Aeson..: "recipient"
        address <- object Aeson..: "recipientAddress"
        reference <- object Aeson..: "domainReferenceId"
        unless (Text.length kind <= 100 && not (Text.null kind)) (parserFailure "invalid mail kind")
        unless (validAddressEnvelope address) (parserFailure "invalid recipient address")
        pure (ExternalEmailPayload kind recipient address reference)

externalEmailPayloadJson :: ExternalEmailPayload -> Aeson.Value
externalEmailPayloadJson payload = Aeson.object
    [ "mailKind" Aeson..= payload.externalMailKind
    , "recipient" Aeson..= Aeson.object
        [ "kind" Aeson..= ("venue-report-recipient" :: Text)
        , "recipientId" Aeson..= payload.externalRecipient.externalRecipientId
        , "venueId" Aeson..= payload.externalRecipient.externalVenueId
        , "reportId" Aeson..= payload.externalRecipient.externalReportId
        ]
    , "recipientAddress" Aeson..= payload.externalRecipientAddress
    , "domainReferenceId" Aeson..= payload.externalDomainReferenceId
    ]

-- Domain eligibility/address validation remains mandatory. This boundary only
-- rejects oversized/header-bearing addresses before dispatching untrusted jobs.
validAddressEnvelope :: Text -> Bool
validAddressEnvelope value =
    not (Text.null (Text.strip value)) && Text.length value <= 254
        && not (Text.any (`elem` ['\r', '\n', '\NUL']) value)

exactKeys :: [Text] -> Aeson.Object -> Aeson.Parser ()
exactKeys names object = unless
    (length names == KeyMap.size object && all (\name -> KeyMap.member (Key.fromText name) object) names)
    (parserFailure "unexpected envelope fields")

externalEmailDedupeKey :: Text -> ExternalEmailPayload -> Text
externalEmailDedupeKey semanticEventKey payload = Text.intercalate ":"
    [ "email-delivery-v2"
    , payload.externalMailKind
    , semanticEventKey
    , tshow payload.externalRecipient.externalVenueId
    , tshow payload.externalRecipient.externalReportId
    , tshow payload.externalRecipient.externalRecipientId
    , emailRecipientAddressDigest payload.externalRecipientAddress
    ]

emailRecipientAddressDigest :: Text -> Text
emailRecipientAddressDigest address =
    tshow (Hash.hash (TextEncoding.encodeUtf8 (Text.toCaseFold (Text.strip address))) :: Hash.Digest Hash.SHA256)
