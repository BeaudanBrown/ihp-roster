module Web.Controller.ResendWebhooks where

import Application.EmailDelivery.ResendWebhook
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Network.HTTP.Types.Status (Status, status400, status500)
import qualified Network.Wai as Wai
import qualified System.Environment as Environment
import Web.Controller.Prelude

instance Controller ResendWebhooksController where
    beforeAction = bepisBeforeAction BepisPublicController annotateTelemetryAction

    action currentAction@ResendWebhookAction = runBepis currentAction BepisIntegrationAction do
        rawBody <- getRequestBody
        headers <- requireResendHeaders
        maybeSecret <- liftIO (fmap (fmap (Text.strip . cs)) (Environment.lookupEnv "RESEND_WEBHOOK_SECRET"))
        case maybeSecret of
            Nothing -> renderPlainWithStatus status500 "Resend webhook is not configured"
            Just secret -> do
                now <- getCurrentTime
                handleResendWebhook now secret headers rawBody >>= \case
                    Left message -> renderPlainWithStatus status400 message
                    Right _ -> renderPlain "ok"

requireResendHeaders ::
    (?respond :: Respond, ?context :: ControllerContext, ?request :: Request) =>
    IO ResendWebhookHeaders
requireResendHeaders =
    case (header "svix-id", header "svix-timestamp", header "svix-signature") of
        (Just svixId, Just svixTimestamp, Just svixSignature) ->
            pure ResendWebhookHeaders { svixId, svixTimestamp, svixSignature }
        _ -> renderPlainWithStatus status400 "Svix signature headers are required"
  where
    header name = TextEncoding.decodeUtf8 <$> lookup name (Wai.requestHeaders ?request)

renderPlainWithStatus :: (?respond :: Respond, ?request :: Request) => Status -> Text -> IO value
renderPlainWithStatus status message =
    respondAndStop (Wai.responseLBS status [("Content-Type", "text/plain")] (cs message))
