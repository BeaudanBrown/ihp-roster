module Web.Controller.StripeWebhooks where

import Application.Billing.Stripe
import Application.Billing.Webhook
import Application.Helper.SurfaceResource (liveMutationResult)
import Control.Exception (SomeException, try)
import Control.Monad (void)
import qualified Data.Text.Encoding as TextEncoding
import Network.HTTP.Types.Status (Status, status400, status500)
import qualified Network.Wai as Wai
import Web.Billing.Mutations (billingTouchedResources)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResourcesWithoutContext)

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
                        processing <- try (handleStripeWebhookPayload stripeConfig.stripeMode rawBody)
                        case processing of
                            Left (_ :: SomeException) ->
                                renderPlainWithStatus status500 "Stripe webhook processing failed"
                            Right (Left message) ->
                                renderPlainWithStatus status400 message
                            Right (Right result) -> do
                                _ <- try (invalidateBillingWebhookResult result) :: IO (Either SomeException ())
                                renderPlain "ok"

invalidateBillingWebhookResult :: (?modelContext :: ModelContext) => BillingWebhookResult -> IO ()
invalidateBillingWebhookResult result =
    forM_ (billingWebhookVenueId result) \venueId ->
        void $
            invalidateTouchedResourcesWithoutContext "billing.webhook" $
                liveMutationResult result (billingTouchedResources (Id venueId))

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
renderPlainWithStatus status message = do
    respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain")] (cs message))
    error "unreachable"
