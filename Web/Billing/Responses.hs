module Web.Billing.Responses
    ( respondWithBillingCheckout
    , respondWithBillingPortal
    , respondWithBillingReconciliation
    , redirectToCorrelatedCheckoutReturn
    , billingRedirectWithError
    ) where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Billing.Checkout (CheckoutStartOutcome (..),
                                     CheckoutStartResult (..))
import Application.Billing.Reconciliation (BillingReconciliationFailure (..))
import Application.Billing.Stripe
import Application.Helper.Url (appendQueryParams)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude

-- These are completion consumers, not provider workflows. The existing start
-- audits intentionally occur after provider/host validation, outside committed
-- Checkout phases and before the terminal HTTP response. Do not move them into
-- preparation or record a successful start on a rejected redirect.
respondWithBillingCheckout :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => CheckoutStartResult -> IO ResponseReceived
respondWithBillingCheckout checkoutResult =
    case checkoutResult.checkoutStartOutcome of
        CheckoutStartRejected message -> billingRedirectWithError message
        CheckoutAwaitingWebhook attempt -> redirectToCorrelatedCheckoutReturn attempt
        CheckoutSessionReady attempt checkoutSession ->
            case checkoutSession.stripeCheckoutSessionUrl of
                Nothing -> billingRedirectWithError "Stripe Checkout did not return a hosted session URL."
                Just checkoutUrl ->
                    validateStripeCheckoutRedirectUrl checkoutUrl >>= \case
                        Left message -> billingRedirectWithError message
                        Right validatedCheckoutUrl -> do
                            void $ recordCurrentUserAuditEvent
                                BillingCheckoutStartedAudit
                                "billing_checkout_attempts"
                                (unpackId attempt.id)
                                (Aeson.object
                                    [ "stripeCustomerId" Aeson..= attempt.stripeCustomerId
                                    , "stripeCheckoutSessionId" Aeson..= checkoutSession.stripeCheckoutSessionId
                                    , "stripePriceId" Aeson..= attempt.stripePriceId
                                    , "resumed" Aeson..= not checkoutResult.checkoutAttemptWasCreated
                                    ])
                            redirectToBillingUrl validatedCheckoutUrl

respondWithBillingPortal :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => VenueBillingCustomer -> Text -> Either StripeClientError StripePortalSession -> IO ResponseReceived
respondWithBillingPortal billingCustomer returnUrl = \case
    Left err -> billingRedirectWithError ("Stripe Customer Portal failed: " <> stripeClientErrorText err)
    Right portalSession ->
        case validateCreatedPortalSession billingCustomer.stripeCustomerId returnUrl portalSession of
            Left message -> billingRedirectWithError message
            Right validatedPortalSession ->
                validateStripePortalRedirectUrl validatedPortalSession.stripePortalSessionUrl >>= \case
                    Left message -> billingRedirectWithError message
                    Right validatedPortalUrl -> do
                        void $ recordCurrentUserAuditEvent
                            BillingPortalStartedAudit
                            "venue_billing_customers"
                            (unpackId billingCustomer.id)
                            (Aeson.object
                                [ "stripeCustomerId" Aeson..= billingCustomer.stripeCustomerId
                                , "stripePortalSessionId" Aeson..= validatedPortalSession.stripePortalSessionId
                                ])
                        redirectToBillingUrl validatedPortalUrl

respondWithBillingReconciliation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Either BillingReconciliationFailure EnqueueAppJobResult -> IO ResponseReceived
respondWithBillingReconciliation = \case
    Left failure -> billingRedirectWithError failure.reconciliationFailureSummary
    Right enqueueResult -> do
        let (appJob, alreadyActive) = case enqueueResult of
                EnqueuedAppJob job       -> (job, False)
                ExistingActiveAppJob job -> (job, True)
        void $ recordCurrentUserAuditEvent
            BillingReconciliationRequestedAudit
            "app_jobs"
            (unpackId appJob.id)
            ( Aeson.object
                [ "alreadyActive" Aeson..= alreadyActive
                , "relatedTable" Aeson..= appJob.relatedTable
                , "relatedId" Aeson..= appJob.relatedId
                ]
            )
        setSuccessMessage $
            if alreadyActive
                then "Billing synchronization is already queued."
                else "Billing synchronization queued."
        redirectTo BillingAction

-- Both callers already hold a correlated attempt. Keep the defensive missing
-- Session failure for resumed Checkout and never expose the Session in the URL.
redirectToCorrelatedCheckoutReturn :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => BillingCheckoutAttempt -> IO ResponseReceived
redirectToCorrelatedCheckoutReturn attempt =
    case attempt.stripeCheckoutSessionId of
        Nothing -> billingRedirectWithError "The open Checkout attempt has no Stripe Session to resume."
        Just _ ->
            redirectToPath $
                appendQueryParams
                    (pathTo BillingAction)
                    [ ("checkout", "success")
                    , ("attempt_id", inputValue attempt.id)
                    ]

billingRedirectWithError :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ResponseReceived
billingRedirectWithError message = do
    setErrorMessage message
    redirectTo BillingAction

redirectToBillingUrl :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Text -> IO ResponseReceived
redirectToBillingUrl url =
    if isHtmxRequest
        then do
            setHeader ("HX-Redirect", cs url)
            renderPlain ""
        else redirectToUrl url
