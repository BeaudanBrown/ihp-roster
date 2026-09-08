module Application.Billing.Persistence
    ( lockStripeEventForWebhook
    , lockVenueForBilling
    , lockVenueForCheckout
    )
where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Data.Tuple.Only (Only (..))
import IHP.ControllerPrelude
import IHP.ModelSupport (unsafeSqlQuery)

-- An event-ID transaction lock makes duplicate delivery serialization
-- independent of whether the event can be associated with a venue.
lockStripeEventForWebhook :: (?modelContext :: ModelContext) => Text -> IO ()
lockStripeEventForWebhook eventId = do
    lockResults :: [Only Bool] <-
        unsafeSqlQuery
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS event_lock"
            (Only eventId)
    unless (lockResults == [Only True]) do
        externalRuntimeInvariantFailure ProviderRuntimeInvariant "Unable to lock the Stripe webhook event"

-- IHP QueryBuilder does not expose SELECT ... FOR UPDATE. Keep the unavoidable
-- locking SQL isolated here rather than embedding it in the Checkout or webhook
-- state machines.
lockVenueForBilling :: (?modelContext :: ModelContext) => UUID -> IO ()
lockVenueForBilling venueId = do
    lockedVenueIds :: [Only UUID] <-
        unsafeSqlQuery
            "SELECT id FROM venues WHERE id = ? FOR UPDATE"
            (Only venueId)
    unless (length lockedVenueIds == 1) do
        externalRuntimeInvariantFailure ProviderRuntimeInvariant "Unable to lock the venue for billing"

lockVenueForCheckout :: (?modelContext :: ModelContext) => UUID -> IO ()
lockVenueForCheckout = lockVenueForBilling
