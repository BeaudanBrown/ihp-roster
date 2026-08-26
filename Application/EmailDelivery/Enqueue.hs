module Application.EmailDelivery.Enqueue
    ( EmailDeliveryEnqueueResult (..)
    , EmailDeliveryRequest (..)
    , emailDeliveryJobKind
    , enqueueEmailDelivery
    , enqueueEmailDeliveryWithStatus
    ) where

import Application.EmailDelivery.Persistence
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerPrelude

emailDeliveryJobKind :: Text
emailDeliveryJobKind = "email_delivery"

data EmailDeliveryRequest = EmailDeliveryRequest
    { mailKind             :: !Text
    , recipientAccountId   :: !UUID
    , recipientAddress     :: !Text
    , domainReferenceTable :: !Text
    , domainReferenceId    :: !UUID
    , semanticEventKey     :: !Text
    , requestedByUserId    :: !(Maybe UUID)
    , venueId              :: !(Maybe UUID)
    }
    deriving (Eq, Show)

data EmailDeliveryEnqueueResult
    = EnqueuedEmailDelivery !AppJob
    | ExistingEmailDelivery !AppJob
    deriving (Eq, Show)

enqueueEmailDelivery ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryRequest ->
    IO AppJob
enqueueEmailDelivery request =
    enqueueEmailDeliveryWithStatus request >>= \case
        EnqueuedEmailDelivery appJob -> pure appJob
        ExistingEmailDelivery appJob -> pure appJob

enqueueEmailDeliveryWithStatus ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryRequest ->
    IO EmailDeliveryEnqueueResult
enqueueEmailDeliveryWithStatus request = do
    let dedupeKey = emailDeliveryDedupeKey request
    inserted <-
        insertPermanentlyDeduplicatedEmailJob
            EmailDeliveryInsert
                { payload = emailDeliveryPayload request
                , requestedByUserId = request.requestedByUserId
                , venueId = request.venueId
                , relatedTable = request.domainReferenceTable
                , relatedId = request.domainReferenceId
                , dedupeKey
                }
    case inserted of
        [appJob] -> pure (EnqueuedEmailDelivery appJob)
        [] -> do
            existing <-
                query @AppJob
                    |> filterWhere (#jobKind, emailDeliveryJobKind)
                    |> filterWhere (#dedupeKey, Just dedupeKey)
                    |> orderByAsc #createdAt
                    |> fetchOneOrNothing
            case existing of
                Just appJob -> pure (ExistingEmailDelivery appJob)
                Nothing -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Email delivery dedupe conflict occurred without an existing job"
        _ -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "Email delivery insert unexpectedly returned multiple rows"

emailDeliveryPayload :: EmailDeliveryRequest -> Aeson.Value
emailDeliveryPayload request =
    Aeson.object
        [ "mailKind" Aeson..= request.mailKind
        , "recipientAccountId" Aeson..= request.recipientAccountId
        , "recipientAddress" Aeson..= request.recipientAddress
        , "domainReferenceId" Aeson..= request.domainReferenceId
        ]

emailDeliveryDedupeKey :: EmailDeliveryRequest -> Text
emailDeliveryDedupeKey request =
    Text.intercalate
        ":"
        [ "email-delivery"
        , request.mailKind
        , request.semanticEventKey
        , tshow request.recipientAccountId
        , recipientAddressDigest request.recipientAddress
        ]

recipientAddressDigest :: Text -> Text
recipientAddressDigest address =
    tshow
        ( Hash.hash
            (TextEncoding.encodeUtf8 (Text.toCaseFold (Text.strip address))) :: Hash.Digest Hash.SHA256
        )
