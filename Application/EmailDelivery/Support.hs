module Application.EmailDelivery.Support
    ( NotificationDeliveryHealth (..)
    , NotificationIncidentEventHealth (..)
    , NotificationHealth (..)
    , fetchNotificationHealth
    ) where

import Application.EmailDelivery.Enqueue (emailDeliveryJobKind)
import Application.OperationalIncident.Types (operationalIncidentMailKind)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Map.Strict as Map
import Generated.Types
import IHP.ControllerPrelude

data NotificationDeliveryHealth = NotificationDeliveryHealth
    { job            :: !AppJob
    , mailKind       :: !(Maybe Text)
    , providerState  :: !(Maybe EmailDeliveryProviderState)
    , deliveryStatus :: !(Maybe Text)
    , canResend      :: !Bool
    }

data NotificationIncidentEventHealth = NotificationIncidentEventHealth
    { event                  :: !OperationalIncidentEvent
    , recipientSnapshotCount :: !Int
    , deliveredCount         :: !Int
    , failedCount            :: !Int
    , pendingCount           :: !Int
    }

data NotificationHealth = NotificationHealth
    { openIncidents        :: ![OperationalIncident]
    , recentIncidentEvents :: ![NotificationIncidentEventHealth]
    , zeroRecipientEvents  :: ![OperationalIncidentEvent]
    , recentDeliveries     :: ![NotificationDeliveryHealth]
    , recentHostDispatches :: ![HostWatchdogDispatch]
    , hostWatchdogStatus   :: !(Maybe HostWatchdogStatus)
    }

fetchNotificationHealth :: (?modelContext :: ModelContext) => IO NotificationHealth
fetchNotificationHealth = do
    openIncidents <-
        query @OperationalIncident
            |> filterWhere (#state, "open" :: Text)
            |> orderByDesc #lastObservedAt
            |> limit 50
            |> fetch
    incidentEvents <-
        query @OperationalIncidentEvent
            |> orderByDesc #observedAt
            |> limit 50
            |> fetch
    eventRecipients <-
        query @OperationalIncidentEventRecipient
            |> filterWhereIn (#operationalIncidentEventId, map (unpackId . (.id)) incidentEvents)
            |> fetch
    eventJobs <-
        query @AppJob
            |> filterWhereIn (#id, map (Id . (.emailDeliveryJobId)) eventRecipients)
            |> fetch
    eventProviderStates <-
        query @EmailDeliveryProviderState
            |> filterWhereIn (#emailDeliveryJobId, map (Id . unpackId . (.id)) eventJobs)
            |> fetch
    let eventJobsById = Map.fromList [(unpackId appJob.id, appJob) | appJob <- eventJobs]
        eventStatesByJob = Map.fromList [(unpackId state.emailDeliveryJobId, state) | state <- eventProviderStates]
        recipientsByEvent = Map.fromListWith (<>) [(recipient.operationalIncidentEventId, [recipient]) | recipient <- eventRecipients]
        recentIncidentEvents = map (incidentEventHealth recipientsByEvent eventJobsById eventStatesByJob) incidentEvents
        zeroRecipientEvents = filter ((== 0) . (.eligibleRecipientCount)) incidentEvents
    jobs <-
        query @AppJob
            |> filterWhere (#jobKind, emailDeliveryJobKind)
            |> orderByDesc #createdAt
            |> limit 50
            |> fetch
    states <-
        query @EmailDeliveryProviderState
            |> filterWhereIn (#emailDeliveryJobId, map (Id . unpackId . (.id)) jobs)
            |> fetch
    let statesByJob = Map.fromList [(unpackId state.emailDeliveryJobId, state) | state <- states]
    let recentDeliveries = map (deliveryHealth statesByJob) jobs
    recentHostDispatches <-
        query @HostWatchdogDispatch
            |> orderByDesc #attemptedAt
            |> limit 50
            |> fetch
    hostWatchdogStatus <- query @HostWatchdogStatus |> fetchOneOrNothing
    pure NotificationHealth { .. }

incidentEventHealth ::
    Map.Map UUID [OperationalIncidentEventRecipient] ->
    Map.Map UUID AppJob ->
    Map.Map UUID EmailDeliveryProviderState ->
    OperationalIncidentEvent ->
    NotificationIncidentEventHealth
incidentEventHealth recipientsByEvent jobsById statesByJob event =
    let recipients = Map.findWithDefault [] (unpackId event.id) recipientsByEvent
        outcomes = map (recipientOutcome jobsById statesByJob) recipients
        recipientSnapshotCount = length recipients
        deliveredCount = length (filter (== "delivered") outcomes)
        failedCount = length (filter (== "failed") outcomes)
        pendingCount = recipientSnapshotCount - deliveredCount - failedCount
     in NotificationIncidentEventHealth { .. }

recipientOutcome :: Map.Map UUID AppJob -> Map.Map UUID EmailDeliveryProviderState -> OperationalIncidentEventRecipient -> Text
recipientOutcome jobsById statesByJob recipient =
    case Map.lookup recipient.emailDeliveryJobId jobsById of
        Nothing -> "pending"
        Just appJob
            | appJob.status `elem` [JobStatusFailed, JobStatusTimedOut] -> "failed"
            | payloadText "deliveryStatus" appJob.result == Just "delivery_disabled" -> "failed"
            | otherwise -> case (.providerStatus) <$> Map.lookup recipient.emailDeliveryJobId statesByJob of
                Just "delivered" -> "delivered"
                Just status | status `elem` ["bounced", "complained", "failed", "suppressed"] -> "failed"
                _ -> "pending"

deliveryHealth :: Map.Map UUID EmailDeliveryProviderState -> AppJob -> NotificationDeliveryHealth
deliveryHealth states appJob =
    let mailKind = payloadText "mailKind" appJob.payload
        deliveryStatus = payloadText "deliveryStatus" appJob.result
        providerState = Map.lookup (unpackId appJob.id) states
        providerFailed = maybe False ((`elem` ["bounced", "complained", "failed", "suppressed"]) . (.providerStatus)) providerState
        queueFailed = appJob.status `elem` [JobStatusFailed, JobStatusTimedOut]
        canResend = mailKind == Just operationalIncidentMailKind && (providerFailed || queueFailed || deliveryStatus == Just "delivery_disabled")
     in NotificationDeliveryHealth { job = appJob, .. }

payloadText :: Text -> Aeson.Value -> Maybe Text
payloadText key = AesonTypes.parseMaybe (Aeson.withObject "bounded email metadata" (Aeson..: AesonKey.fromText key))
