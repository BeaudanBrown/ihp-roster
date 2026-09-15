module Application.EmailDelivery.Resend
    ( requestOperationalEmailResend
    ) where

import Application.EmailDelivery.Enqueue
import Application.OperationalIncident.Types (operationalIncidentMailKind)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusFailed, JobStatusTimedOut))

data ResendPayload = ResendPayload
    { mailKind           :: !Text
    , recipientAccountId :: !UUID
    , recipientAddress   :: !Text
    , domainReferenceId  :: !UUID
    }

instance Aeson.FromJSON ResendPayload where
    parseJSON = Aeson.withObject "email delivery payload" \object ->
        ResendPayload
            <$> object Aeson..: "mailKind"
            <*> object Aeson..: "recipientAccountId"
            <*> object Aeson..: "recipientAddress"
            <*> object Aeson..: "domainReferenceId"

requestOperationalEmailResend ::
    (?modelContext :: ModelContext) =>
    User ->
    AppJob ->
    Text ->
    IO (Maybe AppJob)
requestOperationalEmailResend actor original rawReason = do
    let reason = Text.strip rawReason
    if not (eligibleActor actor) || Text.null reason || Text.length reason > 240
        then pure Nothing
        else case Aeson.fromJSON original.payload of
            Aeson.Error _ -> pure Nothing
            Aeson.Success payload
                | not (eligibleOriginal original payload) -> pure Nothing
                | otherwise -> do
                    recipient <-
                        query @User
                            |> filterWhere (#id, Id payload.recipientAccountId)
                            |> filterWhere (#platformRole, Just SuperAdmin)
                            |> filterWhere (#deactivatedAt, Nothing)
                            |> fetchOneOrNothing
                    retryable <- originalHasVisibleFailure original
                    relationship <-
                        query @OperationalIncidentEventRecipient
                            |> filterWhere (#operationalIncidentEventId, payload.domainReferenceId)
                            |> filterWhere (#recipientUserId, payload.recipientAccountId)
                            |> filterWhere (#emailDeliveryJobId, unpackId original.id)
                            |> fetchOneOrNothing
                    case (recipient, retryable, relationship) of
                        (Just eligibleRecipient, True, Just _) -> Just <$> createAuditedResend actor original payload eligibleRecipient reason
                        _ -> pure Nothing

createAuditedResend ::
    (?modelContext :: ModelContext) =>
    User ->
    AppJob ->
    ResendPayload ->
    User ->
    Text ->
    IO AppJob
createAuditedResend actor original payload recipient reason = withTransaction do
    request <-
        newRecord @EmailDeliveryResendRequest
            |> set #originalEmailDeliveryJobId (unpackId original.id)
            |> set #replacementEmailDeliveryJobId Nothing
            |> set #requestedByUserId (unpackId actor.id)
            |> set #reason reason
            |> createRecord
    replacement <-
        enqueueEmailDelivery
            EmailDeliveryRequest
                { mailKind = operationalIncidentMailKind
                , recipientAccountId = unpackId recipient.id
                , recipientAddress = recipient.email
                , domainReferenceTable = "operational_incident_events"
                , domainReferenceId = payload.domainReferenceId
                , semanticEventKey = "audited-resend:" <> tshow (unpackId request.id)
                , requestedByUserId = Just (unpackId actor.id)
                , venueId = original.venueId
                }
    _ <- request |> set #replacementEmailDeliveryJobId (Just (unpackId replacement.id)) |> updateRecord
    pure replacement

eligibleActor :: User -> Bool
eligibleActor actor = actor.platformRole == Just SuperAdmin && isNothing actor.deactivatedAt

eligibleOriginal :: AppJob -> ResendPayload -> Bool
eligibleOriginal original payload =
    original.jobKind == emailDeliveryJobKind
        && payload.mailKind == operationalIncidentMailKind
        && original.relatedTable == Just "operational_incident_events"
        && original.relatedId == Just payload.domainReferenceId

originalHasVisibleFailure :: (?modelContext :: ModelContext) => AppJob -> IO Bool
originalHasVisibleFailure original = do
    provider <-
        query @EmailDeliveryProviderState
            |> filterWhere (#emailDeliveryJobId, Id (unpackId original.id))
            |> fetchOneOrNothing
    pure $
        original.status `elem` [JobStatusFailed, JobStatusTimedOut]
            || maybe False ((`elem` ["bounced", "complained", "failed", "suppressed"]) . (.providerStatus)) provider
            || deliveryWasDisabled original

deliveryWasDisabled :: AppJob -> Bool
deliveryWasDisabled original =
    AesonTypes.parseMaybe (Aeson.withObject "email result" (Aeson..: "deliveryStatus")) original.result
        == Just ("delivery_disabled" :: Text)
