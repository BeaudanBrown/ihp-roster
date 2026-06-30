module Web.Controller.StripeWebhooks where

import Application.Billing.Stripe
import Application.Billing.Webhook
import qualified Data.Text.Encoding as TextEncoding
import Network.HTTP.Types.Status (Status, status400, status500)
import qualified Network.Wai as Wai
import Web.Billing.Mutations (recordBillingWebhookMutation)
import Web.Controller.Prelude

instance Controller StripeWebhooksController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@StripeWebhookAction = bepisIntegrationAction currentAction do
        rawBody <- getRequestBody
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
                                _ <- recordBillingWebhookMutation result
                                renderPlain "ok"

requireStripeSignatureHeader :: (?context :: ControllerContext, ?request :: Request) => IO Text
requireStripeSignatureHeader =
    case lookup "Stripe-Signature" (Wai.requestHeaders ?request) of
        Just value -> pure (TextEncoding.decodeUtf8 value)
        Nothing -> renderPlainWithStatus status400 "Stripe-Signature header is required"

renderPlainWithStatus :: (?request :: Request) => Status -> Text -> IO value
renderPlainWithStatus status message = do
    respondAndExit (Wai.responseLBS status [("Content-Type", "text/plain")] (cs message))
    error "unreachable"
