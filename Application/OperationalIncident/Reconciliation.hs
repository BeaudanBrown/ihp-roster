module Application.OperationalIncident.Reconciliation
    ( reconcileOperationalIncident
    ) where

import Application.EmailDelivery.Enqueue
import Application.OperationalIncident.Persistence
import Application.OperationalIncident.Types
import qualified "crypton" Crypto.Hash as Hash
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types (JobStatus (JobStatusSucceeded))

reconcileOperationalIncident ::
    (?modelContext :: ModelContext) =>
    IncidentObservation ->
    IO ReconciliationResult
reconcileOperationalIncident observation = withTransaction do
    lockIncidentIdentity (incidentLockKey observation)
    existing <-
        query @OperationalIncident
            |> filterWhere (#category, observation.category)
            |> filterWhere (#scopeKey, observation.scopeKey)
            |> filterWhere (#stableIdentity, observation.stableIdentity)
            |> fetchOneOrNothing
    reconcileLocked observation existing

reconcileLocked ::
    (?modelContext :: ModelContext) =>
    IncidentObservation ->
    Maybe OperationalIncident ->
    IO ReconciliationResult
reconcileLocked observation Nothing
    | not observation.isActive = pure (IncidentUnchanged Nothing)
    | otherwise = do
        incident <- createIncident observation
        recordTransition observation incident 1 IncidentOpened True
reconcileLocked observation (Just incident)
    | observation.isActive && incident.state == "resolved" = do
        let occurrence = incident.occurrenceCount + 1
        reopened <-
            incident
                |> set #lastObservedAt observation.observedAt
                |> set #openedAt observation.observedAt
                |> set #resolvedAt Nothing
                |> set #state "open"
                |> set #severity (incidentSeverityText observation.severity)
                |> set #impactKey observation.impactKey
                |> set #impactRank observation.impactRank
                |> set #symptomCodes (Aeson.toJSON observation.symptomCodes)
                |> set #safeMetadata observation.safeMetadata
                |> set #occurrenceCount occurrence
                |> updateRecord
        sequenceNumber <- nextSequence incident
        recordTransition observation reopened sequenceNumber IncidentRecurred True
    | observation.isActive && observation.impactRank > incident.impactRank = do
        escalated <- updateObservedIncident observation incident
        sequenceNumber <- nextSequence incident
        recordTransition observation escalated sequenceNumber IncidentImpactEscalated True
    | observation.isActive = do
        updated <- updateObservedIncident observation incident
        pure (IncidentUnchanged (Just updated))
    | incident.state == "resolved" = pure (IncidentUnchanged (Just incident))
    | otherwise = do
        dispatched <- incidentHadDispatchedNotification incident
        resolved <-
            incident
                |> set #lastObservedAt observation.observedAt
                |> set #resolvedAt (Just observation.observedAt)
                |> set #state "resolved"
                |> set #symptomCodes (Aeson.toJSON observation.symptomCodes)
                |> set #safeMetadata observation.safeMetadata
                |> updateRecord
        sequenceNumber <- nextSequence incident
        recordTransition observation resolved sequenceNumber IncidentRecovered dispatched

createIncident :: (?modelContext :: ModelContext) => IncidentObservation -> IO OperationalIncident
createIncident observation =
    newRecord @OperationalIncident
        |> set #category observation.category
        |> set #scopeKey observation.scopeKey
        |> set #stableIdentity observation.stableIdentity
        |> set #affectedSource observation.affectedSource
        |> set #venueId observation.venueId
        |> set #firstObservedAt observation.observedAt
        |> set #lastObservedAt observation.observedAt
        |> set #openedAt observation.observedAt
        |> set #resolvedAt Nothing
        |> set #state "open"
        |> set #severity (incidentSeverityText observation.severity)
        |> set #impactKey observation.impactKey
        |> set #impactRank observation.impactRank
        |> set #symptomCodes (Aeson.toJSON observation.symptomCodes)
        |> set #safeMetadata observation.safeMetadata
        |> set #occurrenceCount 1
        |> createRecord

updateObservedIncident ::
    (?modelContext :: ModelContext) =>
    IncidentObservation ->
    OperationalIncident ->
    IO OperationalIncident
updateObservedIncident observation incident =
    incident
        |> set #lastObservedAt observation.observedAt
        |> set #severity (incidentSeverityText observation.severity)
        |> set #impactKey observation.impactKey
        |> set #impactRank (max incident.impactRank observation.impactRank)
        |> set #symptomCodes (Aeson.toJSON observation.symptomCodes)
        |> set #safeMetadata observation.safeMetadata
        |> updateRecord

recordTransition ::
    (?modelContext :: ModelContext) =>
    IncidentObservation ->
    OperationalIncident ->
    Int ->
    IncidentTransition ->
    Bool ->
    IO ReconciliationResult
recordTransition observation incident sequenceNumber transition notificationRequired = do
    event <-
        newRecord @OperationalIncidentEvent
            |> set #operationalIncidentId (unpackId incident.id)
            |> set #eventSequence sequenceNumber
            |> set #transition (incidentTransitionText transition)
            |> set #eventKey (transitionEventKey incident sequenceNumber transition observation.impactKey)
            |> set #observedAt observation.observedAt
            |> set #severity (incidentSeverityText observation.severity)
            |> set #impactKey observation.impactKey
            |> set #symptomCodes (Aeson.toJSON observation.symptomCodes)
            |> set #safeMetadata observation.safeMetadata
            |> set #notificationRequired notificationRequired
            |> set #eligibleRecipientCount 0
            |> set #recipientsReconciledAt Nothing
            |> createRecord
    recipients <- if notificationRequired then activeSuperAdmins else pure []
    forM_ recipients (enqueueRecipient incident event)
    reconciledEvent <-
        event
            |> set #eligibleRecipientCount (length recipients)
            |> set #recipientsReconciledAt (Just observation.observedAt)
            |> updateRecord
    pure (IncidentTransitionRecorded incident reconciledEvent transition)

activeSuperAdmins :: (?modelContext :: ModelContext) => IO [User]
activeSuperAdmins =
    query @User
        |> filterWhere (#platformRole, Just SuperAdmin)
        |> filterWhere (#deactivatedAt, Nothing)
        |> orderByAsc #id
        |> fetch

enqueueRecipient ::
    (?modelContext :: ModelContext) =>
    OperationalIncident ->
    OperationalIncidentEvent ->
    User ->
    IO ()
enqueueRecipient incident event recipient = do
    job <-
        enqueueEmailDelivery
            EmailDeliveryRequest
                { mailKind = operationalIncidentMailKind
                , recipientAccountId = unpackId recipient.id
                , recipientAddress = recipient.email
                , domainReferenceTable = "operational_incident_events"
                , domainReferenceId = unpackId event.id
                , semanticEventKey = event.eventKey
                , requestedByUserId = Nothing
                , venueId = incident.venueId
                }
    _ <-
        newRecord @OperationalIncidentEventRecipient
            |> set #operationalIncidentEventId (unpackId event.id)
            |> set #recipientUserId (unpackId recipient.id)
            |> set #recipientAddress recipient.email
            |> set #recipientAddressDigest (recipientDigest recipient.email)
            |> set #emailDeliveryJobId (unpackId job.id)
            |> createRecord
    pure ()

nextSequence :: (?modelContext :: ModelContext) => OperationalIncident -> IO Int
nextSequence incident = do
    events <-
        query @OperationalIncidentEvent
            |> filterWhere (#operationalIncidentId, unpackId incident.id)
            |> orderByDesc #eventSequence
            |> limit 1
            |> fetch
    pure $ maybe 1 ((+ 1) . (.eventSequence)) (headMay events)

incidentHadDispatchedNotification ::
    (?modelContext :: ModelContext) =>
    OperationalIncident ->
    IO Bool
incidentHadDispatchedNotification incident = do
    events <-
        query @OperationalIncidentEvent
            |> filterWhere (#operationalIncidentId, unpackId incident.id)
            |> fetch
    recipients <-
        query @OperationalIncidentEventRecipient
            |> filterWhereIn (#operationalIncidentEventId, map (unpackId . (.id)) events)
            |> fetch
    jobs <-
        query @AppJob
            |> filterWhereIn (#id, map (Id . (.emailDeliveryJobId)) recipients)
            |> fetch
    pure (any wasDispatched jobs)

wasDispatched :: AppJob -> Bool
wasDispatched job =
    job.status == JobStatusSucceeded
        && AesonTypes.parseMaybe (Aeson.withObject "email result" (Aeson..: "deliveryStatus")) job.result == Just ("sent" :: Text)

incidentLockKey :: IncidentObservation -> Text
incidentLockKey observation =
    Text.intercalate ":" ["operational-incident", observation.category, observation.scopeKey, observation.stableIdentity]

transitionEventKey :: OperationalIncident -> Int -> IncidentTransition -> Text -> Text
transitionEventKey incident sequenceNumber transition impactKey =
    Text.intercalate
        ":"
        [ "operational-incident"
        , tshow (unpackId incident.id)
        , tshow sequenceNumber
        , incidentTransitionText transition
        , impactKey
        ]

recipientDigest :: Text -> Text
recipientDigest address =
    tshow
        ( Hash.hash
            (TextEncoding.encodeUtf8 (Text.toCaseFold (Text.strip address))) :: Hash.Digest Hash.SHA256
        )
