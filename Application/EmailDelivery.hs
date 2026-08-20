{-# LANGUAGE RankNTypes #-}

module Application.EmailDelivery
    ( EmailDeliveryRequest (..)
    , EmailDeliveryRuntime (..)
    , emailDeliveryJobKind
    , enqueueEmailDelivery
    , performEmailDeliveryJob
    , performEmailDeliveryJobWith
    ) where

import Application.EmailDelivery.Persistence
import Application.Feedback.Email (feedbackSubmittedMailKind,
                                   loadFeedbackNotificationMail)
import Application.Helper.EmailVerification (isEmailDeliveryDisabled)
import Application.Helper.Mail
import Control.Monad (void)
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerPrelude
import IHP.EnvVar (envOrDefault)
import IHP.FrameworkConfig (ConfigProvider, FrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail (sendMail)
import IHP.MailPrelude (BuildMail)

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

data EmailDeliveryPayload = EmailDeliveryPayload
    { payloadMailKind           :: !Text
    , payloadRecipientAccountId :: !UUID
    , payloadRecipientAddress   :: !Text
    , payloadDomainReferenceId  :: !UUID
    }
    deriving (Eq, Show)

instance Aeson.FromJSON EmailDeliveryPayload where
    parseJSON = Aeson.withObject "EmailDeliveryPayload" \object ->
        EmailDeliveryPayload
            <$> object Aeson..: "mailKind"
            <*> object Aeson..: "recipientAccountId"
            <*> object Aeson..: "recipientAddress"
            <*> object Aeson..: "domainReferenceId"

data EmailDeliveryRuntime = EmailDeliveryRuntime
    { deliveryIsDisabled :: !(IO Bool)
    , deliverMail        :: !(forall mail. BuildMail mail => mail -> IO ())
    }

enqueueEmailDelivery ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryRequest ->
    IO AppJob
enqueueEmailDelivery request = do
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
        [appJob] -> pure appJob
        [] -> do
            existing <-
                query @AppJob
                    |> filterWhere (#jobKind, emailDeliveryJobKind)
                    |> filterWhere (#dedupeKey, Just dedupeKey)
                    |> orderByAsc #createdAt
                    |> fetchOneOrNothing
            case existing of
                Just appJob -> pure appJob
                Nothing -> error "Email delivery dedupe conflict occurred without an existing job"
        _ -> error "Email delivery insert unexpectedly returned multiple rows"

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

performEmailDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performEmailDeliveryJob =
    performEmailDeliveryJobWith
        EmailDeliveryRuntime
            { deliveryIsDisabled = isEmailDeliveryDisabled
            , deliverMail = sendMail
            }

performEmailDeliveryJobWith ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    EmailDeliveryRuntime ->
    AppJob ->
    IO ()
performEmailDeliveryJobWith runtime appJob
    | appJob.payloadSchemaVersion /= 1 =
        fail ("Unsupported email delivery payload schema version: " <> cs (tshow appJob.payloadSchemaVersion))
    | otherwise =
        case Aeson.fromJSON appJob.payload of
            Aeson.Error parseError -> fail ("Invalid email delivery payload: " <> parseError)
            Aeson.Success payload -> performPayload runtime appJob payload

performPayload ::
    (?context :: context, ConfigProvider context, ?modelContext :: ModelContext) =>
    EmailDeliveryRuntime ->
    AppJob ->
    EmailDeliveryPayload ->
    IO ()
performPayload EmailDeliveryRuntime { deliveryIsDisabled, deliverMail } appJob payload = do
    AppMailSettings { .. } <- loadAppMailSettings
    appBaseUrl :: Text <- envOrDefault "APP_BASE_URL" "http://localhost:8000"
    disabled <- deliveryIsDisabled
    if disabled
        then completeEmailDelivery appJob payload "delivery_disabled" Nothing
        else case payload.payloadMailKind of
            mailKind | mailKind == feedbackSubmittedMailKind -> do
                maybeMail <-
                    loadFeedbackNotificationMail
                        payload.payloadRecipientAddress
                        payload.payloadDomainReferenceId
                        AppMailSettings { .. }
                        appBaseUrl
                case maybeMail of
                    Nothing -> completeEmailDelivery appJob payload "delivery_skipped" (Just "domain_reference_missing")
                    Just mail -> do
                        deliverMail mail
                        completeEmailDelivery appJob payload "sent" Nothing
            unknownKind -> fail ("Unknown email delivery mail kind: " <> cs unknownKind)

completeEmailDelivery ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    EmailDeliveryPayload ->
    Text ->
    Maybe Text ->
    IO ()
completeEmailDelivery appJob payload deliveryStatus maybeReason =
    void $
        appJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> set #result
                ( Aeson.object
                    ( [ "deliveryStatus" Aeson..= deliveryStatus
                      , "mailKind" Aeson..= payload.payloadMailKind
                      , "domainReferenceId" Aeson..= payload.payloadDomainReferenceId
                      ]
                        <> maybe [] (\reason -> ["reason" Aeson..= reason]) maybeReason
                    )
                )
            |> updateRecord
