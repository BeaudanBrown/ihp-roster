module Application.Billing.NotificationKind
    ( BillingNotificationKind (..)
    , billingNotificationKindText
    , parseBillingNotificationKind
    ) where

import IHP.Prelude

data BillingNotificationKind
    = BillingPaymentTrouble
    | BillingPaymentRecovered
    | BillingCancellationScheduled
    | BillingRenewalResumed
    | BillingCancellationCompleted
    | BillingCheckoutPaymentFailed
    | BillingOperationalRetriesExhausted
    deriving (Eq, Show)

billingNotificationKindText :: BillingNotificationKind -> Text
billingNotificationKindText = \case
    BillingPaymentTrouble              -> "payment_trouble"
    BillingPaymentRecovered            -> "payment_recovered"
    BillingCancellationScheduled       -> "cancellation_scheduled"
    BillingRenewalResumed               -> "renewal_resumed"
    BillingCancellationCompleted       -> "cancellation_completed"
    BillingCheckoutPaymentFailed       -> "checkout_payment_failed"
    BillingOperationalRetriesExhausted -> "operational_retries_exhausted"

parseBillingNotificationKind :: Text -> Maybe BillingNotificationKind
parseBillingNotificationKind = \case
    "payment_trouble"               -> Just BillingPaymentTrouble
    "payment_recovered"             -> Just BillingPaymentRecovered
    "cancellation_scheduled"        -> Just BillingCancellationScheduled
    "renewal_resumed"               -> Just BillingRenewalResumed
    "cancellation_completed"        -> Just BillingCancellationCompleted
    "checkout_payment_failed"       -> Just BillingCheckoutPaymentFailed
    "operational_retries_exhausted" -> Just BillingOperationalRetriesExhausted
    -- Keep already-queued pre-transition payloads readable across deployment.
    "payment_failed"                -> Just BillingPaymentTrouble
    "past_due"                      -> Just BillingPaymentTrouble
    "unpaid"                        -> Just BillingPaymentTrouble
    "incomplete_expired"            -> Just BillingPaymentTrouble
    "async_payment_failed"          -> Just BillingCheckoutPaymentFailed
    "canceled"                      -> Just BillingCancellationCompleted
    _                               -> Nothing
