module Application.EmailDelivery.Support
    ( NotificationDeliveryHealth (..)
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
import IHP.Job.Types (JobStatus (JobStatusFailed, JobStatusTimedOut))

data NotificationDeliveryHealth = NotificationDeliveryHealth
    { job            :: !AppJob
    , mailKind       :: !(Maybe Text)
    , providerState  :: !(Maybe EmailDeliveryProviderState)
    , deliveryStatus :: !(Maybe Text)
    , canResend      :: !Bool
    }

data NotificationHealth = NotificationHealth
    { openIncidents       :: ![OperationalIncident]
    , zeroRecipientEvents :: ![OperationalIncidentEvent]
    , recentDeliveries    :: ![NotificationDeliveryHealth]
    }

fetchNotificationHealth :: (?modelContext :: ModelContext) => IO NotificationHealth
fetchNotificationHealth = do
    openIncidents <-
        query @OperationalIncident
            |> filterWhere (#state, "open" :: Text)
            |> orderByDesc #lastObservedAt
            |> limit 50
            |> fetch
    zeroRecipientEvents <-
        query @OperationalIncidentEvent
            |> filterWhere (#eligibleRecipientCount, 0)
            |> orderByDesc #observedAt
            |> limit 25
            |> fetch
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
    pure NotificationHealth { .. }

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
