-- | Safe, independent queue and provider facts for customer-facing history.
-- Acceptance can coexist with a failed/retrying queue acknowledgement. Neither
-- a successful job nor SMTP acceptance proves inbox delivery.
module Application.EmailDelivery.Status
    ( DeliveryProgress (..), QueueProgress (..), ProviderProgress (..)
    , deliveryProgress, unavailableDelivery, cancelPendingDelivery
    ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Generated.Types
import IHP.ControllerPrelude

data QueueProgress = DeliveryQueued | DeliverySending | DeliveryRetrying
    | DeliveryFinished | DeliveryFailed | DeliverySkipped | DeliveryCancelled | DeliveryUnavailable
    deriving (Eq, Show)
data ProviderProgress = ProviderUnknown | ProviderAccepted | ProviderConfirmed | ProviderFailed
    deriving (Eq, Show)
data DeliveryProgress = DeliveryProgress
    { queue :: !QueueProgress
    , provider :: !ProviderProgress
    , acceptedAt :: !(Maybe UTCTime)
    , providerObservedAt :: !(Maybe UTCTime)
    } deriving (Eq, Show)

unavailableDelivery :: DeliveryProgress
unavailableDelivery = DeliveryProgress DeliveryUnavailable ProviderUnknown Nothing Nothing

deliveryProgress :: AppJob -> Maybe EmailDeliveryProviderState -> DeliveryProgress
deliveryProgress job state = DeliveryProgress { queue, provider, acceptedAt, providerObservedAt }
  where
    acceptedAt = state >>= (.smtpAcceptedAt)
    providerObservedAt = state >>= (.providerStatusAt)
    provider = case (.providerStatus) <$> state of
        Just "delivered" -> ProviderConfirmed
        Just status | status `elem` ["bounced", "complained", "failed", "suppressed"] -> ProviderFailed
        _ | isJust acceptedAt -> ProviderAccepted
        _ -> ProviderUnknown
    queue = case job.status of
        JobStatusNotStarted -> DeliveryQueued
        JobStatusRunning -> DeliverySending
        JobStatusRetry -> DeliveryRetrying
        JobStatusFailed -> DeliveryFailed
        JobStatusTimedOut -> DeliveryFailed
        JobStatusSucceeded -> case Aeson.parseMaybe (Aeson.withObject "delivery result" (Aeson..: "deliveryStatus")) job.result :: Maybe Text of
            Just "sent" -> DeliveryFinished
            Just "delivery_skipped" -> DeliverySkipped
            Just "delivery_disabled" -> DeliverySkipped
            _ -> DeliveryUnavailable

-- Removal cancels remaining attempts, not already-accepted/in-flight mail.
-- Preserve provider facts even if a removed recipient's job has not run again.
cancelPendingDelivery :: DeliveryProgress -> DeliveryProgress
cancelPendingDelivery progress = case progress.queue of
    DeliveryQueued -> progress { queue = DeliveryCancelled }
    DeliveryRetrying -> progress { queue = DeliveryCancelled }
    DeliverySending -> progress { queue = DeliveryCancelled }
    _ -> progress
