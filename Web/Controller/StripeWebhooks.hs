module Web.Controller.StripeWebhooks where

import Application.Billing.Stripe
import Application.Billing.Webhook
import qualified Data.Text.Encoding as TextEncoding
import Network.HTTP.Types.Status (Status, status400, status500)
import qualified Network.Wai as Wai
import Web.Billing.LiveUpdates (BillingSurfaceKey (..), broadcastBillingInvalidationForVenue)
import Web.Controller.Prelude

instance Controller StripeWebhooksController where
    action StripeWebhookAction = do
        rawBody <- Wai.strictRequestBody ?request
        signatureHeader <- requireStripeSignatureHeader
        readStripeConfig >>= \case
            Left message ->
                renderPlainWithStatus status500 message
            Right stripeConfig ->
                verifyStripeWebhookSignature stripeConfig.webhookSecret signatureHeader rawBody >>= \case
                    Left message ->
                        renderPlainWithStatus status400 message
                    Right _ ->
                        handleStripeWebhookPayload rawBody >>= \case
                            Left message ->
                                renderPlainWithStatus status400 message
                            Right result -> do
                                broadcastBillingWebhookResult result
                                renderPlain "ok"

requireStripeSignatureHeader :: (?context :: ControllerContext, ?request :: Request) => IO Text
requireStripeSignatureHeader =
    case lookup "Stripe-Signature" (Wai.requestHeaders ?request) of
        Just value -> pure (TextEncoding.decodeUtf8 value)
        Nothing -> renderPlainWithStatus status400 "Stripe-Signature header is required"

broadcastBillingWebhookResult :: BillingWebhookResult -> IO ()
broadcastBillingWebhookResult result =
    case billingWebhookResultVenueId result of
        Nothing -> pure ()
        Just venueId -> broadcastBillingInvalidationForVenue BillingSurfaceKey { billingSurfaceVenueId = venueId }

billingWebhookResultVenueId :: BillingWebhookResult -> Maybe UUID
billingWebhookResultVenueId (BillingWebhookProcessed event) = event.venueId
billingWebhookResultVenueId (BillingWebhookDuplicate event) = event.venueId
billingWebhookResultVenueId (BillingWebhookIgnored event) = event.venueId

renderPlainWithStatus :: (?request :: Request) => Status -> Text -> IO value
renderPlainWithStatus status message = do
    respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain")] (cs message))
    error "unreachable"
