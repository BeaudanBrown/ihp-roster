module Web.Controller.StripeWebhooks where

import Application.Billing.Stripe
import Application.Billing.Webhook
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Control.Exception (SomeException, try)
import qualified Data.Set as Set
import qualified Data.Text.Encoding as TextEncoding
import Network.HTTP.Types.Status (Status, status400, status500)
import qualified Network.Wai as Wai
import Web.Billing.Mutations (billingTouchedResources)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutationOutcome)

instance Controller StripeWebhooksController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@StripeWebhookAction = runBepis currentAction BepisIntegrationAction do
        rawBody <- getRequestBody
        signatureHeader <- requireStripeSignatureHeader
        readStripeConfig >>= \case
            Left message ->
                renderPlainWithStatus status500 message
            Right stripeConfig ->
                verifyStripeWebhookSignature stripeConfig.webhookSecret signatureHeader rawBody >>= \case
                    Left message ->
                        renderPlainWithStatus status400 message
                    Right _ -> do
                        processing <- try $
                            withDurableLiveMutationOutcome billingWebhookPublication $
                                handleStripeWebhookPayloadInCurrentTransaction stripeConfig.stripeMode rawBody
                        case processing of
                            Left (_ :: SomeException) ->
                                renderPlainWithStatus status500 "Stripe webhook processing failed"
                            Right (Left message) ->
                                renderPlainWithStatus status400 message
                            Right (Right _) -> renderPlain "ok"

billingWebhookPublication :: Either Text BillingWebhookResult -> Maybe (Text, Set.Set SurfaceResourceValue)
billingWebhookPublication = \case
    Left _ -> Nothing
    Right result -> do
        venueId <- billingWebhookVenueId result
        pure ("billing.webhook", Set.fromList (billingTouchedResources (Id venueId)))

billingWebhookVenueId :: BillingWebhookResult -> Maybe UUID
billingWebhookVenueId = \case
    BillingWebhookProcessed event -> event.venueId
    BillingWebhookDuplicate event -> event.venueId
    BillingWebhookIgnored event -> event.venueId

requireStripeSignatureHeader :: (?context :: ControllerContext, ?request :: Request) => IO Text
requireStripeSignatureHeader =
    case lookup "Stripe-Signature" (Wai.requestHeaders ?request) of
        Just value -> pure (TextEncoding.decodeUtf8 value)
        Nothing -> renderPlainWithStatus status400 "Stripe-Signature header is required"

renderPlainWithStatus :: (?request :: Request) => Status -> Text -> IO value
renderPlainWithStatus status message =
    respondAndStop (Wai.responseLBS status [("Content-Type", "text/plain")] (cs message))
