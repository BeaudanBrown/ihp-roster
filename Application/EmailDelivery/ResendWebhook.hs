module Application.EmailDelivery.ResendWebhook
    ( ResendWebhookHeaders (..)
    , ResendWebhookResult (..)
    , handleResendWebhook
    , verifyResendWebhookAt
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (PersistedRuntimeInvariant), externalRuntimeInvariantFailure)
import Application.OperationalIncident
import Application.OperationalIncident.Types (operationalIncidentMailKind)
import qualified "crypton" Crypto.Hash as Hash
import qualified "crypton" Crypto.MAC.HMAC as HMAC
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.ByteArray as ByteArray
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Control.Monad (void)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Generated.Types
import IHP.ControllerPrelude
import Text.Read (readMaybe)

data ResendWebhookHeaders = ResendWebhookHeaders
    { svixId        :: !Text
    , svixTimestamp :: !Text
    , svixSignature :: !Text
    }
    deriving (Eq, Show)

data ResendWebhookPayload = ResendWebhookPayload
    { eventType       :: !Text
    , eventAt         :: !UTCTime
    , providerEmailId :: !Text
    , messageId       :: !(Maybe Text)
    }
    deriving (Eq, Show)

instance Aeson.FromJSON ResendWebhookPayload where
    parseJSON = Aeson.withObject "Resend webhook" \object -> do
        eventType <- object Aeson..: "type"
        eventAt <- object Aeson..: "created_at"
        dataObject <- object Aeson..: "data"
        Aeson.withObject "Resend webhook data" (\details ->
            ResendWebhookPayload eventType eventAt
                <$> details Aeson..: "email_id"
                <*> details Aeson..:? "message_id") dataObject

data ResendWebhookResult
    = ResendWebhookProcessed !EmailDeliveryWebhookEvent
    | ResendWebhookDuplicate !EmailDeliveryWebhookEvent
    | ResendWebhookUnknownMessage !EmailDeliveryWebhookEvent
    deriving (Eq, Show)

verifyResendWebhookAt ::
    UTCTime ->
    NominalDiffTime ->
    Text ->
    ResendWebhookHeaders ->
    LBS.ByteString ->
    Either Text ()
verifyResendWebhookAt now tolerance secret headers rawBody = do
    timestampSeconds <- maybe (Left "Invalid Svix timestamp") Right (readMaybe @Integer (cs headers.svixTimestamp))
    let signatureTime = posixSecondsToUTCTime (fromInteger timestampSeconds)
    unless (abs (diffUTCTime now signatureTime) <= tolerance) (Left "Svix timestamp is outside the replay window")
    key <- decodeWebhookSecret secret
    let signed =
            TextEncoding.encodeUtf8 headers.svixId
                <> "."
                <> TextEncoding.encodeUtf8 headers.svixTimestamp
                <> "."
                <> LBS.toStrict rawBody
    let expected = Base64.encode (ByteArray.convert (HMAC.hmac key signed :: HMAC.HMAC Hash.SHA256))
    let signatures = mapMaybe (Text.stripPrefix "v1,") (Text.words headers.svixSignature)
    unless (any (secureEquals expected . TextEncoding.encodeUtf8) signatures) (Left "Svix signature mismatch")

handleResendWebhook ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    Text ->
    ResendWebhookHeaders ->
    LBS.ByteString ->
    IO (Either Text ResendWebhookResult)
handleResendWebhook now secret headers rawBody =
    case verifyResendWebhookAt now 300 secret headers rawBody of
        Left message -> pure (Left message)
        Right () -> case Aeson.eitherDecode rawBody of
            Left _ -> pure (Left "Invalid Resend webhook payload")
            Right payload
                | payload.eventType `notElem` supportedEventTypes -> pure (Left "Unsupported Resend webhook event")
                | otherwise -> Right <$> processVerifiedWebhook now headers payload

processVerifiedWebhook ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    ResendWebhookHeaders ->
    ResendWebhookPayload ->
    IO ResendWebhookResult
processVerifiedWebhook now headers payload = do
    (result, changedState) <- withTransaction do
        lockWebhookEvent headers.svixId
        duplicate <-
            query @EmailDeliveryWebhookEvent
                |> filterWhere (#svixId, headers.svixId)
                |> fetchOneOrNothing
        case duplicate of
            Just event -> pure (ResendWebhookDuplicate event, Nothing)
            Nothing -> do
                maybeState <- findProviderState payload
                case maybeState of
                    Nothing -> do
                        event <- createWebhookEvent now headers payload "unknown_message"
                        pure (ResendWebhookUnknownMessage event, Nothing)
                    Just state -> do
                        let incomingStatus = providerStatusFor payload.eventType
                        let isOlder = maybe False (>= payload.eventAt) state.providerStatusAt
                        let outcome = if isOlder && isJust incomingStatus then "ignored_older_status" else "correlated"
                        event <- createWebhookEvent now headers payload outcome
                        updated <-
                            state
                                |> set #providerEmailId (Just payload.providerEmailId)
                                |> applyProviderStatus incomingStatus payload.eventAt isOlder
                                |> updateRecord
                        pure (ResendWebhookProcessed event, if isOlder then Nothing else Just updated)
    forM_ changedState reconcileProviderIncident
    pure result

lockWebhookEvent :: (?modelContext :: ModelContext) => Text -> IO ()
lockWebhookEvent eventId = do
    rows :: [Only Bool] <-
        unsafeSqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS resend_webhook_lock"
            (Only eventId)
    unless (rows == [Only True]) $
        externalRuntimeInvariantFailure PersistedRuntimeInvariant "Unable to lock Resend webhook event"

findProviderState ::
    (?modelContext :: ModelContext) =>
    ResendWebhookPayload ->
    IO (Maybe EmailDeliveryProviderState)
findProviderState payload = do
    byProvider <-
        query @EmailDeliveryProviderState
            |> filterWhere (#providerEmailId, Just payload.providerEmailId)
            |> fetchOneOrNothing
    case byProvider of
        Just state -> pure (Just state)
        Nothing -> case payload.messageId of
            Nothing -> pure Nothing
            Just messageId ->
                query @EmailDeliveryProviderState
                    |> filterWhere (#messageId, messageId)
                    |> fetchOneOrNothing

createWebhookEvent ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    ResendWebhookHeaders ->
    ResendWebhookPayload ->
    Text ->
    IO EmailDeliveryWebhookEvent
createWebhookEvent now headers payload outcome =
    newRecord @EmailDeliveryWebhookEvent
        |> set #svixId headers.svixId
        |> set #signatureTimestamp (posixSecondsToUTCTime (fromInteger (fromMaybe 0 (readMaybe @Integer (cs headers.svixTimestamp)))))
        |> set #eventType payload.eventType
        |> set #providerEmailId payload.providerEmailId
        |> set #messageId payload.messageId
        |> set #eventAt payload.eventAt
        |> set #receivedAt now
        |> set #processingOutcome outcome
        |> createRecord

applyProviderStatus ::
    Maybe Text ->
    UTCTime ->
    Bool ->
    EmailDeliveryProviderState ->
    EmailDeliveryProviderState
applyProviderStatus Nothing _ _ state = state
applyProviderStatus (Just _) _ True state = state
applyProviderStatus (Just status) eventAt False state =
    state
        |> set #providerStatus status
        |> set #providerStatusAt (Just eventAt)

reconcileProviderIncident ::
    (?modelContext :: ModelContext) =>
    EmailDeliveryProviderState ->
    IO ()
reconcileProviderIncident state = do
    appJob <- fetch (Id (unpackId state.emailDeliveryJobId) :: Id AppJob)
    let isIncidentNotification =
            AesonTypes.parseMaybe (Aeson.withObject "email payload" (Aeson..: "mailKind")) appJob.payload
                == Just operationalIncidentMailKind
    let active = state.providerStatus `elem` ["bounced", "complained", "failed", "suppressed"]
    let recovered = state.providerStatus == "delivered"
    unless isIncidentNotification $
        when (active || recovered) $
            void $
                reconcileOperationalIncident
                    IncidentObservation
                        { category = "email_delivery"
                        , scopeKey = "global"
                        , stableIdentity = tshow state.emailDeliveryJobId
                        , affectedSource = "resend"
                        , venueId = appJob.venueId
                        , observedAt = fromMaybe state.updatedAt state.providerStatusAt
                        , isActive = active
                        , severity = if state.providerStatus == "complained" then IncidentCritical else IncidentWarning
                        , impactKey = state.providerStatus
                        , impactRank = if state.providerStatus == "complained" then 30 else 20
                        , symptomCodes = [state.providerStatus]
                        , safeMetadata = Aeson.object ["emailDeliveryJobId" Aeson..= state.emailDeliveryJobId, "providerStatus" Aeson..= state.providerStatus]
                        }

providerStatusFor :: Text -> Maybe Text
providerStatusFor = \case
    "email.delivered" -> Just "delivered"
    "email.bounced" -> Just "bounced"
    "email.complained" -> Just "complained"
    "email.failed" -> Just "failed"
    "email.suppressed" -> Just "suppressed"
    "email.sent" -> Nothing
    _ -> Nothing

supportedEventTypes :: [Text]
supportedEventTypes =
    [ "email.sent"
    , "email.delivered"
    , "email.bounced"
    , "email.complained"
    , "email.failed"
    , "email.suppressed"
    ]

decodeWebhookSecret :: Text -> Either Text ByteString.ByteString
decodeWebhookSecret rawSecret = do
    encoded <- maybe (Left "Invalid Resend webhook secret") Right (Text.stripPrefix "whsec_" (Text.strip rawSecret))
    case Base64.decode (TextEncoding.encodeUtf8 encoded) of
        Left _ -> Left "Invalid Resend webhook secret"
        Right decoded -> Right decoded

secureEquals :: ByteString.ByteString -> ByteString.ByteString -> Bool
secureEquals left right = ByteArray.constEq left right
